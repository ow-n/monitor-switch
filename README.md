# Monitor Switch

Declarative multi-monitor control for Windows. One YAML file describes your wall - which screens stay on for each profile, what refresh rate they run, whether HDR is on, and what the panels' own OSD settings should be. One command applies it.

Hand a column of monitors to your laptop and take it back without opening Settings, and without the profile silently restoring settings you deliberately changed.

---

## Why the refresh cap is the default

Every profile switch re-applies a refresh policy, and that policy ships as `safe` (60 Hz).

Driving several large panels at high refresh consumes a lot of display-engine and PCIe bandwidth. HDR compounds it, because HDR means 10-bit colour. On a GPU whose link has degraded - or any bandwidth-starved setup - a single frame can exceed the driver's TDR watchdog and take the display driver down with `0x116 VIDEO_TDR_FAILURE`.

Capping refresh keeps the GPU under that threshold. **It is a mitigation, not a cure.** If you are seeing TDR resets, fix the underlying link; the cap only buys you a stable desktop while you do.

Raise it whenever you want:

```powershell
.\bin\monitor-switch.ps1 refresh -Policy max
```

Or set `refresh.policy: max` in `monitors.yaml` to make it permanent.

---

## Install

```powershell
git clone https://github.com/ow-n/monitor-switch.git
cd monitor-switch
.\install.ps1
```

The installer will:

1. Install `DisplayConfig` and `powershell-yaml` from PSGallery
2. Copy `monitors.yaml` to `%LOCALAPPDATA%\MonitorSwitch\` so `git pull` never clobbers your tuning
3. Capture a baseline snapshot of your current layout
4. Generate one `.bat` launcher per profile

> Arrange your monitors exactly how you want them **before** the baseline capture. Every profile is derived from it.

---

## Commands

```powershell
.\bin\monitor-switch.ps1 <command> [args]
```

| Command | What it does |
| --- | --- |
| `switch <name>` | Apply a profile, then enforce the refresh, HDR and OSD policies |
| `list` | Show profiles and which DisplayIds each keeps active |
| `status` | Live layout: grid slot, position, refresh rate, rotation, primary |
| `parity` | Compare every readable setting across displays and flag drift |
| `capture` | Re-snapshot the current layout as the new baseline |
| `identify` | Flash DisplayId + connection type on each physical panel |
| `refresh` | Re-apply the refresh policy only |
| `hdr` | Re-apply the HDR policy only |
| `osd` | Re-apply the monitor OSD policy only |
| `shortcuts` | Regenerate the `.bat` launchers |
| `config` | Print the resolved config file path |

Useful switches: `-Policy`, `-SafeHz 60`, `-SdrNits 300`, `-Setting Brightness -Value 35`, `-SkipRefresh`, `-SkipHdr`, `-SkipOsd`, `-WhatIf`.

Everything that writes supports `-WhatIf`. Use it first.

---

## The two layers

Monitor Switch drives both sides of the cable, which is why it can fix things Windows Settings cannot.

| Layer | Reached via | Controls |
| --- | --- | --- |
| **GPU side** | Windows CCD + display-mode APIs | which displays are active, position, primary, rotation, refresh rate, HDR, SDR white level |
| **Monitor side** | DDC/CI over the video cable | brightness, contrast, colour preset, RGB gains, sharpness, picture mode |

The monitor side talks to each panel's own controller, so it changes the hardware, not a Windows setting. It needs DDC/CI enabled in the monitor's own menu - `parity` shows which panels answer.

---

## How profiles work

Windows renumbers DisplayIds whenever a monitor is added or removed, so **nothing here is keyed on DisplayId**. Profiles select displays by where they sit on the desktop.

Each display's position is bucketed into a named column and row using `layout.panelWidth` / `panelHeight`, producing a **slot**:

```text
+----------------+----------------+----------------+
| top-left       | top-middle     | top-right      |
+----------------+----------------+----------------+
| bottom-left    | bottom-middle  | bottom-right   |
+----------------+----------------+----------------+
```

Names scale with however many distinct positions exist - two columns become `left`/`right`, three become `left`/`middle`/`right`.

Slots come from the baseline, not the live layout, so disabling a column does not rename the survivors.

Run `status` to see the live slot for every display, and `identify` when identical panels are impossible to tell apart.

---

## Configuration

`monitors.yaml`, resolved in this order:

1. `$env:MONITOR_SWITCH_CONFIG`
2. `%LOCALAPPDATA%\MonitorSwitch\monitors.yaml`
3. the repo template

### Refresh

```yaml
refresh:
  policy: safe          # safe | max | native
  safeHz: 60

  displays:             # explicit per-slot targets - highest precedence
    bottom-middle: 120

  overrides:            # fallback caps by monitor name substring
    - match: "MPG341"
      hz: 100
```

Precedence per display: `displays[<slot>]`, then a matching `overrides` entry, then the policy.

A **policy cap only ever lowers** - a display already at or below it is left alone, because raising it back up would add the bandwidth the cap exists to avoid. An explicit `displays` entry is a request, so it may raise a display above `safeHz`; you get a warning when it does.

Resolution and colour depth are never touched.

### HDR

```yaml
hdr:
  policy: leave         # on | off | leave
  sdrNits: 240
  autoHdr: leave        # on | off | leave
```

`sdrNits` is the SDR content brightness slider - how bright ordinary SDR content looks while HDR is on. Windows stores it raw (1000 = 80 nits); this config takes plain nits.

### OSD

```yaml
osd:
  policy: leave         # apply | sync | leave
  reference: DISPLAY1
  settings:
    Brightness: 35
    Contrast: 50
```

`apply` writes `settings` to every display. `sync` reads `reference` and copies its values onto the others - the fastest way to kill OSD drift across a wall. A value above what the panel reports as its maximum is skipped, not clamped.

### Profiles

```yaml
profiles:
  all:
    description: Full restore - every monitor back on
    select: all

  left-middle:
    description: LEFT + MIDDLE columns - frees the right column
    select:
      columns: [left, middle]
    primary:
      column: middle
      row: bottom

  top-left:
    select:
      columns: [left]
      rows: [top]
    primary: first
    refresh:              # per-profile override, merged over the global section
      policy: max
```

| Key | Meaning |
| --- | --- |
| `select: all` | Full restore from the baseline snapshot |
| `select.columns` | Keep only these columns. Omit for "any" |
| `select.rows` | Keep only these rows. Omit for "any" |
| `primary` | `first`, a bare row/column name, or `{ column: ..., row: ... }` |
| `refresh` / `hdr` / `osd` | Optional per-profile overrides, shallow-merged over the global section |

Per-profile overrides are the reason a single-monitor profile can safely run at `max` while the full wall stays capped - one panel is a fraction of the bandwidth.

Everything not kept is disabled in a single atomic CCD change - no flicker, no cascade of reconnects.

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

Any attribute whose value is not identical on every display is flagged. Input source is never compared - it legitimately differs per physical port. A panel that cannot answer over DDC/CI reports `n/a` rather than failing the run, and `n/a` never counts as drift.

Exits non-zero when drift is found, so it works as a CI or scheduled-task check. Silence rows you do not care about via `parity.ignore`.

---

## State

Machine-specific files live outside the repo, in `%LOCALAPPDATA%\MonitorSwitch\state\`:

| File | Purpose |
| --- | --- |
| `baseline.xml` | Full `DisplayConfig` snapshot: positions, rotations, refresh, primary |
| `positions.json` | DisplayId to X/Y map, so selectors stay correct when profiles are chained |

Re-run `capture` after physically rearranging monitors, changing rotation, or adding/removing a display. The old snapshot goes stale the moment DisplayIds renumber.

---

## Troubleshooting

**Displays look stuck after a switch.** Open Settings > System > Display, nudge a monitor, hit Apply, then retry.

**A profile matched no displays.** Your baseline is stale, or the column/row names in the selector do not exist. Run `status` to see the real slots.

**Refresh change reports a failure code.** The panel does not support that rate at its current resolution. `status` shows what it is actually running; the policy only picks from modes Windows reports as valid.

**"DDC/CI unavailable, skipped".** Enable DDC/CI in the monitor's own on-screen menu. Some panels also drop it when connected through a KVM or a DisplayLink dock.

**A panel reports `n/a` for one setting.** It does not implement that VCP code. Nothing is wrong; that row simply cannot be compared.

**Nothing switches at all.** `DisplayConfig` needs the modern CCD APIs. `MultiMonitorTool`'s `/disable` and `/enable` have been broken since Windows 11 24H2 - that is why this uses `DisplayConfig` instead.

---

## Development

```powershell
.\tools\smoke-test.ps1              # read-only; exercises every code path, applies nothing
.\tools\smoke-test.ps1 -SeedFrom "$env:USERPROFILE\Documents\Tools\Monitors"
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

Module layout:

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

- Windows 10 or 11
- PowerShell 5.1 or later
- [`DisplayConfig`](https://github.com/MartinGC94/DisplayConfig) 6.0.0+
- [`powershell-yaml`](https://github.com/cloudbase/powershell-yaml) 0.4.7+

## License

MIT
