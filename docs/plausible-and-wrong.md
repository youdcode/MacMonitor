# Seven ways a monitor lies without erroring

Everything below was measured on one machine: a `Mac16,8` running macOS 26.5
(build 25F71). Commands are quoted with their real output.

This application was audited, and then fixed, over two days. Every defect found had
the same shape.

**None of them raised anything.** No exception, no `nil`, no non-zero exit, no compiler
warning. Every one returned a well-formed, plausible number of the right type in the
right range, and the interface displayed it without hesitation. The test suite was
green throughout, because the tests did not exist yet — and when they did exist, they
were green too, because they tested the same wrong assumption the code did.

What caught every single one was the same thing: taking the number the application
produced and comparing it against an independent reference before believing it.
`top` for memory. `uptime` for uptime. `netstat -ib` for the network. `ioreg` for the
sensors. Not a better test — a second opinion.

---

## 1. The page size

`vm_stat` reports page counts, not bytes. The code multiplied by a hardcoded 4096.

```
$ sysctl -n hw.pagesize
16384
```

Four kilobytes is right on Intel and wrong on every Apple Silicon Mac. Everything
derived from `vm_stat` was a quarter of the truth. Measured at the same instant:

```
app, before          4.24 GB used
app, after          16.95 GB used
top                 23G used (2999M wired, 9186M compressor)
```

The gauge showed 18% and coloured itself green.

Nothing failed. `4096` is a plausible page size, the arithmetic was correct, and the
result was a number of gigabytes that fitted comfortably inside the machine's memory.
The only way to notice is to hold it next to `top`.

## 2. The per-process CPU that would have vanished

The plan was to replace the `ps` subprocess with a native API. Two candidates, both
measured against processes the app does not own:

```
proc_pid_rusage / proc_pidinfo(PROC_PIDTASKINFO)
  own process                  OK
  launchd (root)               -1
  WindowServer (_windowserver) -1

kinfo_proc.kp_proc.p_pctcpu
  populated for 0 of 609 processes
```

`/bin/ps` manages it because it is setuid root. A normal application cannot.

Going native would have compiled, passed every test, and produced a process list —
just one containing only the current user's processes, silently missing
`WindowServer`, `kernel_task` and everything else that matters when a machine is
misbehaving. The application still shells out to `ps`, and the reason sits next to the
call.

## 3. The disk that was always idle

Disk throughput comes from `IOBlockStorageDriver`. The obvious call is
`IOServiceGetMatchingService`, which returns the first match.

```
5 entries match
  entry 1:  read 0.0 GB    write 0.0 GB
  entry 2:  read 504.8 GB  write 212.5 GB
  entry 3:  read 0.0 GB    write 0.0 GB
  entry 4:  read 0.0 GB    write 0.0 GB
  entry 5:  read 1.4 GB    write 0.0 GB
```

Three of the five report zeros, and which one comes first is not stable between runs.
Take the first and the application ships a disk-activity meter reading 0 B/s forever,
which never errors, never warns, and looks exactly like an idle disk.

The fix is to keep the entry with the largest counters. The lesson is that "the first
match" was never a specification.

## 4. The cores labelled backwards

Per-core load comes from `host_processor_info`. Splitting it by cluster needs a map
from core index to cluster type. The obvious source:

```
$ sysctl hw.perflevel0.name hw.perflevel0.logicalcpu hw.perflevel1.name hw.perflevel1.logicalcpu
hw.perflevel0.name: Performance
hw.perflevel0.logicalcpu: 8
hw.perflevel1.name: Efficiency
hw.perflevel1.logicalcpu: 4
```

Eight performance cores, four efficiency cores. So indices 0–7 are the P cores.

They are not:

```
$ ioreg -lw0 -p IODeviceTree | grep -E '"(cluster-type|logical-cpu-id)"'
logical-cpu-id 0..3   cluster-type "E"
logical-cpu-id 4..11  cluster-type "P"
```

The mapping is `EEEEPPPPPPPP`. `perflevel0` is the *fastest* level, not the *first*
cores. Indexing from the sysctl labels every core the wrong way round, and the chart
would have shown idle efficiency cores as a busy performance cluster.

There is a second trap in the same place: `IOServiceGetMatchingServices("AppleARMCPU")`
returns **zero** matches. The CPU nodes live in the `IODeviceTree` plane, not the
`IOService` plane. Zero matches is easy to read as "this Mac has no such hardware".

## 5. The machine that was always a MacBook Pro

The sidebar showed the machine model. Until `system_profiler` answered, it showed a
hardcoded default: `"MacBook Pro"`. On a Mac mini, that is somebody else's computer.

The obvious fix was `hw.model`, read synchronously. It returns:

```
$ sysctl -n hw.model
Mac16,8
```

A part number, not a name. Correct, useless, and it would have been shown to everyone.

What works is the device tree:

```
$ ioreg -lw0 -p IODeviceTree -n product | grep product-name
"product-name" = <"MacBook Pro (14-inch, Nov 2024)">
```

Read in 0.10 ms, against 186 ms for `system_profiler`, and more specific than the
`MacBook Pro` that `system_profiler` returns. The default was deleted; if neither
source answers, the field is empty. Nothing is invented.

## 6. The verdict that said everything was fine

The Overview screen reduces four figures to a headline. While the page-size bug was
live it counted zero problems and printed *All good*.

This one comes with a correction, because the audit that found it overstated it. The
claim was that the page-size bug caused the *All good*. It did not: the memory
threshold is 85%, the real figure was 73%, and the threshold is not crossed either
way. The disk at 91% and 8.4 GB of swap already counted two problems, so the headline
read *Several issues* in both cases. The **gauge** was green; the **headline** was not.

That was discovered by writing a test from the audit's description and watching it
fail. The test was not rewritten to pass. It was replaced with one that pins the real
mechanism — under-reported memory hides a problem only when memory is the deciding
factor — and the comment on it records the correction.

## 7. The correct number answering the wrong question

The last one is not a bug at all, which is what makes it the worst.

The Network screen showed 16 kB/s down. A browser speed test, at the same moment,
reported 742.7 Mbit/s. The obvious conclusion is that the application is broken by a
factor of five thousand.

Both numbers are right. Throughput is what is passing at this instant. Capacity is
what the link carries when something deliberately fills it. 742.7 Mbit/s is about
93 MB/s, and an idle connection moving 16 kB/s over a 93 MB/s line is exactly what you
would expect to see.

No arithmetic to fix, no API to change. The value was correct, the label was correct,
and the reader — the person who wrote the application — still drew the wrong
conclusion, because the number silently answered a different question from the one
being asked.

The fix was editorial, not technical: label the reading as *current throughput* where
it is read, put capacity in its own card behind a button that says what it will
consume, and never compute one from the other.

---

## The through-line

Seven defects. Zero exceptions, zero warnings, zero failing tests at the moment each
one was live. Six returned a plausible number; the seventh returned a correct one.

A green test suite proves the code does what the test says. A clean build proves the
compiler had no objection. Neither proves the number on screen is true. The only thing
that did was an independent reference — and in the seventh case, not even that: it
took noticing that two correct numbers were being compared as if they measured the
same thing.

## Where this account is unreliable about itself

The audit that started this got three things wrong: it recommended
`ProcessInfo.systemUptime` as the native replacement for `uptime`, which measures
*awake* time and read 5h04 short on the machine it was written on; it claimed the
process memory column inherited the page-size division, which it did not, because it
derived from `hw.memsize`; and it overstated the verdict consequence in §6 above.

An automated check for leftover French comments reported "zero" over a corpus that
included the one it missed. The extractor was right and the word list was wrong, which
is the same failure shape as everything above: a check that answers confidently about
a smaller perimeter than the one you believe you asked about.

## One thing the compiler did catch

During the interface rebuild, `.onChange(of:_:)` with the two-parameter closure was
rejected:

```
error: 'onChange(of:initial:_:)' is only available in macOS 14.0 or newer
```

Nobody was looking for it. The deployment target is macOS 13, and Swift treats an API
newer than the deployment target as an error rather than a warning. So if this project
builds, no API newer than macOS 13 is used without a guard — that half is genuinely
enforced. Runtime behaviour on macOS 13 is a separate question, and it has not been
tested.
