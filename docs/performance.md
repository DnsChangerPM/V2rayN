# Performance

> Policy: no comparative claim ("faster than X", "N% less RAM") is published
> without a measured benchmark recorded in this file. Until then this document
> lists **targets and method**, not results.

## Targets (x64, Windows 10+, release build)
| Metric | Target |
| ------ | ------ |
| Cold startup to first paint | < 1.5 s |
| Cold startup to interactive dashboard | < 2.5 s |
| Warm startup | < 1.0 s |
| Idle RAM (app, core stopped) | < 120 MiB |
| Connected RAM (app, core running) | < 180 MiB |
| Idle CPU (1 min avg) | < 1% |
| Connected CPU, idle tunnel (1 min avg) | < 2% |
| Profile list render (5k rows) | < 300 ms, virtualized |
| Subscription parse (2k lines) | < 1 s, off UI isolate |

## Method
- `scripts/bench_startup.py` (CI `build-windows` job, after the smoke test):
  times `--version` (spawn baseline) and `--smoke-test` (full core lifecycle),
  sampling peak working set of `IranLink.exe` + `xray.exe` via `tasklist`.
  Results append to `dist/bench.jsonl` (uploaded as a CI artifact).
  It does **not** measure time-to-first-paint (not observable headless).
- Manual: Windows Performance Monitor / Task Manager readings recorded in
  `docs/verification/<version>.md`.

## Engineering rules that protect the targets
- Lazy startup: only storage + settings + UI shell load before first paint;
  subscriptions refresh, stats, tray, and update checks start after.
- No heavy work on the UI isolate (parsing/IO/network in services + isolates).
- Bounded log ring (2k entries) + async file writer + rotation (5 × 2 MiB).
- 1 Hz stats sampling; UI rebuilds scoped via `Selector`/provider granularity.
- Animations: implicit, short (<200 ms), disabled under reduced-motion.

## Results
| Date | Build | OS | Cold start | Idle RAM | Conn. RAM | Notes |
| ---- | ----- | -- | ---------- | -------- | --------- | ----- |
| — | — | — | — | — | — | _No measurements yet — record the first CI smoke numbers here._ |

## v2rayN comparison
Not performed. If a comparison is ever published, it must state: both app
versions, OS/build, hardware, core versions, config used, measurement tool,
sample count, and link the raw logs. Anything less is not a benchmark.
