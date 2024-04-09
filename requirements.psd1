@{
    PSDependOptions  = @{
        Target = 'CurrentUser'
    }
    InvokeBuild      = @{
        Version = 'latest'
    }
    az               = @{
        MinimumVersion = 'Latest'
    }
    PSRule               = @{
        Version = 'latest'
    }
    'PSRule.Rules.Azure' = @{
        Version = 'latest'
    }
    Pester               = @{
        Version = 'latest'
    }
}