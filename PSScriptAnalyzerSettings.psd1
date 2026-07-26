@{
    Severity = @(
        'Error'
        'Warning'
    )
    ExcludeRules = @(
        # Interactive shell shortcuts intentionally use compact alias names.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
