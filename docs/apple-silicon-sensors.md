# Reading temperatures on Apple Silicon

Everything below was measured on one machine: a `Mac16,8` running macOS 26.5
(build 25F71, Darwin 25.5.0). It is one data point, not a survey of the platform.
Where a command is quoted, its output is quoted verbatim.

The short version: this application shows no CPU or GPU temperature because it could
not read one, and the usual route no longer exists.

## powermetrics has no smc sampler

The advice you find for reading Mac temperatures is `powermetrics --samplers smc`.
On this machine that sampler is gone:

```
$ powermetrics --samplers smc -n 1
powermetrics: unrecognized sampler: smc
```

Note what is missing from that: any mention of privileges. `powermetrics` normally
refuses outright without root —

```
$ powermetrics -n 1
powermetrics must be invoked as the superuser
```

— but the sampler name is validated **before** the privilege check, so the first
command answers `unrecognized sampler: smc` with no `sudo` at all. Anyone can
reproduce that on their own machine without granting anything.

This matters for how you read the result. "It needs root" would suggest a superuser
could get the temperatures. They cannot: the sampler does not exist.

## What powermetrics does offer

`powermetrics --help` lists the supported samplers:

```
tasks             per task cpu usage and wakeup stats
battery           battery and backlight info
network           network usage info
disk              disk usage info
interrupts        interrupt distribution
cpu_power         cpu power and frequency info
thermal           thermal pressure notifications
sfi               selective forced idle information
gpu_power         gpu power and frequency info
ane_power         dedicated rail ane power and frequency info
```

Ten samplers, no `smc`. The one called `thermal` is described by the tool itself as
*thermal pressure notifications* — the same coarse signal `ProcessInfo.thermalState`
exposes, not a reading in degrees.

## The one temperature that is readable

The battery reports its own temperature through the IORegistry, in centidegrees, with
no privileges and no entitlement:

```
$ ioreg -r -c AppleSmartBattery -w0 | tr ',' '\n' | grep '"Temperature"'
      "Temperature" = 3121
```

That is 31.21 °C. It is the only temperature this application was able to read, and
it is shown on the Battery screen. The same node also carries `CycleCount`,
`DesignCapacity`, `AppleRawMaxCapacity`, `Amperage` and `Voltage`, all readable the
same way.

## What the application shows instead

`ProcessInfo.processInfo.thermalState`, which has four values: nominal, fair, serious,
critical. It is what macOS itself acts on when it decides to throttle, and it is
honest about being a state rather than a measurement.

For a while this application did worse than show nothing. It stored the thermal state
as a number on a 0–100 scale, in a field called `cpuTemp`, and then formatted alerts
from it:

```
"Critical CPU temperature: 100°C"
"High CPU temperature: 75°C"
```

Those degrees never existed. The 100 and the 75 were the encoding of `.critical` and
`.serious`. The strings were also pushed as system notifications, in an application
whose own Thermal tab explained that macOS exposes no temperatures. That is now fixed,
and the story is in [plausible-and-wrong.md](plausible-and-wrong.md).

## What is not claimed here

Whether the SMC keys that older articles list — `TC0P`, `Tp01`, `Tg05` and the rest —
return anything on this hardware. That was not measured, so it is not asserted. What
was measured is that the documented `powermetrics` route to them is gone.

Whether any of this holds on a different Mac, a different chip, or a different version
of macOS. One machine was tested.

## If you know better

If there is a way to read SoC temperatures from a non-privileged, non-sandboxed
application on current Apple Silicon, the measurement would be welcome. A reproducible
command and its output is worth more than a link.
