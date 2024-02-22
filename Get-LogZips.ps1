# SYNOPSIS:
# This script collects various registry information, system details, and compresses specific folders into zip files.
# Data collected here will be used for troubleshooting WorkspaceONE UEM issues

# AUTHOR:
# James Romeo Gaspar (jg3098662)
# 20 February 2024

# DESCRIPTION:
# The script gathers information from different registry paths related to logon UI, OMADM, Rnrollments, and Profilelist keys.
# It also collects system details such as hostname and serial number.
# Furthermore, it compresses specific Airwatch folders into zip files for easier management.

# NOTES:
# - Ensure to run this script with appropriate permissions to access registry and file system.
# - The script generates a log file at C:\Temp\Zip-AirwatchFolders.txt for tracking operations.
# - Output files are stored in the C:\Temp directory with a timestamped filename.


function Get-LogonUIRegistryProperties {
    [CmdletBinding()]
    param ()

    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
    $keyProperties = Get-ItemProperty -Path $registryPath | Select-Object @{Name="Source";Expression={$registryPath}}, PSChildName, LastLoggedOnUser, LastLoggedOnUserSID, LastLoggedOnDisplayName, LastLoggedOnSAMUser
    Write-Output ""
    Write-Output "---------------- LogonUI Values ----------------"
    $keyProperties
}

function Get-OMADMSubkeyNames {
    [CmdletBinding()]
    param ()
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts"
    $subkeys = Get-ChildItem -Path $registryPath
    if ($subkeys.Count -eq 0) {
        Write-Output "---------------- OMADM Keys ----------------"
        Write-Output ""
        Write-Output "No OMADM subkeys found under $registryPath"
        Write-Output ""
        return
    }

    $subkeyValues = @()
    foreach ($subkey in $subkeys) {
        $subkeyName = Split-Path $subkey -Leaf
        try {
            $subkeyValue = (Get-ItemProperty -Path $subkey.PSPath).PSChildName
            $subkeyValues += $subkeyValue
        } 
        catch {
            Write-Error "Error occurred while retrieving value for subkey $($subkey.Name): $_"
        }
    }

    # Output the names of the subkeys
    Write-Output "---------------- OMADM Keys ----------------"
    Write-Output ""
    foreach ($index in 0..($subkeys.Count - 1)) {
        $source = $subkeys[$index].PSPath -replace "\\[^\\]+$"
        Write-Output "Source                  : $source"
        Write-Output "Enrollment GUID         : $($subkeyValues[$index])"
        Write-Output ""
    }
}


function Get-EnrollmentsWithUPN {
    [CmdletBinding()]
    param (
        [string]$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
    )

    try {
        $subkeys = Get-ChildItem -Path $RegistryPath -ErrorAction Stop

        $found = $false

        foreach ($subkey in $subkeys) {
            $value = Get-ItemProperty -Path $subkey.PSPath | Where-Object { $_.UPN -ne $null }
            if ($value) {
                $found = $true
                # Output all the values for the key
                $keyValues = Get-ItemProperty -Path $subkey.PSPath | Select-Object @{Name="Source";Expression={$RegistryPath}}, *
                $subkeyName = Split-Path $subkey -Leaf
                $subkeyValue = (Get-ItemProperty -Path $subkey.PSPath).PSChildName
                Write-Output "------------ Enrollment Values ------------"
                Write-Output ""
                Write-Output "Enrollment GUID         : $subkeyName"
                $keyValues 
                break
            }
        }

        if (-not $found) {
            Write-Output "------------ Enrollment Values ------------"
            Write-Output ""
            Write-Output "No enrollments found under $RegistryPath"
            Write-Output ""
        }
    } catch {
        Write-Error "Error occurred: $_"
    }
}


function Get-ProfileListKeysInfo {
    [CmdletBinding()]
    param ()

    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    $subkeys = Get-ChildItem -Path $registryPath

    Write-Output "------------ Profile List Keys ------------"
    Write-Output ""
    Write-Output "Source           : $registryPath"
    Write-Output ""

    foreach ($subkey in $subkeys) {
        $profile = Get-ItemProperty -Path $subkey.PSPath | Select-Object PSChildName, ProfileImagePath
        $profile
    }
}

function Zip-AirwatchFolders {
    param (
        [string]$ProgramDataPath = "C:\ProgramData\Airwatch",
        [string]$ProgramFilesPath = "C:\Program Files (x86)\Airwatch",
        [string]$DestinationPath = "C:\Temp",
        [string]$LogFile = "C:\Temp\Zip-AWFolders-$(Get-Date -Format "yyyyMMdd-HHmmss").txt"
    )

    try {
        if (!(Test-Path $LogFile)) {
            New-Item -Path $LogFile -ItemType File -Force | Out-Null
        } else {
            Clear-Content -Path $LogFile -Force
        }

        Write-Output "------------ Extracting and Compressing Airwatch Folders ------------" | Tee-Object -FilePath $LogFile -Append
        Write-Output "" | Tee-Object -FilePath $LogFile -Append

        $TimeStamp = Get-Date -Format "yyyyMMddHHmmss"
        $TempAWFolder = Join-Path -Path $DestinationPath -ChildPath "Airwatch_$TimeStamp"
        $TempAWx86Folder = Join-Path -Path $DestinationPath -ChildPath "Airwatchx86_$TimeStamp"

        if (Test-Path $ProgramDataPath) {
            Write-Output "Copying C:\ProgramData\Airwatch..." | Tee-Object -FilePath $LogFile -Append
            Write-Output "Copying files from $ProgramDataPath to $TempAWFolder" | Tee-Object -FilePath $LogFile -Append
            Copy-Item -Path $ProgramDataPath\* -Destination $TempAWFolder -Recurse -Force
            Write-Output "Files copied successfully." | Tee-Object -FilePath $LogFile -Append

            Write-Output "Zipping C:\ProgramData\Airwatch..." | Tee-Object -FilePath $LogFile -Append
            $DataZipFile = Join-Path -Path $DestinationPath -ChildPath "Airwatch_$TimeStamp.zip"
            Write-Output "Zipping files in $TempAWFolder to $DataZipFile" | Tee-Object -FilePath $LogFile -Append
            Compress-Archive -Path $TempAWFolder -DestinationPath $DataZipFile -Update
            Write-Output "Files zipped successfully." | Tee-Object -FilePath $LogFile -Append

            Write-Output "Cleaning up Temp Folder for C:\ProgramData\Airwatch..." | Tee-Object -FilePath $LogFile -Append
            Write-Output "Deleting folder $TempAWFolder" | Tee-Object -FilePath $LogFile -Append
            Remove-Item -Path $TempAWFolder -Recurse -Force
            Write-Output "Cleanup completed." | Tee-Object -FilePath $LogFile -Append
            Write-Output "" | Tee-Object -FilePath $LogFile -Append
            Write-Host "Processing completed for $ProgramDataPath" -ForegroundColor Green | Tee-Object -FilePath $LogFile -Append
            Write-Output "" | Tee-Object -FilePath $LogFile -Append
        } else {
            Write-Host "Folder not found on system: $ProgramDataPath" -ForegroundColor Red | Tee-Object -FilePath $LogFile -Append
            Write-Output "" | Tee-Object -FilePath $LogFile -Append
        }

        if (Test-Path $ProgramFilesPath) {
            Write-Output "Copying C:\Program Files (x86)\Airwatch..." | Tee-Object -FilePath $LogFile -Append
            Write-Output "Copying files from $ProgramFilesPath to $TempAWx86Folder" | Tee-Object -FilePath $LogFile -Append
            New-Item -Path $TempAWx86Folder -ItemType Directory -Force | Out-Null
            Copy-Item -Path $ProgramFilesPath\* -Destination $TempAWx86Folder -Recurse -Force
            Write-Output "Files copied successfully." | Tee-Object -FilePath $LogFile -Append
           
            Write-Output "Zipping C:\Program Files (x86)\Airwatch..." | Tee-Object -FilePath $LogFile -Append
            $FilesZipFile = Join-Path -Path $DestinationPath -ChildPath "Airwatchx86_$TimeStamp.zip"
            Write-Output "Zipping files in $TempAWx86Folder to $FilesZipFile" | Tee-Object -FilePath $LogFile -Append
            Compress-Archive -Path $TempAWx86Folder -DestinationPath $FilesZipFile -Update
            Write-Output "Files zipped successfully." | Tee-Object -FilePath $LogFile -Append

            Write-Output "Cleaning up Temp Folder for C:\Program Files (x86)\Airwatch..." | Tee-Object -FilePath $LogFile -Append
            Write-Output "Deleting folder $TempAWx86Folder" | Tee-Object -FilePath $LogFile -Append
            Remove-Item -Path $TempAWx86Folder -Recurse -Force
            Write-Output "Cleanup completed." | Tee-Object -FilePath $LogFile -Append
            Write-Output "" | Tee-Object -FilePath $LogFile -Append
            Write-Host "Processing completed for $ProgramFilesPath" -ForegroundColor Green | Tee-Object -FilePath $LogFile -Append
            Write-Output "" | Tee-Object -FilePath $LogFile -Append
        } else {
            Write-Host "Folder not found on system: $ProgramFilesPath" -ForegroundColor Red | Tee-Object -FilePath $LogFile -Append
            Write-Output "" | Tee-Object -FilePath $LogFile -Append
        }
        Write-Output "------------------------------------" | Tee-Object -FilePath $LogFile -Append
        Write-Output "" | Tee-Object -FilePath $LogFile -Append
        Write-Host "Registry information extraction completed." -ForegroundColor Yellow | Tee-Object -FilePath $LogFile -Append
        Write-Host "Please see C:\Temp\$Filename" -ForegroundColor Cyan | Tee-Object -FilePath $LogFile -Append
        Write-Output "" | Tee-Object -FilePath $LogFile -Append
        Write-Host "Completed compressing folder/s." -ForegroundColor Yellow | Tee-Object -FilePath $LogFile -Append
        Write-Host "Please see ($DataZipFile, $FilesZipFile)" -ForegroundColor Cyan | Tee-Object -FilePath $LogFile -Append
    }
    catch {
        Write-Error "An error occurred: $_"
        Write-Host "Error occurred. Please check the log file: $LogFile"
    }
}


$CurrentDateTime = Get-Date -Format "yyyyMMdd-HHmmss"
$Hostname = $env:COMPUTERNAME
$SerialNumber = Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty SerialNumber

$Header = @"

Hostname: $Hostname
Serial Number: $SerialNumber
Date/Time: $CurrentDateTime

"@

$Filename = "RegInfo_${Hostname}_${CurrentDateTime}.txt"

$Header | Out-File -FilePath "C:\Temp\$Filename"
Write-Output $Header

Get-LogonUIRegistryProperties | Tee-Object -FilePath "C:\Temp\$Filename" -Append 
Get-OMADMSubkeyNames | Tee-Object -FilePath "C:\Temp\$Filename" -Append
Get-EnrollmentsWithUPN | Tee-Object -FilePath "C:\Temp\$Filename" -Append
Get-ProfileListKeysInfo | Tee-Object -FilePath "C:\Temp\$Filename" -Append
Zip-AirwatchFolders
