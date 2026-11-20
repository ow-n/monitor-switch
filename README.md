# Monitor Switch

Declarative multi-monitor control for Windows.

One shared engine, separate configs and captured layouts per setup.

Hand a column of monitors to your laptop, then take it back.
No Settings, no silently restored refresh rate.

---

## Install

```powershell
git clone https://github.com/ow-n/monitor-switch.git
cd monitor-switch
.\install.ps1 -Setup home-pc
```

Use **PowerShell 7 (`pwsh`)** for the installer and CLI.
Arrange your monitors exactly how you want them before capturing.
Use `-SkipCapture` to install before the monitors are connected.

| Step | What it does |
| --- | --- |
| 1 | Installs `powershell-yaml` from PSGallery |
| 2 | Copies the selected setup template to `%LOCALAPPDATA%\MonitorSwitch\setups\<setup>\` so `git pull` never clobbers it |
| 3 | Captures the baseline layout |
| 4 | Writes setup-pinned `.bat` launchers into a separate folder per setup |

## Home PC, home laptop, office laptop

| Setup | Template folder | Purpose | Launcher folder |
| --- | --- | --- | --- |
| `home-pc` | `setups\home-pc` | Existing column handoffs and single-screen profiles | `Home PC Setup` |
| `home-laptop` | `setups\home-laptop` | Save/restore the laptop's home alignment; no display toggles | `Home Laptop Setup` |
| `office-laptop` | `setups\office-laptop` | Save/restore office alignment; no display toggles | `Office Laptop Setup` |

Launcher folders live under `%USERPROFILE%\Documents\Tools\Monitors`.
Every generated launcher pins its setup and config, even when another setup was used last.
Pass `-Setup` explicitly on every CLI invocation; it is not remembered globally.
The existing unqualified home PC install still uses its legacy config and state.
A fresh machine without a legacy install must choose a setup instead of inheriting the PC wall.

On the laptop, install both independent setups without capturing disconnected monitors:

```powershell
.\install.ps1 -Setup home-laptop -SkipCapture
.\install.ps1 -Setup office-laptop -SkipCapture
```

At the office, connect all intended monitors, use Windows Display Settings to extend
them and align their edges with the physical arrangement, then save it:

```powershell
.\bin\monitor-switch.ps1 identify -Setup office-laptop
.\bin\monitor-switch.ps1 capture -Setup office-laptop
# Later, on the same laptop with the same connections:
.\bin\monitor-switch.ps1 restore -Setup office-laptop
```

Do the same at home with `-Setup home-laptop`. Capture the laptop's own screens,
not the PC snapshot. Laptop templates have no home grid positions or rotations;
the `layout.panelWidth` / `panelHeight` values only group status labels.
Captured CCD modes retain the actual resolutions and positions, including mixed-size panels.
The `alignment` mode rejects any profile that would select a subset of displays.
Its refresh policy is `native` and OSD policy is `leave`; **HDR stays locked off**.

Initial alignment needs the laptop connected there; the software cannot infer physical
monitor placement remotely. With different pixel densities/scaling, saved Windows positions
alone do not guarantee physically identical cursor movement across every point on an edge.
Re-capture after changing connections; do not copy baselines between machines.

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
Optional `layout.columnNames` and `layout.rowNames` pin names to grid indexes.
The shipped wall uses those maps, so unplugging the right column does not rename
the physical middle column to `right`, and a lone bottom-middle stays bottom-middle.

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
| `single` | `columns: [middle]` + `rows: [bottom]` | bottom-middle, upright | 1 | 4 |

`left` makes the top-left monitor primary while keeping both left monitors on.

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
Panels may briefly go black while waking or reacquiring the video signal.

---

## Commands

```powershell
.\bin\monitor-switch.ps1 <command> [args] -Setup home-pc
```

| Command | What it does |
| --- | --- |
| `switch <name>` | Apply a profile, then enforce refresh, HDR and OSD policies |
| `restore` | Restore the selected setup's full captured layout (`switch all`) |
| `list` | Profiles and which DisplayIds each keeps |
| `status` | Live layout: slot, position, refresh, rotation, primary |
| `parity` | Compare every readable setting across displays, flag drift |
| `capture` | Disable HDR, then re-snapshot the current layout as the new baseline |
| `identify` | Flash DisplayId and connection type on each panel |
| `refresh` | Re-apply the refresh policy only |
| `hdr` | Re-apply the HDR policy only |
| `osd` | Re-apply the monitor OSD policy only |
| `shortcuts` | Regenerate the `.bat` launchers |
| `config` | Print the resolved config path |

Switches: `-Policy`, `-SafeHz 60`, `-Setting Brightness -Value 35`, `-SkipRefresh`, `-SkipOsd`, `-WhatIf`.

Everything that writes supports `-WhatIf`.
Use it first.

### HDR lockout

**HDR, Auto HDR, and HDR video playback stay off.**
Global config, profile overrides, and command arguments accept only `off`.
Requests for `on` or `leave` are errors, not overrides.
`-SkipHdr` is rejected before any layout change.

Every profile disables HDR before restoring a layout and in a `finally` guard
immediately afterward, even if the restore fails, before refresh or OSD policies run.
Capture also disables HDR before saving.
HDR writes and read-back failures stop the command instead of reporting success.
The HDR policy does not write SDR content brightness; an explicit `-SdrNits` only prints a warning.

The Auto HDR registry update preserves other DirectX preferences.

---

## Config

With `-Setup <name>`, `monitors.yaml` is resolved in this order:

1. `%LOCALAPPDATA%\MonitorSwitch\setups\<name>\monitors.yaml`
2. `setups\<name>\monitors.yaml` in the repo

Explicit setups never consult `MONITOR_SWITCH_CONFIG` or the legacy home config.
`-ConfigPath` explicitly overrides the config only, not the selected setup's state.
Module users select the context with `Set-MonitorSwitchSetup -Name office-laptop`
after importing the module. This affects only that module session.

Without `-Setup`, existing legacy installs resolve:

1. `$env:MONITOR_SWITCH_CONFIG`
2. `%LOCALAPPDATA%\MonitorSwitch\monitors.yaml`

An unconfigured machine errors rather than falling back to the home PC template.
The root `monitors.yaml` remains the legacy home PC template.

Every key:

| Key | Values | Default | Meaning |
| --- | --- | --- | --- |
| `mode` | `handoff` `alignment` | `handoff` when omitted | Alignment permits only `select: all` |
| `layout.panelWidth` | px | `3440` | Drives the column maths |
| `layout.panelHeight` | px | `1440` | Drives the row maths |
| `layout.columnNames` | grid index to name | `-1: left, 0: middle, 1: right` | Stable physical columns, even with missing panels |
| `layout.rowNames` | grid index to name | `-1: top, 0: bottom` | Stable physical rows |
| `refresh.policy` | `safe` `max` `native` | `safe` | Cap, push to max, or leave alone |
| `refresh.safeHz` | Hz | `60` | The cap. Only ever lowers |
| `refresh.displays` | slot to Hz | `{}` | Explicit per-slot target. Highest precedence, may raise |
| `refresh.overrides` | `match` + `hz` | `[]` | Fallback cap by monitor-name substring. First match wins |
| `hdr.policy` | `off` | `off` | Windows HDR is locked off |
| `hdr.sdrNits` | nits | `240` | Stored only; inactive while HDR is off |
| `hdr.autoHdr` | `off` | `off` | Auto HDR for games is locked off |
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

Named setup state lives in `%LOCALAPPDATA%\MonitorSwitch\setups\<name>\state\`.
Legacy installs retain `%LOCALAPPDATA%\MonitorSwitch\state\`.
Snapshots and device identities stay on the capturing machine, **never in Git**.

| File | Purpose |
| --- | --- |
| `baseline.json` | Full snapshot: positions, rotations, refresh, primary (a legacy `baseline.xml` is migrated on first use) |
| `positions.json` | DisplayId + device path to X/Y map, so selectors survive chained profiles |

Re-run `capture` after rearranging monitors, changing rotation, or adding a display.
The snapshot goes stale the moment DisplayIds renumber.

Profiles are selectors over a captured layout, not automatically generated from
the number of plugged-in monitors. No new profile names are needed for four versus
five panels, but the baseline must match the current connections.
Physical rotation comes from that baseline; it cannot be inferred from monitor count.

Before any profile applies, the saved device paths and DisplayIds must match the
connected panels, including ones disabled by a handoff. A changed cable, display
count, or numbering produces an explicit error instead of applying stale rotations.
`capture` requires every connected panel to be active, so `single` or `left` cannot
accidentally replace the full baseline.

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
.\tools\smoke-test.ps1 -Setup home-pc # read-only, applies nothing
.\tools\test-hdr-lockout.ps1        # adversarial config checks and mocked writes
.\tools\test-setups.ps1             # isolated state, config and launcher checks
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

```text
src/MonitorSwitch/
  MonitorSwitch.psd1      manifest + exports
  MonitorSwitch.psm1      loader
  Private/Interop.ps1     P/Invoke: display modes + DDC/CI
  Private/Ccd.ps1         built-in Windows CCD + snapshot handling
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
| PowerShell | 7+ for generated launchers; module syntax supports 5.1 |
| `powershell-yaml` | 0.4.7+ |

Display control uses the Windows CCD APIs directly (inline C#, no compiled DLL), so it runs with Smart App Control on.
