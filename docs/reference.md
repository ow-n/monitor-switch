# Reference

## CLI

```powershell
.\scripts\monitor-switch.ps1 <command> [args] -Setup <setup>
```

| Command | Effect |
| --- | --- |
| `switch <name>` | Apply profile; `all` brings back the complete saved arrangement |
| `capture` | Save arranged layout; first use or topology/layout change, not daily |
| `list` | Profiles + selected DisplayIds |
| `status` | Live slots, position, refresh, rotation, primary |
| `identify` | Panel overlays: DisplayId + connection |
| `compare` | Readable-setting differences; exit 1 on mismatch |
| `refresh` | Refresh policy only |
| `hdr` | Disable and verify HDR, Auto HDR, and HDR video playback |
| `picture` | Panel picture settings only |
| `config` | Resolved config path |

| Option | Scope |
| --- | --- |
| `-WhatIf` | Preview writes; use before applying |
| `-ConfigPath` | Override config, not setup state |
| `-SkipRefresh` | Profile: skip refresh |
| `-SkipPicture` | Profile: skip picture settings, not input selection or verification |
| `-Policy`, `-SafeHz` | `refresh` |
| `-Policy` | `picture`: `apply`, `sync`, `leave` |
| `-Setting`, `-Value`, `-Reference` | `picture` |

Options unsupported by the selected command are errors, not silently ignored.
HDR is mandatory, not a configurable policy. `-SkipHdr`, `-AutoHdr`, and `-SdrNits` are not supported.
Laptop folders use `CAPTURE.bat` once and `ALL.bat` thereafter; there is no separate restore command.

## Contracts

| Area | Invariant |
| --- | --- |
| Setup | Explicit `-Setup`; module callers use `Set-MonitorSwitchSetup -Name <setup>` |
| Config | Tracked `setups\<setup>\config.psd1`; native data file, no installed copy |
| State | One ignored `state\<setup>\layout.json`; machine/location-specific |
| Capture | All connected panels active; repeat after wiring, count, numbering, layout or rotation changes |
| Capture format | Module 3 uses version 1 of `MonitorSwitch.SavedLayout`; older JSON/XML captures are not read or migrated. Capture again on each machine/location |
| Identity | Saved device paths + DisplayIds must match all connected panels, including disabled ones |
| Slots | Baseline geometry, not current active count; never hard-code DisplayIds |
| Naming | `layout.columnNames` / `rowNames` pin grid indexes; omitted maps infer names |
| Selection | Keep matching panels; disable others atomically; ALL preserves captured primary |
| Alignment | No subset handoffs or input routing |
| Overrides | Profile `refresh` and `picture` shallow-merge over global sections |
| HDR | Windows HDR, Auto HDR, video HDR always off; reject any `hdr` configuration section or bypass argument |
| HDR ordering | Enforce before layout and in `finally` afterward; write/read-back failures block |
| SDR | Preserve content brightness and unrelated DirectX preferences; no brightness tuning argument |
| Modes | Resolution + colour depth unchanged |
| Refresh | Slot target > first matching name cap > policy; explicit targets may raise, caps only lower |
| Refresh risk | Multi-panel high refresh can trigger driver TDR; safe cap mitigates, not cures |
| DDC/CI | Enable in panel menu; cable/KVM/dock support varies |
| Inputs | Only listed slots written; outgoing before detach, incoming after restore |
| Input proof | VCP `0x60` read-back required; missing/mismatched result fails; Windows `Active` is not proof |
| Handoff | Laptop awake + sending video; reapply may briefly reconnect disabled panels |
| Picture limits | Unsupported codes skipped with a warning; over-maximum values skipped |
| Comparison | Exclude input source; `n/a` is not drift; `comparison.ignore` suppresses named rows |

## Config semantics

Actual values + shipped profiles: [setup configs](../setups).

| Key | Meaning / accepted values |
| --- | --- |
| `mode` | `handoff` (default), `alignment` (only `select = 'all'`) |
| `layout.panelWidth`, `panelHeight` | Pixel spacing for grid quantization |
| `layout.columnNames`, `rowNames` | Grid-index -> physical name |
| `profiles.<name>.select` | `'all'` or `@{ columns = @(...); rows = @(...) }`; omitted axis unrestricted |
| `profiles.<name>.primary` | `'first'`, row/column name, or `@{ column = 'middle'; row = 'bottom' }` |
| `profiles.<name>.inputs` | Slot -> `HDMI1`, `HDMI2`, `DP1`, `DP2` |
| `refresh.policy`, `safeHz` | `safe` cap, `max` supported maximum, `native` unchanged |
| `refresh.displays` | Slot -> explicit Hz target |
| `refresh.overrides` | Ordered `match` monitor-name substring + `hz` cap |
| `picture.policy`, `reference`, `settings` | `apply` writes settings; `sync` copies reference; `leave` does nothing |
| `picture.settings` keys | Brightness, Contrast, ColorPreset, RedGain, GreenGain, BlueGain, Sharpness, PictureMode |
| `comparison.ignore` | Readable-setting row names excluded from comparison |

## Saved layout

`layout.json` contains the format/version, native Windows path and mode buffers,
and the device identity associated with each captured path. Positions and slot
geometry are derived from those buffers, not duplicated in a sidecar.

Capture requires every connected panel to be active. It writes a temporary file
and atomically replaces the saved layout; a failed capture does not replace the
working file. Reads reject unsupported versions, corrupt buffers, inconsistent
identities, and invalid path/source indexes before any profile writes.

Legacy `baseline.json`, `positions.json`, and `baseline.xml` files are left untouched
but ignored. Connect, enable, and arrange every panel, then run `capture` before
using the version 3 profiles. Do this separately on each machine/location.

## Source map

Source paths relative to `src`; `scripts` paths relative to repository root.

| Path | Responsibility |
| --- | --- |
| `scripts\monitor-switch.ps1`, `scripts\run.cmd` | CLI dispatch, portable launcher |
| `Module\MonitorSwitch.psd1`, `MonitorSwitch.psm1` | Authoritative exports, explicit loader |
| `Configuration\SetupConfiguration.ps1` | Setup context, paths, validation, overrides |
| `Layout\SavedLayout.ps1` | One capture format, atomic storage, loading and geometry |
| `Layout\MonitorSlots.ps1` | Slot names, topology guard, selectors |
| `Layout\ProfileOperations.ps1` | Complete safe switching sequence, staged handoffs, mandatory HDR-off enforcement |
| `MonitorControl\InputSelection.ps1` | Send and verify physical panel input selection |
| `MonitorControl\RefreshRatePolicy.ps1` | Refresh selection and enforcement |
| `MonitorControl\PictureSettings.ps1` | Picture controls and apply/sync policy |
| `Diagnostics\DisplayDiagnostics.ps1` | Status, settings comparison, identification overlays |
| `Windows\DisplayTopology.ps1` | Native desktop configuration, HDR settings, adapter rebinding |
| `Windows\DisplayModes.ps1` | Current display modes; enumerate supported rates only when needed |
| `Windows\MonitorConnection.ps1` | Physical monitor handles and setting reads/writes |

Import `src\Module\MonitorSwitch.psd1`. Folder placement does not determine
visibility; the manifest export list does. The loader fails if a required file or
exported command is missing.

All native code compiles in memory. No external display module or compiled DLL is required.

## Checks

Run from repository root.
CI: [`.github\workflows\ci.yml`](../.github/workflows/ci.yml); lint, manifest, mocked regressions.

```powershell
.\tests\test-hdr-lockout.ps1
.\tests\test-setups.ps1
.\tests\test-input-routing.ps1
Test-ModuleManifest .\src\Module\MonitorSwitch.psd1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
.\tests\smoke-test.ps1 -Setup home-pc # Read-only; physical desktop required
```

Profile changes: config + launcher + launcher expectations in `tests\test-setups.ps1`.
Hardware handoffs: verify actual panel inputs, not just Windows topology.

## Recovery

| Symptom | Action |
| --- | --- |
| Missing/stale/legacy capture | Activate + arrange all connected panels; capture again |
| Empty selection | Check `status`, saved geometry + configured axis names |
| Stuck layout | Windows Display Settings: nudge panel, Apply, retry |
| Refresh failure | Choose supported rate at current resolution |
| Input read-back failure | Check DDC/CI, cable/input mapping, KVM/dock |
| Unsupported VCP `n/a` | No action |

Never substitute MultiMonitorTool enable/disable; use built-in CCD.
