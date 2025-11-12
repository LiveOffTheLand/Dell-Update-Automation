<#
.SYNOPSIS
    Check and install Windows Updates using PSWindowsUpdate module.

.DESCRIPTION
    This script automates the process of checking for and installing Windows Updates.
    It uses the PSWindowsUpdate module to interact with Windows Update services.

.PARAMETER AutoReboot
    Automatically reboot the system if required after updates are installed.

.PARAMETER AcceptAll
    Automatically accept all updates without prompting.

.PARAMETER LogPath
    Path to store the update log file. Default is .\logs\WindowsUpdates.log

.EXAMPLE
    .\PSWindowsUpdates.ps1
    Check and list available updates without installing.

.EXAMPLE
    .\PSWindowsUpdates.ps1 -AcceptAll -AutoReboot
    Install all available updates and reboot if necessary.

.NOTES
    Version: v0.1
    Author: PowerShell Automation
    Date: 2025-11-10
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$AutoReboot,
    
    [Parameter(Mandatory=$false)]
    [switch]$AcceptAll,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\logs\WindowsUpdates.log"
)

# Ensure logs directory exists
$logDir = Split-Path -Path $LogPath -Parent
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Function to write log messages
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Main script execution
try {
    Write-Log "=== Windows Update Check Started ===" -Level Info
    
    # Check for administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log "This script requires administrator privileges. Please run as Administrator." -Level Error
        exit 1
    }
    
    # Check if PSWindowsUpdate module is installed
    Write-Log "Checking for PSWindowsUpdate module..." -Level Info
    $module = Get-Module -ListAvailable -Name PSWindowsUpdate
    
    if (-not $module) {
        Write-Log "PSWindowsUpdate module not found. Installing..." -Level Warning
        try {
            Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
            Write-Log "PSWindowsUpdate module installed successfully." -Level Success
        }
        catch {
            Write-Log "Failed to install PSWindowsUpdate module: $($_.Exception.Message)" -Level Error
            exit 1
        }
    }
    else {
        Write-Log "PSWindowsUpdate module found (Version: $($module.Version))." -Level Success
    }
    
    # Import the module
    Write-Log "Importing PSWindowsUpdate module..." -Level Info
    Import-Module PSWindowsUpdate -ErrorAction Stop
    
    # Check for available updates
    Write-Log "Checking for available Windows Updates..." -Level Info
    $updates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop
    
    if ($updates.Count -eq 0) {
        Write-Log "No updates available. System is up to date." -Level Success
        Write-Log "=== Windows Update Check Completed ===" -Level Info
        exit 0
    }
    
    # Display available updates
    Write-Log "Found $($updates.Count) update(s) available:" -Level Info
    foreach ($update in $updates) {
        Write-Log "  - $($update.Title) (Size: $([math]::Round($update.Size / 1MB, 2)) MB)" -Level Info
    }
    
    # Install updates if AcceptAll is specified
    if ($AcceptAll) {
        Write-Log "Installing updates..." -Level Info
        
        $installParams = @{
            MicrosoftUpdate = $true
            AcceptAll = $true
            IgnoreReboot = -not $AutoReboot
            Verbose = $true
        }
        
        if ($AutoReboot) {
            Write-Log "AutoReboot is enabled. System will reboot if necessary." -Level Warning
            $installParams.Add('AutoReboot', $true)
        }
        
        $installResults = Install-WindowsUpdate @installParams -ErrorAction Stop
        
        # Log installation results
        foreach ($result in $installResults) {
            if ($result.Result -eq 'Installed') {
                Write-Log "Installed: $($result.Title)" -Level Success
            }
            elseif ($result.Result -eq 'Failed') {
                Write-Log "Failed: $($result.Title) - $($result.ResultCode)" -Level Error
            }
            else {
                Write-Log "Status: $($result.Title) - $($result.Result)" -Level Info
            }
        }
        
        # Check if reboot is required
        $rebootRequired = Get-WURebootStatus -Silent
        if ($rebootRequired) {
            Write-Log "System reboot is required to complete the installation." -Level Warning
            if (-not $AutoReboot) {
                Write-Log "Please restart your computer manually." -Level Warning
            }
        }
        else {
            Write-Log "No reboot required." -Level Success
        }
    }
    else {
        Write-Log "Use -AcceptAll parameter to install updates automatically." -Level Info
    }
    
    Write-Log "=== Windows Update Check Completed ===" -Level Info
}
catch {
    Write-Log "An error occurred: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
