#---------------------------------------------------------[Logging]--------------------------------------------------------#

## Verbose Logging (This will enable verbose logging to be printed to console for testing purposes)
#$VerbosePreference="Continue"

## Debug (This will enable debug logging to be printed to console for testing purposes)
#$DebugPreference="Continue"


## Enabling the Transcript wil give you more clarity on the errors you are getting
# This will write this transcript on the machine that it has ran on. This depends on what Hybrid Worker Group you run it from
#Start-Transcript -Path "C:\Temp\AutomationAccountTranscript_$(Get-Date -Format 'yyyy-MM-dd_HH_mm_ss').txt"


#---------------------------------------------------------[Initializations]--------------------------------------------------------#


$script:vmName = "HomeLabTest"


#--------------------------------------------------------[Functions]------------------------------------------------------#

function Test-ISOFile {
    param (
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    <#
    .SYNOPSIS
        Checks that the ISO file exists at the provided path.
    #>

    if (!(Test-Path $IsoPath)) {
        Write-Error "Error: ISO file not found at $IsoPath. Please update the IsoPath variable."
        exit 1
    } else {
        Write-Verbose "ISO file found at $IsoPath"
    }
}


function Remove-ExistingVM {
    param (
        [Parameter(Mandatory)]
        [string]$VmName,
        [Parameter(Mandatory)]
        [string]$VdiskPath
    )

    <#
    .SYNOPSIS
        Removes an existing VirtualBox VM and virtual disk if they exist.
    #>

    $existingVMs = & VBoxManage list vms | Select-String $VmName
    if ($existingVMs) {
        Write-Debug "VM '$VmName' already exists. Removing it..."
        & VBoxManage unregistervm $VmName --delete
    }
    if (Test-Path $VdiskPath) {
        Write-Debug "Virtual disk '$VdiskPath' already exists. Removing it..."
        Remove-Item $VdiskPath -Force
    }
}


function New-VirtualMachine {
    param (
        [Parameter(Mandatory)]
        [string]$VmName,
        [string]$OSType = "Debian_64"
    )
    <#
    .SYNOPSIS
        Creates and registers a new VirtualBox VM.
    #>

    & VBoxManage createvm --name $VmName --ostype $OSType --register
    Write-Verbose "Created and registered VM '$VmName'"
}


function Set-VMSettings {
    param (
        [Parameter(Mandatory)]
        [string]$VmName,
        [Parameter(Mandatory)]
        [int]$Memory,
        [Parameter(Mandatory)]
        [int]$Vram
    )

    <#
    .SYNOPSIS
        Configures the VM settings such as memory, video memory, and network.
    #>

    & VBoxManage modifyvm $VmName --memory $Memory --vram $Vram --hwvirtex on --pae on --ioapic on --nic1 nat
    Write-Verbose "Configured VM settings for '$VmName'"
    Write-Debug "Memory: $Memory MB, VRAM: $Vram MB"
}


function Set-StorageConfiguration {
    param (
        [Parameter(Mandatory)]
        [string]$VmName,
        [Parameter(Mandatory)]
        [string]$VdiskPath,
        [Parameter(Mandatory)]
        [int]$DiskSize,
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    <#
    .SYNOPSIS
        Configures storage controllers, creates a virtual disk, and attaches the ISO.
    #>

    & VBoxManage storagectl $VmName --name "SATA Controller" --add sata --controller IntelAHCI
    & VBoxManage createmedium disk --filename $VdiskPath --size $DiskSize --format VDI
    & VBoxManage storageattach $VmName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $VdiskPath
    & VBoxManage storagectl $VmName --name "IDE Controller" --add ide
    & VBoxManage storageattach $VmName --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium $IsoPath
    Write-Verbose "Configured storage for VM '$VmName'"
    Write-Debug "Disk: $VdiskPath ($DiskSize MB) attached with ISO: $IsoPath"
}


function Start-VM {
    param (
        [Parameter(Mandatory)]
        [string]$VmName,
        [Parameter(Mandatory)]
        [string]$VdiskPath,
        [Parameter(Mandatory)]
        [int]$DiskSize,
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    <#
    .SYNOPSIS
        Starts the VM and displays basic information.
    #>

    & VBoxManage startvm $VmName --type gui
    Write-Verbose "VM '$VmName' has been created and started."
    Write-Debug "Virtual disk: $VdiskPath ($DiskSize MB) | ISO: $IsoPath"
}


function Wait-ForInstallResponse {
    param (
        [int]$Port = 8080
    )

    <#
    .SYNOPSIS
        Waits for an HTTP request on the specified port and responds, used to pause for the auto install.
    #>

    Write-Verbose "Retrieving default route..."
    $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object -Property RouteMetric | Select-Object -First 1
    if (-not $defaultRoute) {
        Write-Verbose "No default route found."
        return
    }
    Write-Debug "Default route InterfaceIndex: $($defaultRoute.InterfaceIndex)"

    Write-Verbose "Retrieving active IPv4 address..."
    $activeIpObj = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceIndex -eq $defaultRoute.InterfaceIndex }
    if (-not $activeIpObj) {
        Write-Verbose "No IPv4 address found."
        return
    }

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://$($activeIpObj[0].IPAddress):$Port/")
    $listener.Start()
    Write-Verbose "Listening on http://$($activeIpObj[0].IPAddress):$Port/ ... Waiting for auto install response"

    $context = $listener.GetContext()
    $request = $context.Request

    $context.Response.StatusCode = 200
    $responseString = 'Success'
    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($responseString)
    $context.Response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
    $context.Response.Close()

    Write-Verbose "Received request: $($request.HttpMethod) $($request.Url)"
    $listener.Stop()
}


function Stop-VirtualMachine {
    param (
        [Parameter(Mandatory)]
        [string]$VmName
    )

    <#
    .SYNOPSIS
        Shuts down the specified VM.
    #>

    Write-Verbose "Shutting down VM '$VmName'"
    & VBoxManage controlvm $VmName poweroff
    Start-Sleep -Seconds 5
}


function Set-PortForwarding {
    param (
        [Parameter(Mandatory)]
        [string]$VmName
    )

    <#
    .SYNOPSIS
        Removes the install medium and sets up port forwarding rules for the VM.
    #>

    Write-Verbose "Removing install medium and adding port forwarding for VM '$VmName'"
    
    & VBoxManage storageattach $VmName --storagectl "IDE Controller" --port 1 --device 0 --medium none
    & VBoxManage modifyvm $VmName --natpf1 "SSH,tcp,,22,,22"
    & VBoxManage modifyvm $VmName --natpf1 "HTTP,tcp,,80,,80"
    & VBoxManage modifyvm $VmName --natpf1 "HTTPS,tcp,,443,,443"
    & VBoxManage modifyvm $VmName --natpf1 "FTP,tcp,,21,,21"
    & VBoxManage modifyvm $VmName --natpf1 "FTPS,tcp,,990,,990"
    & VBoxManage modifyvm $VmName --natpf1 "SFTP,tcp,,22,,22"
    & VBoxManage modifyvm $VmName --natpf1 "Custom8006,tcp,,8006,,8006"
    
    Start-Sleep -Seconds 5
}


function Start-VirtualMachine {
    param (
        [Parameter(Mandatory)]
        [string]$VmName
    )

    <#
    .SYNOPSIS
        Boots the specified VM.
    #>

    Write-Verbose "Booting VM '$VmName'"
    & VBoxManage startvm $VmName --type gui
    Start-Sleep -Seconds 10
    Write-Verbose "VM '$VmName' has been started"
}


#--------------------------------------------------------[Constants]------------------------------------------------------#


# Main Script Execution
# Define constants and parameters
$PORT      = 8080
$ISOPATH   = "C:\Repo\HomeLab\Proxmox\UnattendedInstall\source-auto-from-iso.iso"
$ramSize   = 8000         # Memory in MB
$vramSize  = 128          # Video RAM in MB
$diskSize  = 20000        # Disk size in MB (~20GB)
$vdiskPath = "$HOME/VirtualBox VMs/$script:vmName/$script:vmName.vdi"


#--------------------------------------------------------[Running Sequence]------------------------------------------------------#


# Execute functions
function Start-VirtualMachineBuild {
    [CmdletBinding()]
    param (
        [string]$vmName = "HomeLabTest"
    )

    try {
        $script:vmName = $vmName
        Test-ISOFile -IsoPath $ISOPATH
        Remove-ExistingVM -VmName $vmName -VdiskPath $vdiskPath
        New-VirtualMachine -VmName $vmName
        Set-VMSettings -VmName $vmName -Memory $ramSize -Vram $vramSize
        Set-StorageConfiguration -VmName $vmName -VdiskPath $vdiskPath -DiskSize $diskSize -IsoPath $ISOPATH
        Start-VM -VmName $vmName -VdiskPath $vdiskPath -DiskSize $diskSize -IsoPath $ISOPATH
        Wait-ForInstallResponse -Port $PORT
        Stop-VirtualMachine -VmName $vmName
        Set-PortForwarding -VmName $vmName
        Start-VirtualMachine -VmName $vmName
    }
    catch {
        throw "Error in virtual machine install: $_"
    }
    

}