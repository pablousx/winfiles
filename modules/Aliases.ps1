function Invoke-WinfilesGit {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [object[]]$Arguments
    )

    & git -C $env:WINFILES_DIR @Arguments
}

function Invoke-NpmInstall {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & npm install @Arguments
}

function Invoke-NpmDev {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & npm run dev @Arguments
}

function Invoke-NpmBuild {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & npm run build @Arguments
}

function Invoke-NpmStart {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & npm run start @Arguments
}

function Invoke-PnpmInstall {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & pnpm install @Arguments
}

function Invoke-PnpmDev {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & pnpm run dev @Arguments
}

function Invoke-PnpmBuild {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & pnpm run build @Arguments
}

function Invoke-PnpmStart {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & pnpm run start @Arguments
}

function Invoke-YarnInstall {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & yarn install @Arguments
}

function Invoke-YarnDev {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & yarn dev @Arguments
}

function Invoke-YarnBuild {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & yarn build @Arguments
}

function Invoke-YarnStart {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
    & yarn start @Arguments
}

function Open-WinfilesCode {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [object[]]$Arguments
    )

    & code -r @Arguments
}

function Set-WinfilesParentLocation {
    [CmdletBinding()]
    param()
    Set-Location -Path '..'
}

function Set-WinfilesPreviousLocation {
    [CmdletBinding()]
    param()
    Set-Location -Path '-'
}

function Set-WinfilesDevLocation {
    [CmdletBinding()]
    param()

    $devPath = Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath 'dev'
    Set-Location -LiteralPath $devPath
}

function Get-WinfilesDirectoryListing {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [object[]]$Arguments
    )

    if (Get-Command -Name eza -CommandType Application -ErrorAction SilentlyContinue) {
        & eza --icons --all @Arguments
    }
    else {
        Get-ChildItem -Force @Arguments
    }
}

function Start-WinfilesItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Start-Process -FilePath $Path
}

function Restart-WinfilesProfile {
    [CmdletBinding()]
    param()

    . (Join-Path -Path $env:WINFILES_DIR -ChildPath 'profile.ps1')
}

function Open-WinfilesFileInEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    & $env:EDITOR $Path
}

function Open-WinfilesProfileInEditor {
    [CmdletBinding()]
    param()

    Open-WinfilesFileInEditor -Path (
        Join-Path -Path $env:WINFILES_DIR -ChildPath 'profile.ps1'
    )
}

function Open-WinfilesAliasesInEditor {
    [CmdletBinding()]
    param()

    Open-WinfilesFileInEditor -Path (
        Join-Path -Path $env:WINFILES_DIR -ChildPath 'modules\Aliases.ps1'
    )
}

function Open-WinfilesSettingsInEditor {
    [CmdletBinding()]
    param()

    $settingsPath = Join-Path -Path $env:WINFILES_DIR -ChildPath 'config\settings.psd1'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        $examplePath = Join-Path -Path $env:WINFILES_DIR -ChildPath 'config\settings.example.psd1'
        Copy-Item -LiteralPath $examplePath -Destination $settingsPath
    }

    Open-WinfilesFileInEditor -Path $settingsPath
}

function Start-WinfilesWebSearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Google', 'DuckDuckGo')]
        [string]$Engine,

        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Terms
    )

    $query = [Uri]::EscapeDataString(($Terms -join ' '))
    $uri = switch ($Engine) {
        'Google' { "https://www.google.com/search?q=$query" }
        'DuckDuckGo' { "https://duckduckgo.com/?q=$query" }
    }

    Start-Process -FilePath $uri
}

function Start-GoogleSearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$Terms
    )

    Start-WinfilesWebSearch -Engine Google -Terms $Terms
}

function Start-DuckDuckGoSearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$Terms
    )

    Start-WinfilesWebSearch -Engine DuckDuckGo -Terms $Terms
}

function Measure-WinfilesStartup {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$Count = 4
    )

    $powerShellPath = (Get-Process -Id $PID).Path
    1..$Count | ForEach-Object {
        Measure-Command {
            & $powerShellPath -NoLogo -Command exit
        } | Select-Object -ExpandProperty TotalMilliseconds
    }
}

function Update-WinfilesModule {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $setupPath = Join-Path -Path $env:WINFILES_DIR -ChildPath 'setup.ps1'
    if ($PSCmdlet.ShouldProcess($env:WINFILES_DIR, 'Install pinned modules and refresh completions')) {
        & $setupPath -PowerShellModules -Completions
    }
}

function Publish-WinfilesRepository {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [string]$Message
    )

    $branch = (& git -C $env:WINFILES_DIR symbolic-ref --quiet --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $branch) {
        throw 'Cannot publish winfiles from a detached HEAD.'
    }

    & git -C $env:WINFILES_DIR status --short
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read winfiles Git status.'
    }

    if (-not $Message) {
        $Message = Read-Host "Commit message (default: 'winfiles updated $(Get-Date -Format dd-MM-yy)')"
    }
    if (-not $Message) {
        $Message = "winfiles updated $(Get-Date -Format dd-MM-yy)"
    }

    if (-not $PSCmdlet.ShouldProcess(
            $env:WINFILES_DIR,
            "Commit tracked changes and push branch '$branch'"
        )) {
        return
    }

    & git -C $env:WINFILES_DIR add --update
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to stage tracked winfiles changes.'
    }

    & git -C $env:WINFILES_DIR diff --cached --quiet
    $diffExitCode = $LASTEXITCODE
    if ($diffExitCode -gt 1) {
        throw 'Unable to inspect staged winfiles changes.'
    }

    if ($diffExitCode -eq 1) {
        & git -C $env:WINFILES_DIR commit -m $Message
        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to commit winfiles changes.'
        }
    }
    else {
        Write-Information 'No tracked changes to commit.' -InformationAction Continue
    }

    & git -C $env:WINFILES_DIR push origin $branch
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to push branch '$branch'."
    }
}

$winfilesAliases = @{
    c                  = 'Open-WinfilesCode'
    cx                 = 'Set-WinfilesParentLocation'
    cz                 = 'Set-WinfilesPreviousLocation'
    dev                = 'Set-WinfilesDevLocation'
    duck               = 'Start-DuckDuckGoSearch'
    google             = 'Start-GoogleSearch'
    lc                 = 'Get-WinfilesDirectoryListing'
    nb                 = 'Invoke-NpmBuild'
    nd                 = 'Invoke-NpmDev'
    ni                 = 'Invoke-NpmInstall'
    ns                 = 'Invoke-NpmStart'
    open               = 'Start-WinfilesItem'
    pnb                = 'Invoke-PnpmBuild'
    pnd                = 'Invoke-PnpmDev'
    pni                = 'Invoke-PnpmInstall'
    pns                = 'Invoke-PnpmStart'
    reload             = 'Restart-WinfilesProfile'
    timepwsh           = 'Measure-WinfilesStartup'
    upload_winfiles    = 'Publish-WinfilesRepository'
    winfiles           = 'Invoke-WinfilesGit'
    winfiles_aliases   = 'Open-WinfilesAliasesInEditor'
    winfiles_config    = 'Open-WinfilesProfileInEditor'
    winfiles_settings  = 'Open-WinfilesSettingsInEditor'
    yb                 = 'Invoke-YarnBuild'
    yd                 = 'Invoke-YarnDev'
    yi                 = 'Invoke-YarnInstall'
    ys                 = 'Invoke-YarnStart'
}

foreach ($aliasName in $winfilesAliases.Keys) {
    Set-Alias -Name $aliasName -Value $winfilesAliases[$aliasName] -Scope Global -Force
}

Remove-Variable -Name aliasName, winfilesAliases -ErrorAction SilentlyContinue
