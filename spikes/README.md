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
