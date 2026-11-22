@{
    mode = 'handoff'
    layout = @{
        panelWidth = 3440; panelHeight = 1440
        columnNames = @{ '-1' = 'left'; '0' = 'middle'; '1' = 'right' }
        rowNames = @{ '-1' = 'top'; '0' = 'bottom' }
    }
    refresh = @{ policy = 'safe'; safeHz = 60; displays = @{}; overrides = @() }
    hdr = @{ policy = 'off'; autoHdr = 'off'; sdrNits = 292 }
    osd = @{ policy = 'leave'; reference = 'DISPLAY1'; settings = @{} }
    parity = @{ ignore = @() }
    profiles = @{
        all = @{ description = 'Restore every captured home PC display'; select = 'all' }
        left = @{
            description = 'Left column on PC; give center HDMI inputs to laptop'
            select = @{ columns = @('left') }; primary = @{ row = 'top' }
            inputs = @{ 'top-middle' = 'HDMI1'; 'bottom-middle' = 'HDMI1' }
        }
        middle = @{
            description = 'Middle column only'; select = @{ columns = @('middle') }; primary = @{ row = 'bottom' }
        }
        'left-middle' = @{
            description = 'Keep left and reclaim center DisplayPort inputs for PC'
            select = @{ columns = @('left', 'middle') }; primary = @{ column = 'middle'; row = 'bottom' }
            inputs = @{ 'top-middle' = 'DP1'; 'bottom-middle' = 'DP1' }
        }
        'top-left' = @{
            description = 'Top-left only'; select = @{ columns = @('left'); rows = @('top') }; primary = 'first'
        }
        single = @{
            description = 'Upright bottom-middle only'
            select = @{ columns = @('middle'); rows = @('bottom') }; primary = 'first'
        }
    }
}
