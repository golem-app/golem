// Storage probe for the TurboFieldfare-on-Android spike (#9).
//
// Measures what a phone's flash delivers at the granularity an expert
// streamer asks for: random pread of 3,358,720-byte blobs (one routed expert
// of Gemma 4 26B-A4B in the .gturbo layout) at queue depths 1..16, under
// three cache regimes — fadvise-evicted, O_DIRECT, and warm — plus the
// controls an mmap-based loader would pay: 4 KiB random reads, demand-paged
// page touching, and one sequential pass. Each run prints one parseable
// `SSD_PROBE key=value ...` line.
//
// Build (any NDK; the repo pins r29):
//   $NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android24-clang \
//     -O2 -static -o expert_read_probe tool/expert_read_probe.c
// Run from /data/local/tmp with a large file (the probe only reads it):
//   ./expert_read_probe <file> <pread|mmap|seq|evict> [--size N] [--qd Q]
//     [--count C] [--regime cold|direct|warm] [--seed S] [--cpus 4-7]
//     [--madv random]
//
// The file must be larger than the page cache the kernel will grant, or
// `warm` and `cold` measure the same thing; mincore() over the whole file is
// reported before and after eviction so the regime is verified, never assumed.

#if !defined(__linux__)
#error "Android/Linux only: O_DIRECT, posix_fadvise and sched_setaffinity."
#endif

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static const uint64_t kExpertBlobBytes = 3358720;

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

static uint64_t xorshift64(uint64_t *s) {
  uint64_t x = *s;
  x ^= x << 13;
  x ^= x >> 7;
  x ^= x << 17;
  return *s = x;
}

static void die(const char *what) {
  fprintf(stderr, "%s: %s\n", what, strerror(errno));
  exit(1);
}

static void pin_cpus(const char *spec) {
  if (!spec) return;
  cpu_set_t set;
  CPU_ZERO(&set);
  int lo, hi;
  if (sscanf(spec, "%d-%d", &lo, &hi) == 2) {
    for (int c = lo; c <= hi; c++) CPU_SET(c, &set);
  } else if (sscanf(spec, "%d", &lo) == 1) {
    CPU_SET(lo, &set);
  } else {
    fprintf(stderr, "bad --cpus %s\n", spec);
    exit(2);
  }
  if (sched_setaffinity(0, sizeof set, &set) != 0) die("sched_setaffinity");
}

// Resident 4 KiB pages of the file, counted via mincore over a throwaway
// mapping. Touches nothing, so it does not perturb the cache it reports.
static uint64_t resident_pages(int fd, uint64_t size) {
  long page = sysconf(_SC_PAGESIZE);
  void *map = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
  if (map == MAP_FAILED) die("mmap(mincore)");
  uint64_t pages = (size + page - 1) / page;
  unsigned char *vec = malloc(pages);
  if (!vec) die("malloc(mincore)");
  uint64_t resident = 0;
  if (mincore(map, size, vec) == 0) {
    for (uint64_t i = 0; i < pages; i++) resident += vec[i] & 1;
  } else {
    resident = UINT64_MAX;
  }
  free(vec);
  munmap(map, size);
  return resident;
}

static uint64_t cached_kb(void) {
  FILE *f = fopen("/proc/meminfo", "r");
  if (!f) return 0;
  char line[256];
  uint64_t cached = 0;
  while (fgets(line, sizeof line, f)) {
    if (sscanf(line, "Cached: %llu kB", (unsigned long long *)&cached) == 1) break;
  }
  fclose(f);
  return cached;
}

static int cmp_double(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}

typedef struct {
  int fd;
  uint64_t size;
  uint64_t *offsets;
  int count;
  int qd;
  int index;
  double *latency;
  void *buf;
  int failed;
} Worker;

static void *pread_worker(void *arg) {
  Worker *w = arg;
  for (int i = w->index; i < w->count; i += w->qd) {
    double t0 = now_ms();
    uint64_t done = 0;
    while (done < w->size) {
      ssize_t n = pread(w->fd, (char *)w->buf + done, w->size - done,
                        (off_t)(w->offsets[i] + done));
      if (n <= 0) {
        w->failed = errno ? errno : EIO;
        return NULL;
      }
      done += (uint64_t)n;
    }
    w->latency[i] = now_ms() - t0;
  }
  return NULL;
}

static void report(const char *mode, const char *regime, uint64_t size,
                   int qd, int count, double *latency, double wall_ms,
                   uint64_t res_before, uint64_t res_after, const char *extra) {
  qsort(latency, count, sizeof(double), cmp_double);
  double sum = 0;
  for (int i = 0; i < count; i++) sum += latency[i];
  double bytes = (double)size * count;
  printf("SSD_PROBE mode=%s regime=%s size=%llu qd=%d count=%d "
         "p50_ms=%.3f p90_ms=%.3f p99_ms=%.3f max_ms=%.3f mean_ms=%.3f "
         "wall_ms=%.1f mbps=%.1f resident_pages_before=%llu "
         "resident_pages_after=%llu%s\n",
         mode, regime, (unsigned long long)size, qd, count,
         latency[count / 2], latency[(int)(count * 0.9)],
         latency[(int)(count * 0.99)], latency[count - 1], sum / count,
         wall_ms, bytes / 1048576.0 / (wall_ms / 1e3),
         (unsigned long long)res_before, (unsigned long long)res_after,
         extra ? extra : "");
  fflush(stdout);
}

static void evict(int fd) {
  fsync(fd);
  if (posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED) != 0) die("fadvise");
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s <file> <pread|mmap|seq|evict> [options]\n", argv[0]);
    return 2;
  }
  const char *path = argv[1];
  const char *mode = argv[2];
  uint64_t size = kExpertBlobBytes;
  int qd = 1, count = 240;
  const char *regime = "cold";
  const char *cpus = NULL;
  const char *madv = NULL;
  uint64_t seed = 0x9E3779B97F4A7C15ull;
  for (int i = 3; i + 1 < argc; i += 2) {
    if (!strcmp(argv[i], "--size")) size = strtoull(argv[i + 1], NULL, 10);
    else if (!strcmp(argv[i], "--qd")) qd = atoi(argv[i + 1]);
    else if (!strcmp(argv[i], "--count")) count = atoi(argv[i + 1]);
    else if (!strcmp(argv[i], "--regime")) regime = argv[i + 1];
    else if (!strcmp(argv[i], "--seed")) seed = strtoull(argv[i + 1], NULL, 10);
    else if (!strcmp(argv[i], "--cpus")) cpus = argv[i + 1];
    else if (!strcmp(argv[i], "--madv")) madv = argv[i + 1];
    else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
  }
  pin_cpus(cpus);

  int direct = !strcmp(regime, "direct");
  int fd = open(path, O_RDONLY | (direct ? O_DIRECT : 0));
  if (fd < 0) die("open");
  struct stat st;
  if (fstat(fd, &st) != 0) die("fstat");
  uint64_t file_size = (uint64_t)st.st_size;
  if (file_size < size * 2) { fprintf(stderr, "file too small\n"); return 2; }

  if (!strcmp(mode, "evict")) {
    uint64_t before = resident_pages(fd, file_size);
    uint64_t cached_before = cached_kb();
    evict(fd);
    printf("SSD_PROBE mode=evict resident_pages_before=%llu resident_pages_after=%llu "
           "cached_kb_before=%llu cached_kb_after=%llu\n",
           (unsigned long long)before, (unsigned long long)resident_pages(fd, file_size),
           (unsigned long long)cached_before, (unsigned long long)cached_kb());
    return 0;
  }

  // One fixed offset sequence per seed, 4 KiB-aligned, so every queue depth
  // and regime reads the same blocks in the same order.
  uint64_t *offsets = malloc(sizeof(uint64_t) * count);
  double *latency = calloc(count, sizeof(double));
  uint64_t s = seed;
  uint64_t span = (file_size - size) / 4096;
  for (int i = 0; i < count; i++) offsets[i] = (xorshift64(&s) % span) * 4096;

  uint64_t res_before = UINT64_MAX, res_after = UINT64_MAX;
  if (!strcmp(regime, "cold")) {
    evict(fd);
    res_before = resident_pages(fd, file_size);
  } else if (!strcmp(regime, "warm")) {
    // Pull the exact blocks in once, so the timed pass is a cache hit.
    void *warm = malloc(size);
    for (int i = 0; i < count; i++) {
      if (pread(fd, warm, size, (off_t)offsets[i]) < 0) die("pread(warm)");
    }
    free(warm);
    res_before = resident_pages(fd, file_size);
  }

  if (!strcmp(mode, "pread")) {
    pthread_t *threads = malloc(sizeof(pthread_t) * qd);
    Worker *workers = calloc(qd, sizeof(Worker));
    for (int t = 0; t < qd; t++) {
      workers[t] = (Worker){fd, size, offsets, count, qd, t, latency, NULL, 0};
      if (posix_memalign(&workers[t].buf, 1 << 21, size) != 0) die("posix_memalign");
    }
    double t0 = now_ms();
    for (int t = 0; t < qd; t++) pthread_create(&threads[t], NULL, pread_worker, &workers[t]);
    for (int t = 0; t < qd; t++) pthread_join(threads[t], NULL);
    double wall = now_ms() - t0;
    for (int t = 0; t < qd; t++) {
      if (workers[t].failed) {
        fprintf(stderr, "pread failed: %s\n", strerror(workers[t].failed));
        return 1;
      }
    }
    res_after = resident_pages(fd, file_size);
    report("pread", regime, size, qd, count, latency, wall, res_before, res_after, NULL);
  } else if (!strcmp(mode, "mmap")) {
    // Demand paging: touch one byte per 4 KiB page of each blob, in order,
    // the way a mapped-weights loader faults experts in.
    void *map = mmap(NULL, file_size, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) die("mmap");
    if (madv && !strcmp(madv, "random")) madvise(map, file_size, MADV_RANDOM);
    volatile unsigned char sink = 0;
    double t0 = now_ms();
    for (int i = 0; i < count; i++) {
      double t = now_ms();
      for (uint64_t p = 0; p < size; p += 4096) sink ^= ((unsigned char *)map)[offsets[i] + p];
      latency[i] = now_ms() - t;
    }
    double wall = now_ms() - t0;
    res_after = resident_pages(fd, file_size);
    char extra[64];
    snprintf(extra, sizeof extra, " madv=%s", madv ? madv : "default");
    report("mmap", regime, size, 1, count, latency, wall, res_before, res_after, extra);
    munmap(map, file_size);
    (void)sink;
  } else if (!strcmp(mode, "seq")) {
    // Sequential reference: `count` reads of `size` bytes from the start.
    void *buf;
    if (posix_memalign(&buf, 1 << 21, size) != 0) die("posix_memalign");
    double t0 = now_ms();
    for (int i = 0; i < count; i++) {
      double t = now_ms();
      if (pread(fd, buf, size, (off_t)(size * (uint64_t)i)) < 0) die("pread(seq)");
      latency[i] = now_ms() - t;
    }
    double wall = now_ms() - t0;
    res_after = resident_pages(fd, file_size);
    report("seq", regime, size, 1, count, latency, wall, res_before, res_after, NULL);
  } else {
    fprintf(stderr, "unknown mode %s\n", mode);
    return 2;
  }
  return 0;
}
