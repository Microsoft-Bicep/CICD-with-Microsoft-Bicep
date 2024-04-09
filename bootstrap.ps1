[CmdletBinding()]
Param
(
    # Bootstrap PS Modules
    [switch]$Bootstrap,

    # Bootstrap VSCode
    [switch]$InstallVSCode,

    # Bootstrap Azure CLI
    [switch]$InstallAzureCLI,

    # Visual Studio Code installation
    [parameter()]
    [ValidateSet(, "64-bit", "32-bit")]
    [string]$Architecture = "64-bit",

    [parameter()]
    [ValidateSet("stable", "insider")]
    [string]$BuildEdition = "stable",

    [Parameter()]
    [ValidateNotNull()]
    [string[]]$AdditionalExtensions = @()
)

$ErrorActionPreference = 'Stop'


# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Error "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
    exit 1
}

if ($Bootstrap.IsPresent) {
    Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    if (-not (Get-Module -Name PSDepend -ListAvailable)) {
        Install-Module -Name PSDepend -Repository PSGallery
    }
    Import-Module -Name PSDepend -Verbose:$false
    Invoke-PSDepend -Path './requirements.psd1' -Install -Import -Force -WarningAction SilentlyContinue
}

if ($InstallVSCode.IsPresent) 
{
    if (($PSVersionTable.PSVersion.Major -le 5) -or $IsWindows)
    {
        switch ($Architecture)
        {
            "64-bit"
            {
                if ((Get-CimInstance -ClassName Win32_OperatingSystem).OSArchitecture -eq "64-bit")
                {
                    Write-Host "codePathBefore" $codePath -ForegroundColor White
                    $codePath = $env:ProgramFiles
                    Write-Host "codePathAfter" $codePath -ForegroundColor White
                    $bitVersion = "win32-x64"
                }
                else
                {
                    $codePath = $env:ProgramFiles
                    $bitVersion = "win32"
                    $Architecture = "32-bit"
                }
                break;
            }
            "32-bit"
            {
                if ((Get-CimInstance -ClassName Win32_OperatingSystem).OSArchitecture -eq "32-bit")
                {
                    $codePath = $env:ProgramFiles
                    $bitVersion = "win32"
                }
                else
                {
                    $codePath = ${env:ProgramFiles(x86)}
                    $bitVersion = "win32"
                }
                break;
            }
        }
        switch ($BuildEdition)
        {
            "Stable"
            {
                $codeCmdPath = "$codePath\Microsoft VS Code\bin\code.cmd"
                $appName = "Visual Studio Code ($($Architecture))"
                break;
            }
            "Insider"
            {
                $codeCmdPath = "$codePath\Microsoft VS Code Insiders\bin\code-insiders.cmd"
                $appName = "Visual Studio Code - Insiders Edition ($($Architecture))"
                break;
            }
        }
        try
        {
            $ProgressPreference = 'SilentlyContinue'
    
            if (!(Test-Path $codeCmdPath))
            {
                Write-Host "`nDownloading latest $appName..." -ForegroundColor Yellow
                Remove-Item -Force "$env:TEMP\vscode-$($BuildEdition).exe" -ErrorAction Stop
                Invoke-WebRequest -Uri "https://update.code.visualstudio.com/latest/$($bitVersion)/$($BuildEdition)" -OutFile "$env:TEMP\vscode-$($BuildEdition).exe"
    
                Write-Host "`nInstalling $appName..." -ForegroundColor Yellow
                Start-Process -Wait "$env:TEMP\vscode-$($BuildEdition).exe" -ArgumentList /silent, /mergetasks=!runcode
            }
            else
            {
                Write-Host "`n$appName is already installed." -ForegroundColor Yellow
            }
    
            $extensions = @("ms-azuretools.vscode-bicep") + $AdditionalExtensions
            foreach ($extension in $extensions)
            {
                Write-Host "`nInstalling extension $extension..." -ForegroundColor Yellow
                & $codeCmdPath --install-extension $extension
            }
            Write-Host "`nInstallation complete!`n`n" -ForegroundColor Green
        }
        finally
        {
            $ProgressPreference = 'Continue'
        }
    }
    else
    {
        Write-Error "This script is currently only supported on the Windows operating system."
    }
}

if ($InstallAzureCLI.IsPresent)
{
    Write-Output “Installing Azure CLI”
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    rm .\AzureCLI.msi
}