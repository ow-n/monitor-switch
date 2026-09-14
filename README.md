# Monitor Switch

Geometry-based multi-monitor profile switching for Windows, with a refresh-rate policy that **defaults to a safe cap**.

Hand a column of monitors to your laptop and take it back with one command - without opening Settings, and without the profile silently re-enabling high refresh rates behind you.

---

## Why the refresh cap is the default

Every profile switch re-applies a refresh policy, and that policy ships as `safe` (60 Hz).

Driving several large panels at high refresh consumes a lot of display-engine and PCIe bandwidth. On a GPU whose link has degraded - or on any bandwidth-starved setup - a single frame can exceed the driver's TDR watchdog and take the display driver down with `0x116 VIDEO_TDR_FAILURE`.

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
| `switch <name>` | Apply a profile, then enforce the refresh policy |
| `list` | Show profiles and which DisplayIds each keeps active |
| `status` | Live layout: grid slot, position, refresh rate, rotation, primary |
| `capture` | Re-snapshot the current layout as the new baseline |
| `identify` | Flash DisplayId + connection type on each physical panel |
| `refresh` | Re-apply the refresh policy only |
| `shortcuts` | Regenerate the `.bat` launchers |
| `config` | Print the resolved config file path |

Useful switches: `-Policy safe|max|native`, `-SafeHz 60`, `-SkipRefresh`, `-WhatIf`.

---

## How profiles work

Windows renumbers DisplayIds whenever a monitor is added or removed, so **nothing here is keyed on DisplayId**. Profiles select displays by where they sit on the desktop.

Each display's position is bucketed into a named column and row using `layout.panelWidth` / `panelHeight`:

```text
+----------------+----------------+----------------+
| top-left       | top-middle     | top-right      |
+----------------+----------------+----------------+
| bottom-left    | bottom-middle  | bottom-right   |
+----------------+----------------+----------------+
```

Names scale with however many distinct positions exist - two columns become `left`/`right`, three become `left`/`middle`/`right`.

Run `status` to see the live slot for every display, and `identify` when identical panels are impossible to tell apart.

---

## Configuration

`monitors.yaml`, resolved in this order:

1. `$env:MONITOR_SWITCH_CONFIG`
2. `%LOCALAPPDATA%\MonitorSwitch\monitors.yaml`
3. the repo template

```yaml
refresh:
  policy: safe          # safe | max | native
  safeHz: 60
  overrides:
    - match: "MPG341"   # substring of the monitor name
      hz: 100

layout:
  panelWidth: 3440
  panelHeight: 1440

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
```

### Selector rules

| Key | Meaning |
| --- | --- |
| `select: all` | Full restore from the baseline snapshot |
| `select.columns` | Keep only these columns. Omit for "any" |
| `select.rows` | Keep only these rows. Omit for "any" |
| `primary` | `first`, a bare row/column name, or `{ column: ..., row: ... }` |

Everything not kept is disabled in a single atomic CCD change - no flicker, no cascade of reconnects.

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

**Nothing switches at all.** `DisplayConfig` needs the modern CCD APIs. `MultiMonitorTool`'s `/disable` and `/enable` have been broken since Windows 11 24H2 - that is why this uses `DisplayConfig` instead.

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or later
- [`DisplayConfig`](https://github.com/MartinGC94/DisplayConfig) 6.0.0+
- [`powershell-yaml`](https://github.com/cloudbase/powershell-yaml) 0.4.7+

## License

MIT
