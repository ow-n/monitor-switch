@{
    mode = 'profile-sets'
    layout = @{ columnGap = 1000; rowGap = 700 }
    refresh = @{ policy = 'native'; safeHz = 60 }
    picture = @{ policy = 'leave' }
    profiles = @{
        all = @{ description = 'Restore the matching captured external layout'; select = 'all' }
        center = @{ description = 'Center column'; select = @{ columns = @('center') } }
        right = @{ description = 'Right column, topmost external primary'; select = @{ columns = @('right') }; primary = 'topmost' }
        left = @{ description = 'Left external column'; select = @{ columns = @('left') }; primary = 'topmost' }
        'center-right' = @{ description = 'Center and right columns'; select = @{ columns = @('center', 'right') } }
        'center-left' = @{ description = 'Center and left external columns'; select = @{ columns = @('center', 'left') } }
        'top-right' = @{ description = 'Top-right external display'; select = @{ columns = @('right'); rows = @('top') } }
    }
}
