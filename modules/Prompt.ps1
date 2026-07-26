$ohMyPoshCommand = Get-Command -Name oh-my-posh -CommandType Application -ErrorAction SilentlyContinue
$ohMyPoshConfig = Join-Path -Path $env:WINFILES_DIR -ChildPath 'config\oh-my-posh.json'

if ($ohMyPoshCommand -and (Test-Path -LiteralPath $ohMyPoshConfig -PathType Leaf)) {
    try {
        $initializationText = & $ohMyPoshCommand.Source init pwsh --config $ohMyPoshConfig |
            Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "oh-my-posh exited with code $LASTEXITCODE."
        }

        # The generated code comes from the locally installed, explicitly
        # resolved executable rather than a network response.
        . ([scriptblock]::Create($initializationText))
    }
    catch {
        Write-Warning "Winfiles could not initialize Oh My Posh: $($_.Exception.Message)"
    }
}

Remove-Variable -Name initializationText, ohMyPoshCommand, ohMyPoshConfig -ErrorAction SilentlyContinue
