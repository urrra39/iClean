# Phase 0 spikes

Throwaway experiments behind [`docs/FEASIBILITY.md`](../docs/FEASIBILITY.md).
They only signal `ic-hog` processes they spawn themselves.

```sh
swift build -c release --product ic-hog
clang -O1 -o /tmp/mach_and_reclaim spikes/mach_and_reclaim.c && /tmp/mach_and_reclaim
swiftc -O -o /tmp/freeze_spike spikes/freeze_spike.swift && /tmp/freeze_spike .build/release/ic-hog 40
swiftc -O -o /tmp/gui_spike spikes/gui_spike.swift && mkdir -p .build/spike && /tmp/gui_spike .build/release/ic-hog .build/spike
```

`freeze_spike` induces real memory pressure (the last argument is the cap in
percent of RAM). Close work you care about first. `gui_spike` briefly brings
a test window to the front and then gives focus back.

## 1.1 spikes

```sh
swift build -c release --product iclear && swift build -c release --product icleard
python3 spikes/hook_overhead.py .build/release 1000
swiftc -O -o /tmp/branch_spike spikes/branch_spike.swift && /tmp/branch_spike "$PWD/Sources/ICSystem" 10000
```

`hook_overhead.py` starts its own shells and an isolated, observe-only daemon in a
temporary home; it signals nothing. Results: [`docs/FEASIBILITY.md`](../docs/FEASIBILITY.md#11-spikes-2026-10-02).

