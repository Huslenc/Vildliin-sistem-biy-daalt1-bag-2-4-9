/* tpdemo - runs the thread pool and prints a JSON event log for the UI.
 * usage: tpdemo workers queue tasks min_ms max_ms interval_ms [seed] */
#define _DEFAULT_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include "threadpool.h"

typedef struct { double t; char ev[10]; int w, k; } event_t;

static event_t *log_buf; static int log_n, log_cap;
static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;
static struct timespec t0;
static int running, max_running, completed, dropped;
static char *rej_seen;                          /* rej_seen[k] = task k already logged as rejected */

static double now_ms(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (t.tv_sec - t0.tv_sec) * 1000.0 + (t.tv_nsec - t0.tv_nsec) / 1e6;
}

static void on_event(const char *ev, int w, int k) {
    pthread_mutex_lock(&log_lock);
    /* a rejected task is retried many times; log the rejection only once per task */
    int skip = 0;
    if (ev[0] == 'r') { if (rej_seen[k]) skip = 1; else rej_seen[k] = 1; }
    if (!skip) {
        if (log_n < log_cap) {
            event_t *e = &log_buf[log_n++];
            e->t = now_ms(); e->w = w; e->k = k;
            snprintf(e->ev, sizeof e->ev, "%s", ev);
        } else dropped++;                       /* never lose events silently */
    }
    if (ev[0] == 's' && ev[1] == 't') { if (++running > max_running) max_running = running; }
    if (ev[0] == 'd' && ev[1] == 'o') { running--; completed++; }
    pthread_mutex_unlock(&log_lock);
}

static void task_fn(void *param) {
    int ms = *(int *)param;
    usleep(ms * 1000);
}

/* strict integer: whole string must be digits (optional sign); rejects "12abc", "", overflow */
static int parse_int(const char *s, long *out) {
    char *end; errno = 0;
    long v = strtol(s, &end, 10);
    if (end == s || *end != '\0' || errno == ERANGE) return 0;
    *out = v; return 1;
}

int main(int argc, char **argv) {
    if (argc < 7) { fprintf(stderr, "usage: %s workers queue tasks min_ms max_ms interval_ms [seed]\n", argv[0]); return 1; }
    long v[7] = {0, 0, 0, 0, 0, 0, 0};
    for (int i = 1; i < argc && i <= 7; i++)
        if (!parse_int(argv[i], &v[i - 1])) { fprintf(stderr, "invalid parameters\n"); return 1; }
    int W = (int)v[0], Q = (int)v[1], N = (int)v[2], lo = (int)v[3], hi = (int)v[4], gap = (int)v[5];
    unsigned seed = argc > 7 ? (unsigned)v[6] : (unsigned)time(NULL);
    if (v[0] < 1 || v[0] > 16 || v[1] < 1 || v[1] > 32 || v[2] < 1 || v[2] > 200 || v[3] < 1 || v[4] < v[3] || v[4] > 5000 || v[5] < 0 || v[5] > 2000) {
        fprintf(stderr, "invalid parameters\n"); return 1;
    }
    log_cap = N * 5 + W * 4 + 64;
    log_buf = malloc(sizeof(event_t) * log_cap);
    int *dur = malloc(sizeof(int) * N);
    rej_seen = calloc(N + 1, 1);
    if (!log_buf || !dur || !rej_seen) { fprintf(stderr, "out of memory\n"); return 1; }
    srand(seed);
    for (int i = 0; i < N; i++) dur[i] = lo + rand() % (hi - lo + 1);

    clock_gettime(CLOCK_MONOTONIC, &t0);
    threadpool_t pool;
    if (pool_init(&pool, W, Q, on_event)) { fprintf(stderr, "pool_init failed\n"); return 1; }
    usleep(20000);                              /* let workers announce themselves (excluded from run_ms) */
    double t_submit0 = now_ms();                /* run_ms starts at the first submit */

    int rejected_tasks = 0;
    for (int i = 0; i < N; i++) {
        int first = 1;
        while (pool_submit(&pool, task_fn, &dur[i], i + 1)) {
            if (first) { rejected_tasks++; first = 0; }
            usleep(3000);                       /* queue full: wait and retry */
        }
        if (gap) usleep(gap * 1000);
    }
    pool_shutdown(&pool);
    double total = now_ms();                    /* timeline end, used by the UI replay */
    double run_ms = total - t_submit0;          /* submit -> last worker joined: no init cost */

    printf("{\"params\":{\"workers\":%d,\"queue\":%d,\"tasks\":%d,\"min\":%d,\"max\":%d,\"interval\":%d,\"seed\":%u},\n", W, Q, N, lo, hi, gap, seed);
    printf("\"summary\":{\"completed\":%d,\"max_running\":%d,\"rejected_tasks\":%d,\"total_ms\":%.1f,\"run_ms\":%.1f,\"dropped_events\":%d,\"truncated\":%s,\"ok\":%s},\n",
           completed, max_running, rejected_tasks, total, run_ms, dropped, dropped ? "true" : "false",
           (completed == N && max_running <= W && !dropped) ? "true" : "false");
    printf("\"events\":[\n");
    for (int i = 0; i < log_n; i++)
        printf("{\"t\":%.2f,\"e\":\"%s\",\"w\":%d,\"k\":%d}%s\n", log_buf[i].t, log_buf[i].ev, log_buf[i].w, log_buf[i].k, i + 1 < log_n ? "," : "");
    printf("]}\n");
    free(log_buf); free(dur); free(rej_seen);
    return 0;
}
