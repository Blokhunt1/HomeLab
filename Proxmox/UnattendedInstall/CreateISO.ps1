#---------------------------------------------------------[Logging]--------------------------------------------------------#

## Verbose Logging (This will enable verbose logging to be printed to console for testing purposes)
#$VerbosePreference="Continue"

## Debug (This will enable debug logging to be printed to console for testing purposes)
#$DebugPreference="Continue"


## Enabling the Transcript wil give you more clarity on the errors you are getting
# This will write this transcript on the machine that it has ran on. This depends on what Hybrid Worker Group you run it from
#Start-Transcript -Path "C:\Temp\AutomationAccountTranscript_$(Get-Date -Format 'yyyy-MM-dd_HH_mm_ss').txt"


#--------------------------------------------------------[Functions]------------------------------------------------------#

function Add-ActiveIpToToml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UnattendedInstallDir = ".\Proxmox\UnattendedInstall\"
    )
    <#
    .SYNOPSIS
    Inserts the active IPv4 address into a TOML template and outputs the updated file.

    .DESCRIPTION
    This function retrieves the active IPv4 address by finding the default route (destination 0.0.0.0/0)
    and determining the corresponding network interface. It then reads the entire TOML template file,
    replaces the placeholder "$LocalNetworkIP" in the [post-installation-webhook] section with the active IP,
    and writes the updated content to "answer.toml" in the UnattendedInstall folder.

    .PARAMETER UnattendedInstallDir
    The base directory where the "Automation_Config\answer_template.toml" is located and where the final
    "answer.toml" will be written.
    #>

    $TempConfigPath = "Automation_Config\"
    $TempTomlFile = "answer_template.toml"
    $TemplateFilePath = Join-Path -Path $UnattendedInstallDir -ChildPath ($TempConfigPath + $TempTomlFile)
    $OutputFilePath   = Join-Path -Path $UnattendedInstallDir -ChildPath ($TempConfigPath + "answer.toml")

    try {
        Write-Verbose "Retrieving default route..."
        $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object -Property RouteMetric | Select-Object -First 1
        if (-not $defaultRoute) {
            Write-Verbose "No default route found."
            return
        }
        Write-Debug "Default route InterfaceIndex: $($defaultRoute.InterfaceIndex)"

        Write-Verbose "Retrieving active IPv4 address from InterfaceIndex $($defaultRoute.InterfaceIndex)..."
        $activeIpObj = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceIndex -eq $defaultRoute.InterfaceIndex }
        if (-not $activeIpObj) {
            Write-Verbose "No IPv4 address found for InterfaceIndex $($defaultRoute.InterfaceIndex)."
            return
        }
        $activeIp = "http://" + $activeIpObj[0].IPAddress + ":8080"
        Write-Debug "Active IP: $activeIp"

        Write-Verbose "Reading TOML template file from: $TemplateFilePath"
        $content = Get-Content -Path $TemplateFilePath -Raw

        Write-Verbose "Replacing placeholder \$LocalNetworkIP with the active IP..."
        $newContent = $content -replace "#LocalNetworkIP", $activeIp

        if(Test-Path -Path $OutputFilePath){
            Write-Verbose "Removing old answer file"
            Remove-Item -Path $OutputFilePath -Force -ErrorAction Stop
        }

        Write-Verbose "Writing updated content to: $OutputFilePath"
        Set-Content -Path $OutputFilePath -Value $newContent
        Write-Verbose "TOML file updated successfully."
    }
    catch {
        Write-Verbose "An error occurred: $_"
    }
}



function Invoke-ProxmoxIsoBuilder {
    [CmdletBinding()]
    param(
        # The name of the ISO file to search for in the build context.
        [Parameter(Mandatory=$false)]
        [string]$SourceName = "source-auto-from-iso.iso",
        
        # The Docker image name to tag.
        [Parameter(Mandatory=$false)]
        [string]$ImageName = "proxmox-iso-builder",

        # The Docker image name to tag.
        [Parameter(Mandatory=$false)]
        [string]$UnattendedInstallDir = "./Proxmox/UnattendedInstall/",
        
        # The temporary Docker container name.
        [Parameter(Mandatory=$false)]
        [string]$ContainerName = "proxmox-iso-container",
        
        # The destination path on the host machine for the ISO.
        [Parameter(Mandatory=$false)]
        [string]$DestinationIsoPath = "./source-auto-from-iso.iso"
    )

    $DockerFile = "Dockerfile"

    Write-Verbose "Building Docker image '$ImageName'..."
    docker build -t $ImageName -f ($UnattendedInstallDir + $DockerFile) $UnattendedInstallDir

    Write-Verbose "Creating temporary container '$ContainerName'..."
    docker create --name $ContainerName $ImageName
    
    # Remove the hash if there is a hash file as it has to be old at this time
    if(Test-Path "$UnattendedInstallDir/hash.md5"){
        Remove-Item -Path "$UnattendedInstallDir/hash.md5" -Force
    }

    Write-Verbose "Copying hash file to check if copy action is needed"
    docker cp "$($ContainerName):/export/hash.md5" "$UnattendedInstallDir/hash.md5"

    try {
        if((Test-Path "$UnattendedInstallDir/$SourceName") -and (Test-Path "$UnattendedInstallDir/hash.md5")){
            $isoHashLocal = (Get-FileHash -Path "$UnattendedInstallDir/source-auto-from-iso.iso" -Algorithm MD5).Hash
            $isoHashDocker = Get-Content -Path "$UnattendedInstallDir/hash.md5"
            if ($isoHashLocal -eq $isoHashDocker){
                Write-Verbose "Won't get new ISO as they are the same '$ContainerName'..."
            }
            else {
                if (Test-Path "$UnattendedInstallDir/$SourceName") {
                        Write-Verbose "Found file: $($file.FullName). Removing it..."
                        Remove-Item -Path $file.FullName -Force
                        Write-Verbose "Removed file: $($file.FullName)."
                }
                Write-Verbose "ISO in local folder is different from ISO on machine"
                Write-Verbose "Copying ISO from container '$ContainerName' ($ExportedIsoPath) to host ($DestinationIsoPath)..."
                docker cp "$($ContainerName):/export/source-auto-from-iso.iso" "$UnattendedInstallDir/source-auto-from-iso.iso"
            }
        }
    }
    catch {
        Write-Error "Verifying hash will copy the ISO anyways $_"
        Write-Verbose "Copying ISO from container '$ContainerName' ($ExportedIsoPath) to host ($DestinationIsoPath)..."
        docker cp "$($ContainerName):/export/source-auto-from-iso.iso" "$UnattendedInstallDir/source-auto-from-iso.iso"
    }
    
    # Clean up after one self
    if (Test-Path "$UnattendedInstallDir/hash.md5"){
        Remove-Item -Path "$UnattendedInstallDir/hash.md5" -Force
    }
    if (Test-Path ($TempConfigPath + "answer.toml")){
        Remove-Item -Path ($TempConfigPath + "answer.toml") -Force
    }


    Write-Verbose "Removing temporary container '$ContainerName'..."
    docker rm $ContainerName
    

    Write-Verbose "Process complete. The ISO is available at '$UnattendedInstallDir/source-auto-from-iso.iso'."
}


#--------------------------------------------------------[Running Sequence]------------------------------------------------------#

function Start-BuildUnatendedProxmoxSetup {
    param (
        [string]$UnattendedInstallDir
    )

    try {
        Add-ActiveIpToToml
        Start-BuildUnatendedProxmoxSetup -UnattendedInstallDir $UnattendedInstallDir
    }
    catch {
        throw "Error with process of building unattended ISO file: $_"
    }
    
    
}