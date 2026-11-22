@{
    mode = 'alignment'
    layout = @{ panelWidth = 1920; panelHeight = 1080 }
    refresh = @{ policy = 'native'; safeHz = 60 }
    hdr = @{ policy = 'off'; autoHdr = 'off' }
    osd = @{ policy = 'leave' }
    profiles = @{ all = @{ description = 'Restore office laptop alignment'; select = 'all' } }
}
