#---------------------------------------------------------[Logging]--------------------------------------------------------#

## Verbose Logging (This will enable verbose logging to be printed to console for testing purposes)
$VerbosePreference="Continue"

## Debug (This will enable debug logging to be printed to console for testing purposes)
$DebugPreference="Continue"


## Enabling the Transcript wil give you more clarity on the errors you are getting
# This will write this transcript on the machine that it has ran on. This depends on what Hybrid Worker Group you run it from
#Start-Transcript -Path "C:\Temp\AutomationAccountTranscript_$(Get-Date -Format 'yyyy-MM-dd_HH_mm_ss').txt"


#---------------------------------------------------------[Imports]--------------------------------------------------------#


. ".\Proxmox\UnattendedInstall\CreateISO.ps1"
. ".\Proxmox\VirtualMachine\CreateVM.ps1"


#---------------------------------------------------------[Initializations]--------------------------------------------------------#

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Output "Not running as Administrator. Relaunching with elevated privileges..."
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
    exit
}

#---------------------------------------------------------[Running Sequence]--------------------------------------------------------#

Invoke-ProxmoxIsoBuilder -UnattendedInstallDir ".\Proxmox\UnattendedInstall\" -Verbose
Start-VirtualMachineBuild -vmName "HomeLab"