// A stateful recognizer fixture. Counts samples across calls without a model.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
struct stream { int counter; };
static int samples, opens, flushes, closes;
static int kind = 2;
int fixture_samples(void) { return samples; }
int fixture_opens(void) { return opens; }
int fixture_flushes(void) { return flushes; }
int fixture_closes(void) { return closes; }
void* crispasr_session_open(const char* path, int threads) {
    kind = strcmp(path, "prefix") == 0 ? 3 : 2;
    (void)threads; return (void*)(intptr_t)1;
}
const char* crispasr_session_backend(void* s) { (void)s; return "fixture"; }
int crispasr_session_stream_kind(void* s) { (void)s; return kind; }
void crispasr_session_close(void* s) { (void)s; }
void* crispasr_session_stream_open(void* s, int threads, int step, int length,
                                  int keep, const char* lang, int translate) {
    (void)s; (void)threads; (void)step; (void)length; (void)keep; (void)translate;
    if (!lang || strcmp(lang, "de")) return NULL;
    opens++;
    return calloc(1, sizeof(struct stream));
}
int crispasr_stream_feed(struct stream* s, const float* pcm, int n) {
    (void)pcm; samples += n; s->counter++; return 1;
}
int crispasr_stream_flush(struct stream* s) { flushes++; s->counter++; return 1; }
int crispasr_stream_get_text(struct stream* s, char* out, int cap, double* t0,
                            double* t1, int64_t* counter) {
    const char* text = flushes ? "Das ist Deutsch. Auch die letzten Wörter bleiben." : "Das ist Deutsch.";
    *t0 = 0; *t1 = samples / 16000.0; *counter = s->counter;
    strncpy(out, text, cap - 1); out[cap - 1] = 0;
    return (int)strlen(text);
}
void crispasr_stream_set_live_decode(struct stream* s, int enabled) { (void)s; (void)enabled; }
void crispasr_stream_close(struct stream* s) { closes++; free(s); }
// Simulate a stateless detector that needs history before it can recognize
// continuous speech. Its warm-up prefix is not evidence of an actual pause.
int crispasr_vad_slices(const char* path, const float* pcm, int n, int rate,
                       float threshold, int min_speech, int min_silence,
                       int pad, float max_chunk, int threads, float** out) {
    (void)path; (void)pcm; (void)threshold; (void)min_speech;
    (void)min_silence; (void)pad; (void)max_chunk; (void)threads;
    *out = NULL;
    if (n < rate * 1.6) return 0;
    *out = malloc(2 * sizeof(float));
    (*out)[0] = 1.4f;
    (*out)[1] = (float)n / rate;
    return 1;
}
void crispasr_vad_free(float* spans) { free(spans); }
