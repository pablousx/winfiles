if ($Host.Name -eq 'ConsoleHost' -and
    (Get-Module -ListAvailable -Name PSReadLine)) {
    try {
        Import-Module -Name PSReadLine -ErrorAction Stop

        $psReadLineOptions = @{
            BellStyle                     = 'None'
            EditMode                      = 'Emacs'
            HistoryNoDuplicates           = $true
            HistorySaveStyle              = 'SaveIncrementally'
            HistorySearchCursorMovesToEnd = $true
            MaximumHistoryCount           = 50000
        }

        if ($WinfilesSettings.DisablePredictions) {
            $psReadLineOptions.PredictionSource = 'None'
        }
        elseif ($Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected) {
            $psReadLineOptions.PredictionSource = 'History'
            $psReadLineOptions.PredictionViewStyle = 'ListView'
        }

        Set-PSReadLineOption @psReadLineOptions
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Spacebar' -Function Complete
    }
    catch {
        Write-Warning "Winfiles could not configure PSReadLine: $($_.Exception.Message)"
    }
}
