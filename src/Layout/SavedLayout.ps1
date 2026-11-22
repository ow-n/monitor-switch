function Get-MonitorSwitchCaptureInstruction {
    $launcher = Join-Path (Get-MonitorSwitchRoot) "setups\$script:MonitorSwitchSetup\CAPTURE.bat"
    if (Test-Path -LiteralPath $launcher) {
        return "run setups\$script:MonitorSwitchSetup\CAPTURE.bat"
    }
    "run .\scripts\monitor-switch.ps1 capture -Setup $script:MonitorSwitchSetup"
}

function Read-MonitorSwitchSavedLayout {
    [CmdletBinding()]
    param([switch]$Optional, [string]$Path, [switch]$AllowInactive)

    if (-not $Path) { $Path = Join-Path (Get-MonitorSwitchStateDir) 'layout.json' }
    if (-not [IO.File]::Exists($path)) {
        if ($Optional) { return $null }
        throw "No saved layout. Connect and arrange all monitors, then $(Get-MonitorSwitchCaptureInstruction) on this machine."
    }

    $json = [IO.File]::ReadAllText($path)
    try { $saved = ConvertFrom-Json -InputObject $json -ErrorAction Stop }
    catch { throw [FormatException]::new("Invalid JSON in saved layout '$path'. $(Get-MonitorSwitchCaptureInstruction).", $_.Exception) }
    foreach ($field in 'Format', 'Version', 'Paths', 'Modes', 'Displays') {
        if ($null -eq $saved -or -not $saved.PSObject.Properties[$field]) {
            throw [FormatException]::new("Invalid saved layout '$path': missing $field. $(Get-MonitorSwitchCaptureInstruction).")
        }
    }
    if ($saved.Format -ne 'MonitorSwitch.SavedLayout' -or $saved.Version -ne 1) {
        throw [FormatException]::new("Unsupported saved layout '$path'. $(Get-MonitorSwitchCaptureInstruction).")
    }

    $indexes = @()
    $identities = @()
    foreach ($display in $saved.Displays) {
        $index = 0
        if (-not $display.PSObject.Properties['PathIndex'] -or
            -not $display.PSObject.Properties['DevicePath'] -or
            -not [int]::TryParse([string]$display.PathIndex, [ref]$index)) {
            throw [FormatException]::new("Invalid display record in '$path'. $(Get-MonitorSwitchCaptureInstruction).")
        }
        $indexes += $index
        $identities += [string]$display.DevicePath
    }
    [MonitorSwitch.Windows.DesktopLayout]::FromSnapshot(
        $saved.Paths, $saved.Modes, [int[]]$indexes, [string[]]$identities, [bool]$AllowInactive)
}

function Get-MonitorSwitchSavedGeometry {
    $layout = Read-MonitorSwitchSavedLayout -Optional
    if ($null -ne $layout) { return $layout.GetGeometry() }
    Get-MonitorSwitchDisplayInfo | ForEach-Object {
        [pscustomobject]@{
            DisplayId = $_.DisplayId; DevicePath = $_.DevicePath
            X = $_.Position.X; Y = $_.Position.Y
        }
    }
}

function Save-MonitorSwitchLayout {
    <#
    .SYNOPSIS
        Save the full arrangement used by ALL and every subset profile.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string]$ConfigPath)

    $cfg = Get-MonitorSwitchConfig -Path $ConfigPath
    if (Test-MonitorSwitchSetMode $cfg) {
        if ($PSCmdlet.ShouldProcess((Get-MonitorSwitchStateDir), 'capture the active laptop arrangement')) {
            Disable-MonitorSwitchHdr -Confirm:$false
            Save-MonitorSwitchSet -Config $cfg
        }
        return
    }
    $path = Join-Path (Get-MonitorSwitchStateDir) 'layout.json'
    if (-not $PSCmdlet.ShouldProcess($path, 'save the full monitor arrangement')) { return }

    $displays = @(Get-MonitorSwitchDisplayInfo)
    if (-not $displays -or @($displays | Where-Object { -not $_.Active }).Count) {
        throw 'Enable every connected display before capture. A subset layout must not replace the full saved arrangement.'
    }
    Disable-MonitorSwitchHdr -Confirm:$false
    $layout = Get-MonitorSwitchDesktopLayout
    $geometry = @($layout.GetGeometry())
    if (-not $geometry -or @($geometry | Where-Object { -not $_.Active }).Count) {
        throw 'Connected displays changed during capture. Enable and arrange every monitor, then capture again.'
    }
    Write-MonitorSwitchSavedLayout -Layout $layout -Path $path
    Write-Host "Full layout saved to $path" -ForegroundColor Green
}

function Write-MonitorSwitchSavedLayout {
    param($Layout, [string]$Path)
    $json = [ordered]@{
        Format = 'MonitorSwitch.SavedLayout'
        Version = 1
        Paths = $Layout.PathsBase64()
        Modes = $Layout.ModesBase64()
        Displays = @(
            for ($i = 0; $i -lt $Layout.Available.Length; $i++) {
                [ordered]@{ PathIndex = $Layout.Available[$i]; DevicePath = $Layout.DevicePaths[$i] }
            }
        )
    } | ConvertTo-Json -Depth 5

    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    $temporary = "$path.$([guid]::NewGuid()).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $path) }
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
