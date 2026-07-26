function Install-WinfilesFnm {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter()]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$NodeVersion = '24.12.0'
    )

    $fnmCommand = Get-Command -Name fnm -CommandType Application -ErrorAction SilentlyContinue
    $fnmPath = if ($fnmCommand) { $fnmCommand.Source } else { $null }
    if (-not $fnmPath -and $IsWindows) {
        $candidatePaths = @(
            (Join-Path -Path (
                    [Environment]::GetFolderPath('LocalApplicationData')
                ) -ChildPath 'Microsoft\WinGet\Links\fnm.exe')
            (Join-Path -Path $env:ProgramData -ChildPath 'chocolatey\bin\fnm.exe')
        )
        foreach ($candidatePath in $candidatePaths) {
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                $fnmPath = $candidatePath
                break
            }
        }
    }

    if (-not $fnmPath) {
        Install-WinfilesPackageSet -RepositoryRoot $RepositoryRoot -Set Fnm
        $fnmCommand = Get-Command -Name fnm -CommandType Application -ErrorAction SilentlyContinue
        if ($fnmCommand) {
            $fnmPath = $fnmCommand.Source
        }
        elseif ($IsWindows) {
            $winGetLink = Join-Path -Path (
                [Environment]::GetFolderPath('LocalApplicationData')
            ) -ChildPath 'Microsoft\WinGet\Links\fnm.exe'
            if (Test-Path -LiteralPath $winGetLink -PathType Leaf) {
                $fnmPath = $winGetLink
            }
        }
    }

    if (-not $fnmPath) {
        throw 'FNM was installed but is not visible in PATH. Restart PowerShell and rerun setup.'
    }

    if ($PSCmdlet.ShouldProcess("Node.js $NodeVersion", 'Install with FNM and set as default')) {
        Invoke-WinfilesNativeCommand -FilePath $fnmPath -ArgumentList @(
            'install', $NodeVersion
        )
        Invoke-WinfilesNativeCommand -FilePath $fnmPath -ArgumentList @(
            'default', $NodeVersion
        )
    }
}
