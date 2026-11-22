@{
    mode = 'alignment'
    layout = @{ panelWidth = 3440; panelHeight = 1440 }
    refresh = @{ policy = 'native'; safeHz = 60 }
    hdr = @{ policy = 'off'; autoHdr = 'off' }
    osd = @{ policy = 'leave' }
    profiles = @{ all = @{ description = 'Restore home laptop alignment'; select = 'all' } }
}
