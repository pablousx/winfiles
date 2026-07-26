$terminalIconsModule = Get-Module -ListAvailable -Name Terminal-Icons |
    Where-Object Version -GE ([version]'0.11.0') |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($terminalIconsModule) {
    Import-Module -Name $terminalIconsModule.Path -ErrorAction SilentlyContinue
}

if ($IsWindows -and
    -not (Get-Module -Name Microsoft.WinGet.CommandNotFound) -and
    (Get-Module -ListAvailable -Name Microsoft.WinGet.CommandNotFound)) {
    Import-Module -Name Microsoft.WinGet.CommandNotFound -ErrorAction SilentlyContinue
}

$fnmCommand = Get-Command -Name fnm -CommandType Application -ErrorAction SilentlyContinue
if ($fnmCommand) {
    try {
        $fnmInitialization = & $fnmCommand.Source env --use-on-cd --shell powershell |
            Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "fnm exited with code $LASTEXITCODE."
        }

        # The generated code comes from the locally installed, explicitly
        # resolved executable rather than a network response.
        . ([scriptblock]::Create($fnmInitialization))
    }
    catch {
        Write-Warning "Winfiles could not initialize FNM: $($_.Exception.Message)"
    }
}

if (-not $WinfilesSettings.DisableFzf -and
    (Get-Command -Name fzf -CommandType Application -ErrorAction SilentlyContinue)) {
    $psFzfModule = Get-Module -ListAvailable -Name PSFzf |
        Where-Object Version -GE ([version]'2.7.12') |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($psFzfModule) {
        Import-Module -Name $psFzfModule.Path -ErrorAction SilentlyContinue
    }
}

$inshellisensePath = Join-Path -Path (
    [Environment]::GetFolderPath('UserProfile')
) -ChildPath '.inshellisense\init\powershell\init.ps1'
$inshellisenseLoaded = Get-Variable -Name WinfilesInshellisenseLoaded `
    -Scope Global -ErrorAction SilentlyContinue
if (-not $inshellisenseLoaded -and
    (Test-Path -LiteralPath $inshellisensePath -PathType Leaf)) {
    . $inshellisensePath
    Set-Variable -Name WinfilesInshellisenseLoaded -Value $true -Scope Global
}

Remove-Variable -Name fnmCommand, fnmInitialization, inshellisenseLoaded, inshellisensePath,
    psFzfModule, terminalIconsModule -ErrorAction SilentlyContinue
