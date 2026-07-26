function Install-WinfilesPackageSet {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [ValidateSet('Core', 'Fnm')]
        [string]$Set
    )

    if (-not $IsWindows) {
        throw 'WinGet package installation is supported only on Windows.'
    }

    $wingetCommand = Get-Command -Name winget -CommandType Application -ErrorAction SilentlyContinue
    $wingetPath = if ($wingetCommand) {
        $wingetCommand.Source
    }
    else {
        Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) `
            -ChildPath 'Microsoft\WindowsApps\winget.exe'
    }
    if (-not (Test-Path -LiteralPath $wingetPath -PathType Leaf)) {
        throw 'WinGet is required to install Windows packages.'
    }

    $manifest = Get-WinfilesPackageManifest -RepositoryRoot $RepositoryRoot
    foreach ($package in @($manifest[$Set])) {
        if (Get-Command -Name $package.Command -CommandType Application -ErrorAction SilentlyContinue) {
            Write-WinfilesLog "$($package.Id) is already available; leaving it unchanged."
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($package.Id, 'Install package with WinGet')) {
            continue
        }

        Invoke-WinfilesNativeCommand -FilePath $wingetPath -ArgumentList @(
            'install',
            '--id', $package.Id,
            '--exact',
            '--source', 'winget',
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )
        Add-WinfilesOwnedPackage -Id $package.Id
    }
}

function Install-WinfilesCore {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot
    )

    Install-WinfilesPackageSet -RepositoryRoot $RepositoryRoot -Set Core
}
