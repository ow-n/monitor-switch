@{
    mode = 'handoff'
    layout = @{
        panelWidth = 3440; panelHeight = 1440
        columnNames = @{ '-1' = 'left'; '0' = 'middle'; '1' = 'right' }
        rowNames = @{ '-1' = 'top'; '0' = 'bottom' }
    }
    refresh = @{ policy = 'safe'; safeHz = 60 }
    picture = @{ policy = 'leave' }
    profiles = @{
        all = @{ description = 'Bring back every captured home PC display'; select = 'all' }
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
    }
}
