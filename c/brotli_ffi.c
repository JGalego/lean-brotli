#include <lean/lean.h>
#include <brotli/encode.h>
#include <brotli/decode.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>

/* =========================================================================
 * Helpers
 * ========================================================================= */

static lean_obj_res mk_byte_array(const uint8_t *data, size_t len) {
    lean_obj_res arr = lean_alloc_sarray(1, len, len);
    memcpy(lean_sarray_cptr(arr), data, len);
    return arr;
}

static lean_obj_res mk_io_error(const char *msg) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(msg)));
}

static lean_obj_res mk_dec_error(const char *prefix, BrotliDecoderErrorCode ec) {
    char buf[256];
    snprintf(buf, sizeof(buf), "%s: %s", prefix, BrotliDecoderErrorString(ec));
    return mk_io_error(buf);
}

static int brotli_quality_is_valid(uint8_t quality) {
    return quality <= 11;
}

/*
 * Grow a buffer, with overflow check.
 * Returns NULL on overflow or allocation failure. Frees old buffer on failure.
 */
static uint8_t *grow_buffer(uint8_t *buf, size_t *buf_size) {
    if (*buf_size > SIZE_MAX / 2) { free(buf); return NULL; }
    *buf_size *= 2;
    uint8_t *nb = (uint8_t *)realloc(buf, *buf_size);
    if (!nb) { free(buf); return NULL; }
    return nb;
}

/* =========================================================================
 * Whole-buffer compression
 *
 * lean_brotli_compress : @& ByteArray → UInt8 → IO ByteArray
 * ========================================================================= */

LEAN_EXPORT lean_obj_res lean_brotli_compress(b_lean_obj_arg data, uint8_t quality,
                                               lean_obj_arg _w) {
    if (!brotli_quality_is_valid(quality)) {
        return mk_io_error("brotli compress: quality must be in range 0..11");
    }

    const uint8_t *src = lean_sarray_cptr(data);
    size_t src_len = lean_sarray_size(data);

    size_t dest_cap = BrotliEncoderMaxCompressedSize(src_len);
    if (dest_cap == 0 && src_len > 0) {
        return mk_io_error("brotli compress: input too large for one-shot API; use streaming");
    }
    /* For empty input, ensure at least a small buffer */
    if (dest_cap == 0) dest_cap = 64;

    lean_obj_res arr = lean_alloc_sarray(1, 0, dest_cap);
    uint8_t *dest = lean_sarray_cptr(arr);
    size_t encoded_size = dest_cap;

    BROTLI_BOOL ok = BrotliEncoderCompress(
        (int)quality, BROTLI_DEFAULT_WINDOW, BROTLI_DEFAULT_MODE,
        src_len, src, &encoded_size, dest);
    if (!ok) {
        lean_dec_ref(arr);
        return mk_io_error("brotli compress: BrotliEncoderCompress failed");
    }

    lean_sarray_set_size(arr, encoded_size);
    return lean_io_result_mk_ok(arr);
}

/* =========================================================================
 * Whole-buffer decompression
 *
 * lean_brotli_decompress : @& ByteArray → UInt64 → IO ByteArray
 *
 * Brotli does not embed the decompressed size in the stream, so we use the
 * streaming API with a growable output buffer.
 * ========================================================================= */

LEAN_EXPORT lean_obj_res lean_brotli_decompress(b_lean_obj_arg data,
                                                 uint64_t max_output,
                                                 lean_obj_arg _w) {
    const uint8_t *src = lean_sarray_cptr(data);
    size_t src_len = lean_sarray_size(data);
    char errbuf[256];

    BrotliDecoderState *dec = BrotliDecoderCreateInstance(NULL, NULL, NULL);
    if (!dec) return mk_io_error("brotli decompress: failed to create decoder");

    size_t buf_size = src_len < SIZE_MAX / 4 ? src_len * 4 : src_len;
    if (buf_size < 65536) buf_size = 65536;
    uint8_t *buf = (uint8_t *)malloc(buf_size);
    if (!buf) {
        BrotliDecoderDestroyInstance(dec);
        return mk_io_error("brotli decompress: out of memory");
    }

    const uint8_t *next_in = src;
    size_t avail_in = src_len;
    size_t total = 0;
    BrotliDecoderResult result = BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT;

    while (result == BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT ||
           (result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT && avail_in > 0)) {
        if (total >= buf_size) {
            buf = grow_buffer(buf, &buf_size);
            if (!buf) {
                BrotliDecoderDestroyInstance(dec);
                return mk_io_error("brotli decompress: out of memory");
            }
        }

        size_t avail_out = buf_size - total;
        uint8_t *next_out = buf + total;
        size_t prev_avail_out = avail_out;

        result = BrotliDecoderDecompressStream(dec, &avail_in, &next_in,
                                               &avail_out, &next_out, NULL);
        total += (prev_avail_out - avail_out);

        if (max_output > 0 && total > max_output) {
            free(buf);
            BrotliDecoderDestroyInstance(dec);
            snprintf(errbuf, sizeof(errbuf),
                     "brotli decompress: decompressed size exceeds limit (%llu bytes)",
                     (unsigned long long)max_output);
            return mk_io_error(errbuf);
        }

        if (result == BROTLI_DECODER_RESULT_ERROR) {
            BrotliDecoderErrorCode ec = BrotliDecoderGetErrorCode(dec);
            lean_obj_res err = mk_dec_error("brotli decompress", ec);
            free(buf);
            BrotliDecoderDestroyInstance(dec);
            return err;
        }
    }

    if (!BrotliDecoderIsFinished(dec)) {
        free(buf);
        BrotliDecoderDestroyInstance(dec);
        return mk_io_error("brotli decompress: incomplete stream");
    }

    BrotliDecoderDestroyInstance(dec);
    lean_obj_res arr = mk_byte_array(buf, total);
    free(buf);
    return lean_io_result_mk_ok(arr);
}

/* =========================================================================
 * Streaming compression state
 * ========================================================================= */

typedef struct {
    BrotliEncoderState *encoder;
    int finished;
} brotli_compress_state;

typedef struct {
    BrotliDecoderState *decoder;
    int finished;
} brotli_decompress_state;

static lean_external_class *g_compress_class   = NULL;
static lean_external_class *g_decompress_class = NULL;
static pthread_once_t g_classes_once = PTHREAD_ONCE_INIT;

static void noop_foreach(void *mod, b_lean_obj_arg fn) {
    (void)mod; (void)fn;
}

static void compress_finalizer(void *p) {
    brotli_compress_state *s = (brotli_compress_state *)p;
    if (s->encoder) BrotliEncoderDestroyInstance(s->encoder);
    free(s);
}

static void decompress_finalizer(void *p) {
    brotli_decompress_state *s = (brotli_decompress_state *)p;
    if (s->decoder) BrotliDecoderDestroyInstance(s->decoder);
    free(s);
}

static void register_classes(void) {
    g_compress_class   = lean_register_external_class(compress_finalizer,   noop_foreach);
    g_decompress_class = lean_register_external_class(decompress_finalizer, noop_foreach);
}

/* =========================================================================
 * Streaming compression: new / push / finish
 *
 * lean_brotli_compress_new    : UInt8 → IO CompressState
 * lean_brotli_compress_push   : @& CompressState → @& ByteArray → IO ByteArray
 * lean_brotli_compress_finish : @& CompressState → IO ByteArray
 * ========================================================================= */

LEAN_EXPORT lean_obj_res lean_brotli_compress_new(uint8_t quality, lean_obj_arg _w) {
    pthread_once(&g_classes_once, register_classes);

    if (!brotli_quality_is_valid(quality)) {
        return mk_io_error("brotli compress: quality must be in range 0..11");
    }

    brotli_compress_state *s = (brotli_compress_state *)malloc(sizeof(*s));
    if (!s) return mk_io_error("brotli compress: out of memory");

    s->encoder  = BrotliEncoderCreateInstance(NULL, NULL, NULL);
    s->finished = 0;
    if (!s->encoder) {
        free(s);
        return mk_io_error("brotli compress: failed to create encoder");
    }

    BrotliEncoderSetParameter(s->encoder, BROTLI_PARAM_QUALITY, (uint32_t)quality);

    lean_obj_res obj = lean_alloc_external(g_compress_class, s);
    return lean_io_result_mk_ok(obj);
}

/*
 * Drive encoder with the given operation until all input is consumed and no
 * more output is buffered.  Returns all produced output as a ByteArray.
 */
static lean_obj_res encoder_drive(brotli_compress_state *s,
                                   const uint8_t *src, size_t src_len,
                                   BrotliEncoderOperation op) {
    const uint8_t *next_in = src;
    size_t avail_in = src_len;

    size_t buf_size = 65536;
    uint8_t *buf = (uint8_t *)malloc(buf_size);
    if (!buf) return mk_io_error("brotli compress: out of memory");
    size_t total = 0;

    for (;;) {
        if (total >= buf_size) {
            buf = grow_buffer(buf, &buf_size);
            if (!buf) return mk_io_error("brotli compress: out of memory");
        }

        size_t avail_out    = buf_size - total;
        uint8_t *next_out   = buf + total;
        size_t prev_avail_out = avail_out;

        BROTLI_BOOL ok = BrotliEncoderCompressStream(
            s->encoder, op,
            &avail_in, &next_in,
            &avail_out, &next_out, NULL);

        if (!ok) {
            free(buf);
            return mk_io_error("brotli compress: BrotliEncoderCompressStream failed");
        }

        total += (prev_avail_out - avail_out);

        /* Done when: input exhausted and no pending internal output */
        if (avail_in == 0 && !BrotliEncoderHasMoreOutput(s->encoder)) break;

        /* For FINISH we also check the IsFinished flag */
        if (op == BROTLI_OPERATION_FINISH && BrotliEncoderIsFinished(s->encoder)) break;
    }

    lean_obj_res arr = mk_byte_array(buf, total);
    free(buf);
    return lean_io_result_mk_ok(arr);
}

LEAN_EXPORT lean_obj_res lean_brotli_compress_push(b_lean_obj_arg state_obj,
                                                    b_lean_obj_arg chunk,
                                                    lean_obj_arg _w) {
    brotli_compress_state *s = lean_get_external_data(state_obj);
    if (s->finished)
        return mk_io_error("brotli compress: push after finish");

    const uint8_t *src = lean_sarray_cptr(chunk);
    size_t src_len     = lean_sarray_size(chunk);

    return encoder_drive(s, src, src_len, BROTLI_OPERATION_PROCESS);
}

LEAN_EXPORT lean_obj_res lean_brotli_compress_finish(b_lean_obj_arg state_obj,
                                                      lean_obj_arg _w) {
    brotli_compress_state *s = lean_get_external_data(state_obj);
    if (s->finished)
        return mk_io_error("brotli compress: finish called more than once");
    s->finished = 1;
    return encoder_drive(s, NULL, 0, BROTLI_OPERATION_FINISH);
}

/* =========================================================================
 * Streaming decompression: new / push / finish
 *
 * lean_brotli_decompress_new    : IO DecompressState
 * lean_brotli_decompress_push   : @& DecompressState → @& ByteArray → IO ByteArray
 * lean_brotli_decompress_finish : @& DecompressState → IO ByteArray
 * ========================================================================= */

LEAN_EXPORT lean_obj_res lean_brotli_decompress_new(lean_obj_arg _w) {
    pthread_once(&g_classes_once, register_classes);

    brotli_decompress_state *s = (brotli_decompress_state *)malloc(sizeof(*s));
    if (!s) return mk_io_error("brotli decompress: out of memory");

    s->decoder  = BrotliDecoderCreateInstance(NULL, NULL, NULL);
    s->finished = 0;
    if (!s->decoder) {
        free(s);
        return mk_io_error("brotli decompress: failed to create decoder");
    }

    lean_obj_res obj = lean_alloc_external(g_decompress_class, s);
    return lean_io_result_mk_ok(obj);
}

/*
 * Feed a chunk of compressed bytes into the decoder, returning all
 * decompressed output produced.  Stops when input is exhausted or an
 * error / end-of-stream is encountered.
 */
static lean_obj_res decoder_drive(brotli_decompress_state *s,
                                   const uint8_t *src, size_t src_len) {
    const uint8_t *next_in = src;
    size_t avail_in = src_len;

    size_t buf_size = src_len < SIZE_MAX / 4 ? src_len * 4 : src_len;
    if (buf_size < 65536) buf_size = 65536;
    uint8_t *buf = (uint8_t *)malloc(buf_size);
    if (!buf) return mk_io_error("brotli decompress: out of memory");
    size_t total = 0;

    for (;;) {
        if (total >= buf_size) {
            buf = grow_buffer(buf, &buf_size);
            if (!buf) return mk_io_error("brotli decompress: out of memory");
        }

        size_t avail_out      = buf_size - total;
        uint8_t *next_out     = buf + total;
        size_t prev_avail_out = avail_out;

        BrotliDecoderResult result = BrotliDecoderDecompressStream(
            s->decoder, &avail_in, &next_in,
            &avail_out, &next_out, NULL);

        total += (prev_avail_out - avail_out);

        if (result == BROTLI_DECODER_RESULT_ERROR) {
            BrotliDecoderErrorCode ec = BrotliDecoderGetErrorCode(s->decoder);
            lean_obj_res err = mk_dec_error("brotli decompress", ec);
            free(buf);
            return err;
        }

        if (result == BROTLI_DECODER_RESULT_SUCCESS) {
            if (avail_in > 0) {
                free(buf);
                return mk_io_error("brotli decompress: trailing data after end of stream");
            }
            s->finished = 1;
            break;
        }

        /* NEEDS_MORE_INPUT: all input consumed, return what we have */
        if (result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT) break;

        /* NEEDS_MORE_OUTPUT: loop with a larger buffer */
    }

    lean_obj_res arr = mk_byte_array(buf, total);
    free(buf);
    return lean_io_result_mk_ok(arr);
}

LEAN_EXPORT lean_obj_res lean_brotli_decompress_push(b_lean_obj_arg state_obj,
                                                      b_lean_obj_arg chunk,
                                                      lean_obj_arg _w) {
    brotli_decompress_state *s = lean_get_external_data(state_obj);

    if (s->finished) {
        if (lean_sarray_size(chunk) > 0)
            return mk_io_error("brotli decompress: push after end of stream");
        lean_obj_res empty = lean_alloc_sarray(1, 0, 0);
        return lean_io_result_mk_ok(empty);
    }

    const uint8_t *src = lean_sarray_cptr(chunk);
    size_t src_len     = lean_sarray_size(chunk);

    return decoder_drive(s, src, src_len);
}

LEAN_EXPORT lean_obj_res lean_brotli_decompress_finish(b_lean_obj_arg state_obj,
                                                        lean_obj_arg _w) {
    brotli_decompress_state *s = lean_get_external_data(state_obj);
    if (!s->finished && !BrotliDecoderIsFinished(s->decoder)) {
        s->finished = 1;
        return mk_io_error("brotli decompress: incomplete stream");
    }
    s->finished = 1;
    lean_obj_res empty = lean_alloc_sarray(1, 0, 0);
    return lean_io_result_mk_ok(empty);
}
