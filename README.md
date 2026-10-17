# Monitor Switch

Declarative multi-monitor control for Windows.

One YAML file describes your wall.
One command applies it.

Hand a column of monitors to your laptop, then take it back.
No Settings, no silently restored refresh rate.

---

## Install

```powershell
git clone https://github.com/ow-n/monitor-switch.git
cd monitor-switch
.\install.ps1
```

Arrange your monitors exactly how you want them **before** installing.
Every profile is derived from that baseline snapshot.

| Step | What it does |
| --- | --- |
| 1 | Installs `DisplayConfig` and `powershell-yaml` from PSGallery |
| 2 | Copies `monitors.yaml` to `%LOCALAPPDATA%\MonitorSwitch\` so `git pull` never clobbers it |
| 3 | Captures the baseline layout |
| 4 | Writes one `.bat` launcher per profile |

---

## Slots

Windows renumbers DisplayIds whenever a monitor is added or removed.
So nothing here is keyed on DisplayId.

Each display is bucketed by desktop position into a **slot**.

```text
+-------------+---------------+--------------+
| top-left    | top-middle    | top-right    |
+-------------+---------------+--------------+
| bottom-left | bottom-middle | bottom-right |
+-------------+---------------+--------------+
```

Names scale to however many positions exist.
Two columns become `left`/`right`, three become `left`/`middle`/`right`.

Slots come from the baseline, not the live layout.
Disabling a column does not rename the survivors.

Run `status` for live slots, `identify` when identical panels are impossible to tell apart.

---

## Profile mappings

Each profile picks which displays **stay on**.
Everything else is disabled, freeing those inputs for another machine.

Shipped profiles, shown on a five-monitor wall:

| Profile | Selector | Keeps | On | Freed |
| --- | --- | --- | --- | --- |
| `all` | `select: all` | everything | 5 | 0 |
| `left` | `columns: [left]` | top-left, bottom-left | 2 | 3 |
| `middle` | `columns: [middle]` | top-middle, bottom-middle | 2 | 3 |
| `left-middle` | `columns: [left, middle]` | top-left, top-middle, bottom-left, bottom-middle | 4 | 1 |
| `top-left` | `columns: [left]` + `rows: [top]` | top-left | 1 | 4 |

Selector keys:

| Key | Meaning |
| --- | --- |
| `select: all` | Full restore from the baseline |
| `select.columns` | Keep only these columns. Omit for any |
| `select.rows` | Keep only these rows. Omit for any |
| `primary` | `first`, a bare row or column name, or `{ column: ..., row: ... }` |
| `refresh` / `hdr` / `osd` | Per-profile override, shallow-merged over the global section |

Per-profile overrides are why a one-monitor profile can run at `max` while the full wall stays capped.
One panel is a fraction of the bandwidth.

Everything not kept is disabled in a single atomic CCD change.
No flicker, no cascade of reconnects.

---

## Commands

```powershell
.\bin\monitor-switch.ps1 <command> [args]
```

| Command | What it does |
| --- | --- |
| `switch <name>` | Apply a profile, then enforce refresh, HDR and OSD policies |
| `list` | Profiles and which DisplayIds each keeps |
| `status` | Live layout: slot, position, refresh, rotation, primary |
| `parity` | Compare every readable setting across displays, flag drift |
| `capture` | Re-snapshot the current layout as the new baseline |
| `identify` | Flash DisplayId and connection type on each panel |
| `refresh` | Re-apply the refresh policy only |
| `hdr` | Re-apply the HDR policy only |
| `osd` | Re-apply the monitor OSD policy only |
| `shortcuts` | Regenerate the `.bat` launchers |
| `config` | Print the resolved config path |

Switches: `-Policy`, `-SafeHz 60`, `-SdrNits 300`, `-Setting Brightness -Value 35`, `-SkipRefresh`, `-SkipHdr`, `-SkipOsd`, `-WhatIf`.

Everything that writes supports `-WhatIf`.
Use it first.

---

## Config

`monitors.yaml`, resolved in this order:

1. `$env:MONITOR_SWITCH_CONFIG`
2. `%LOCALAPPDATA%\MonitorSwitch\monitors.yaml`
3. the repo template

Every key:

| Key | Values | Default | Meaning |
| --- | --- | --- | --- |
| `layout.panelWidth` | px | `3440` | Drives the column maths |
| `layout.panelHeight` | px | `1440` | Drives the row maths |
| `refresh.policy` | `safe` `max` `native` | `safe` | Cap, push to max, or leave alone |
| `refresh.safeHz` | Hz | `60` | The cap. Only ever lowers |
| `refresh.displays` | slot to Hz | `{}` | Explicit per-slot target. Highest precedence, may raise |
| `refresh.overrides` | `match` + `hz` | `[]` | Fallback cap by monitor-name substring. First match wins |
| `hdr.policy` | `on` `off` `leave` | `leave` | Windows HDR |
| `hdr.sdrNits` | nits | `240` | SDR content brightness while HDR is on |
| `hdr.autoHdr` | `on` `off` `leave` | `leave` | Auto HDR for games |
| `osd.policy` | `apply` `sync` `leave` | `leave` | Write `settings`, copy `reference`, or nothing |
| `osd.reference` | display | `DISPLAY1` | Source panel for `sync` |
| `osd.settings` | name to value | `{}` | Brightness, Contrast, ColorPreset, RGB gains, PictureMode |
| `parity.ignore` | row labels | `[]` | Rows to silence in the drift report |
| `shortcuts.enabled` | bool | `true` | Generate `.bat` launchers |
| `shortcuts.directory` | path | `%USERPROFILE%\Documents\Tools\Monitors\shortcuts` | Where they land |

Refresh precedence per display: `displays[<slot>]`, then a matching `overrides` entry, then the policy.

A policy cap **only ever lowers**.
A display already at or below it is left alone.
An explicit `displays` entry is a request, so it may raise above `safeHz` - you get a warning when it does.

Resolution and colour depth are never touched.

`osd.sync` reads `reference` and copies its values onto the others.
Fastest way to kill OSD drift across a wall.
A value above the panel's reported maximum is skipped, not clamped.

---

## Why the cap ships as 60 Hz

Several large panels at high refresh eat display-engine and PCIe bandwidth.
HDR compounds it, because HDR means 10-bit colour.

On a degraded link, a single frame can exceed the driver's TDR watchdog.
That takes the display driver down with `0x116 VIDEO_TDR_FAILURE`.

The cap keeps the GPU under that threshold.
**It is a mitigation, not a cure.**

Raise it any time:

```powershell
.\bin\monitor-switch.ps1 refresh -Policy max
```

Or set `refresh.policy: max` to make it permanent.

---

## Two layers

This drives both sides of the cable, which is why it fixes things Settings cannot.

| Layer | Reached via | Controls |
| --- | --- | --- |
| **GPU side** | Windows CCD + display-mode APIs | active displays, position, primary, rotation, refresh, HDR, SDR white level |
| **Monitor side** | DDC/CI over the video cable | brightness, contrast, colour preset, RGB gains, sharpness, picture mode |

The monitor side talks to each panel's own controller.
It changes the hardware, not a Windows setting.

Needs DDC/CI enabled in the monitor's own menu.
`parity` shows which panels answer.

---

## Parity

```powershell
.\bin\monitor-switch.ps1 parity
```

```text
Attribute    top-left  top-middle bottom-left bottom-middle Drift
---------    --------  ---------- ----------- ------------- -----
Resolution   3440x1440 3440x1440  3440x1440   3440x1440     False
Refresh      60Hz      50Hz       60Hz        50Hz           True
Brightness   96        96         96          96            False
Sharpness    n/a       n/a        n/a         n/a           False
```

Any attribute not identical on every display is flagged.
Input source is never compared - it legitimately differs per port.
A panel that cannot answer reports `n/a`, which never counts as drift.

Exits non-zero on drift, so it works as a scheduled check.

---

## State

Machine-specific files live in `%LOCALAPPDATA%\MonitorSwitch\state\`.

| File | Purpose |
| --- | --- |
| `baseline.xml` | Full snapshot: positions, rotations, refresh, primary |
| `positions.json` | DisplayId to X/Y map, so selectors survive chained profiles |

Re-run `capture` after rearranging monitors, changing rotation, or adding a display.
The snapshot goes stale the moment DisplayIds renumber.

---

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Displays stuck after a switch | Open Settings, Display, nudge a monitor, Apply, retry |
| Profile matched no displays | Stale baseline, or those column/row names do not exist. Run `status` |
| Refresh change reports a failure code | Panel does not support that rate at its current resolution |
| `DDC/CI unavailable, skipped` | Enable DDC/CI in the monitor's menu. KVMs and DisplayLink docks often drop it |
| A panel reports `n/a` | It does not implement that VCP code. Nothing is wrong |
| Nothing switches at all | Needs the modern CCD APIs. `MultiMonitorTool`'s `/disable` has been broken since Windows 11 24H2 |

---

## Development

```powershell
.\tools\smoke-test.ps1              # read-only, applies nothing
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

```text
src/MonitorSwitch/
  MonitorSwitch.psd1      manifest + exports
  MonitorSwitch.psm1      loader
  Private/Interop.ps1     P/Invoke: display modes + DDC/CI
  Private/Paths.ps1       config + state locations, section merging
  Private/Grid.ps1        geometry, slots, profile selectors
  Public/Config.ps1       Get-MonitorSwitchConfig
  Public/Profile.ps1      switch, list, capture, identify, shortcuts
  Public/Refresh.ps1      refresh policy
  Public/Hdr.ps1          HDR policy
  Public/Osd.ps1          DDC/CI panel settings
  Public/Status.ps1       status + parity
```

---

## Requirements

| Need | Version |
| --- | --- |
| Windows | 10 or 11 |
| PowerShell | 5.1+ |
| [`DisplayConfig`](https://github.com/MartinGC94/DisplayConfig) | 6.0.0+ |
| `powershell-yaml` | any |
