@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive CLI: coloured console output is the point.
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
    }
}
