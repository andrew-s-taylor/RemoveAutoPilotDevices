# ********************************************************
# * REMOVE AUTOPILOT DEVICES BY Paul Koning - 12-01-2024 *
# ********************************************************

# This scripts reads a csv-file with serial numbers of AutoPilot devices.
# Each device is removed from:
#                               - The Endpoint device list      (endpoint.microsoft.com)
#                               - The AutoPilot device list     (endpoint.microsoft.com)
#                               - The Azure device list         (portal.azure.com)
#
# Execute this script from an elevated command prompt with the command: powershell -ExecutionPolicy Bypass .\removeAutopilotDevices.ps1



function Check-Module ($m) {
    # Function to check if a module is installed
        if (-not (Get-Module -ListAvailable -Name $m)) {
            Write-Host "`nModule $m is not available, please install it first.`n`n" -ForegroundColor Red
            EXIT 1
        } else {
            Write-Host "`nModule $m is available." -ForegroundColor Green
        }
    }

    function getallpagination () {
        [cmdletbinding()]
            
        param
        (
            $url
        )
            $response = (Invoke-MgGraphRequest -uri $url -Method Get -OutputType PSObject)
            $alloutput = $response.value
            
            $alloutputNextLink = $response."@odata.nextLink"
            
            while ($null -ne $alloutputNextLink) {
                $alloutputResponse = (Invoke-MGGraphRequest -Uri $alloutputNextLink -Method Get -outputType PSObject)
                $alloutputNextLink = $alloutputResponse."@odata.nextLink"
                $alloutput += $alloutputResponse.value
            }
            
            return $alloutput
            }

            Function Connect-ToGraph {
                <#
            .SYNOPSIS
            Authenticates to the Graph API via the Microsoft.Graph.Authentication module.
             
            .DESCRIPTION
            The Connect-ToGraph cmdlet is a wrapper cmdlet that helps authenticate to the Intune Graph API using the Microsoft.Graph.Authentication module. It leverages an Azure AD app ID and app secret for authentication or user-based auth.
             
            .PARAMETER Tenant
            Specifies the tenant (e.g. contoso.onmicrosoft.com) to which to authenticate.
             
            .PARAMETER AppId
            Specifies the Azure AD app ID (GUID) for the application that will be used to authenticate.
             
            .PARAMETER AppSecret
            Specifies the Azure AD app secret corresponding to the app ID that will be used to authenticate.
            
            .PARAMETER Scopes
            Specifies the user scopes for interactive authentication.
             
            .EXAMPLE
            Connect-ToGraph -TenantId $tenantID -AppId $app -AppSecret $secret
             
            -#>
                [cmdletbinding()]
                param
                (
                    [Parameter(Mandatory = $false)] [string]$Tenant,
                    [Parameter(Mandatory = $false)] [string]$AppId,
                    [Parameter(Mandatory = $false)] [string]$AppSecret,
                    [Parameter(Mandatory = $false)] [string]$scopes
                )
            
                Process {
                    Import-Module Microsoft.Graph.Authentication
                    $version = (get-module microsoft.graph.authentication | Select-Object -expandproperty Version).major
            
                    if ($AppId -ne "") {
                        $body = @{
                            grant_type    = "client_credentials";
                            client_id     = $AppId;
                            client_secret = $AppSecret;
                            scope         = "https://graph.microsoft.com/.default";
                        }
                 
                        $response = Invoke-RestMethod -Method Post -Uri https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token -Body $body
                        $accessToken = $response.access_token
                 
                        $accessToken
                        if ($version -eq 2) {
                            write-host "Version 2 module detected"
                            $accesstokenfinal = ConvertTo-SecureString -String $accessToken -AsPlainText -Force
                        }
                        else {
                            write-host "Version 1 Module Detected"
                            Select-MgProfile -Name Beta
                            $accesstokenfinal = $accessToken
                        }
                        $graph = Connect-MgGraph  -AccessToken $accesstokenfinal 
                        Write-Host "Connected to Intune tenant $TenantId using app-based authentication (Azure AD authentication not supported)"
                    }
                    else {
                        if ($version -eq 2) {
                            write-host "Version 2 module detected"
                        }
                        else {
                            write-host "Version 1 Module Detected"
                            Select-MgProfile -Name Beta
                        }
                        $graph = Connect-MgGraph -scopes $scopes
                        Write-Host "Connected to Intune tenant $($graph.TenantId)"
                    }
                }
            }   
    
    # Clear screen and write info on screen
    Clear-Host
    Write-Host "`n********************************************************" -ForegroundColor Blue
    Write-Host "* REMOVE AUTOPILOT DEVICES BY Paul Koning - 12-01-2024 *" -ForegroundColor Blue
    Write-Host "********************************************************`n" -ForegroundColor Blue
    
    
    # Checking if required modules are installed
    # If there are any errors, make sure to install the modules first with:
    #   Install-Module -Name Microsoft.Graph.Authentication
    #   Install-Module -Name WindowsAutoPilotIntuneCommunity


    
    Write-Host "`nChecking if required modules are installed."
    Check-Module("Microsoft.Graph.Authentication")
    Check-Module("WindowsAutoPilotIntuneCommunity")
    
    
    # Connect with Microsoft services
    
    Write-Host "`nConnecting to Microsoft services. Enter your credentials."
    
    Write-Host "`nConnecting to MgGraph`n"		
Connect-ToGraph -scopes "DeviceManagementConfiguration.ReadWrite.All,DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementConfiguration.Read.All,DeviceManagementManagedDevices.Read.All,Directory.Read.All,Directory.ReadWrite.All,User.Read.All,User.ReadWrite.All"

    
    # Paths to files
    $csvPath = ".\serialNumbers.csv"        # This csv-file contains the serial numbers of the AutoPilot devices. Each serial number has to be stored on a seperate line.
    $logPath = ".\notFoundDevices.log"      # Serial numbers that are not found as AutoPilotdevices are stored in this logfile
    
    # Append date and time to logfile
    $dateTimeString = Get-Date -Format "dd-MM-yyy HH:mm:ss"
    " " | Out-File -FilePath $logPath -Append
    $dateTimeString | Out-File -FilePath $logPath -Append
    
    # Read the CSV file
    $serialNumbers = Get-Content -Path $csvPath
    
    # Retrieve al Microsoft Graph devices
    Write-Host "Retrieving all Microsoft Graph devices.`n"	
    $allmanageddevices = getallpagination -url "https://graph.microsoft.com/beta/devicemanagement/manageddevices"
    $allmgdevices = getallpagination -url "https://graph.microsoft.com/beta/devices"
    
    Write-Host "Deleting all devices by serial number.`n"	
    
    # Iterate over each serial number
    foreach ($serialNumber in $serialNumbers) {
        # Get the autopilot device by the serial number
        $apdevice = Get-AutoPilotDevice | Where-Object SerialNumber -eq $serialNumber 
    
        if ($apdevice) { # Device was found
            # Show device information    
            $apdeviceid = $apdevice.azureActiveDirectoryDeviceId
            $apid = $apdevice.id
            $apmanageddeviceid = $apdevice.managedDeviceId
            
            Write-Host "SerialNumber: $serialNumber" -ForegroundColor Blue
            Write-Host "DeviceId: $apdeviceid"
            Write-Host "Id: $apid"
            Write-Host "ManagedDeviceId: $apmanageddeviceid `n"		
            
            # Remove the Intune managed device
            Write-Host "Removing from Intune" 
            try {               
                Invoke-MgGraphRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$apmanageddeviceid" -Method Delete 
            }
            catch {
                Write-Host "Could not remove from Intune devicelist. The device might have been already deleted manually in Intune." -ForegroundColor Red
            }			
    
            # Remove the AutoPilot device
            Write-Host "Removing from AutoPilot"            
            Remove-AutopilotDevice $apid
    
            # Remove the Azure AD device
            Write-Host "Removing from AzureAD`n`n"            
            $mgdevice = $allmgdevices | Where-Object { $_.DeviceId -eq $apdeviceid }
            $mgdeviceid = $mgdevice.id
            Invoke-MgGraphRequest -uri "https://graph.microsoft.com/beta/devices/$mgdeviceid" -Method Delete
            Remove-MgDevice -DeviceID $mgdevice.id
    
        } else { # Device was not found
            # Write the serial number from the device that was not found to the log file
            $serialNumber | Out-File -FilePath $logPath -Append
            
            # Write the not found serial number to the screen
            Write-Host "Device with SerialNumber '$serialNumber' not found.`n`n" -ForegroundColor Red	
        }
    }    
