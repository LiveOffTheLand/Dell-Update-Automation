#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Dell Update Automation - Main Script
.DESCRIPTION
    Comprehensive Dell update management using Dell Command Update CLI
    - Validates Dell hardware and prerequisites
    - Scans for available updates
    - Maintains Excel catalog of updates
    - Installs updates with configurable reboot options
    - Provides verbose logging and progress reporting
.PARAMETER SkipDellCheck
    Skip Dell hardware validation (for testing)
.PARAMETER NoReboot
    Prevent automatic reboot after updates
.PARAMETER CheckOnly
    Only check for updates, don't install
.PARAMETER UpdateType
    Type of updates to install (all, bios, firmware, driver, application)
.PARAMETER CatalogPath
    Custom path for update catalog Excel file
.PARAMETER VerboseLogPath
    Custom path for verbose log Excel file
.PARAMETER SuppressNotifications
    Suppress all user notifications
.PARAMETER ForceInstallDCU
    Force reinstallation of Dell Command Update
.EXAMPLE
    .\DellUpdateAutomation.ps1
    Run full update process with defaults
.EXAMPLE
    .\DellUpdateAutomation.ps1 -CheckOnly
    Only check for updates
.EXAMPLE
    .\DellUpdateAutomation.ps1 -NoReboot -UpdateType driver
    Install only driver updates without reboot
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$SkipDellCheck,
    
    [Parameter()]
    [switch]$NoReboot,
    
    [Parameter()]
    [switch]$CheckOnly,
    
    [Parameter()]
    [ValidateSet('all', 'bios', 'firmware', 'driver', 'application')]
    [string]$UpdateType = 'all',
    
    [Parameter()]
    [string]$CatalogPath,
    
    [Parameter()]
    [string]$VerboseLogPath,
    
    [Parameter()]
    [switch]$SuppressNotifications,
    
    [Parameter()]
    [switch]$ForceInstallDCU
)

$ErrorActionPreference = 'Stop'
$script:StartTime = Get-Date

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Determine script directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path $scriptRoot "Modules"

# Set default paths if not specified
if (-not $CatalogPath) {
    $reportsDir = Join-Path (Split-Path $scriptRoot -Parent) "reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
    }
    $CatalogPath = Join-Path $reportsDir "DellUpdateCatalog.xlsx"
}

if (-not $VerboseLogPath) {
    $logsDir = Join-Path (Split-Path $scriptRoot -Parent) "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }
    $VerboseLogPath = Join-Path $logsDir "DellUpdateLog.xlsx"
}

# ==============================================================================
# IMPORT MODULES
# ==============================================================================

Write-Host ""
Write-Host "+================================================================+" -ForegroundColor Cyan
Write-Host "|         DELL UPDATE AUTOMATION - ENTERPRISE EDITION            |" -ForegroundColor Cyan
Write-Host "+================================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Mode: $(if ($CheckOnly) { 'Check Only' } elseif ($WhatIf) { 'Dry Run' } else { 'Full Automation' })" -ForegroundColor Gray
Write-Host ""

Write-Host "[1/8] Loading modules..." -ForegroundColor Cyan

try {
    # Import all required modules
    $requiredModules = @(
        'SystemValidator.psm1',
        'ErrorHandler.psm1',
        'ProgressReporter.psm1',
        'ExcelService.psm1',
        'DellCommandService.psm1',
        'UpdateCatalogService.psm1'
    )
    
    foreach ($module in $requiredModules) {
        $modulePath = Join-Path $modulesPath $module
        if (-not (Test-Path $modulePath)) {
            throw "Required module not found: $module"
        }
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Verbose "Loaded: $module"
    }
    
    Write-Host "  (OK) All modules loaded successfully" -ForegroundColor Green
    
} catch {
    Write-Host "  (X) Failed to load modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ==============================================================================
# INITIALIZE ERROR HANDLER AND LOGGING
# ==============================================================================

Write-Host ""
Write-Host "[2/8] Initializing logging..." -ForegroundColor Cyan

try {
    # Initialize error handler
    Initialize-ErrorHandler -LogPath $VerboseLogPath -VerboseLogPath $VerboseLogPath
    
    # Initialize Excel logging
    if (Test-ImportExcelModule -AutoInstall) {
        Initialize-VerboseLog -FilePath $VerboseLogPath
        Write-Host "  (OK) Verbose logging initialized: $VerboseLogPath" -ForegroundColor Green
    }
    
    # Initialize update catalog
    Initialize-UpdateCatalog -FilePath $CatalogPath | Out-Null
    Write-Host "  (OK) Update catalog initialized: $CatalogPath" -ForegroundColor Green
    
    # Log start
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "System" -Message "Dell Update Automation started" -Details "Mode: $(if ($CheckOnly) { 'Check Only' } else { 'Full' })"
    
} catch {
    Write-Host "  (X) Failed to initialize logging: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ==============================================================================
# SYSTEM VALIDATION
# ==============================================================================

Write-Host ""
Write-Host "[3/8] Validating system requirements..." -ForegroundColor Cyan

try {
    $validation = Test-SystemRequirements -SkipDellCheck:$SkipDellCheck
    
    if (-not $validation.IsValid) {
        Write-Host ""
        Write-Host "  System validation failed:" -ForegroundColor Red
        foreach ($error in $validation.Errors) {
            Write-Host "    (X) $error" -ForegroundColor Red
        }
        Write-Host ""
        exit 1
    }

    Write-Host "  (OK) PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Green
    Write-Host "  (OK) Administrator: Yes" -ForegroundColor Green
    Write-Host "  (OK) Dell System: $($validation.IsDell)" -ForegroundColor Green
    Write-Host "  (OK) Windows: $($validation.WindowsVersion.Caption)" -ForegroundColor Green

    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "Validation" -Message "System validated" -Details "Dell: $($validation.IsDell)"

} catch {
    Write-Host "  (X) System validation failed: $($_.Exception.Message)" -ForegroundColor Red
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Error" -Category "Validation" -Message "Validation failed" -Details $_.Exception.Message
    if (-not $SkipDellCheck) {
        exit 1
    }
}
# ==============================================================================
# DELL COMMAND UPDATE CHECK/INSTALL
# ==============================================================================

Write-Host ""
Write-Host "[4/8] Checking Dell Command Update..." -ForegroundColor Cyan

try {
    if ($ForceInstallDCU -or -not (Test-DellCommandUpdateInstalled)) {
        Write-Host "  Dell Command Update not found. Installing..." -ForegroundColor Yellow
        
        $installResult = Invoke-SafeOperation -ScriptBlock {
            Install-DellCommandUpdate
        } -ErrorMessage "Failed to install Dell Command Update"
        
        if ($installResult.Success -and $installResult.Result) {
            $dcuVersion = Get-DellCommandUpdateVersion
            Write-Host "  (OK) Dell Command Update installed: v$dcuVersion" -ForegroundColor Green
            Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Success" -Category "DCU" -Message "DCU installed" -Details "Version: $dcuVersion"
        } else {
            throw "Failed to install Dell Command Update"
        }
    } else {
        $dcuVersion = Get-DellCommandUpdateVersion
        $dcuPath = Get-DellCommandUpdatePath
        Write-Host "  (OK) Dell Command Update found: v$dcuVersion" -ForegroundColor Green
        Write-Host "    Path: $dcuPath" -ForegroundColor Gray
        Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "DCU" -Message "DCU already installed" -Details "Version: $dcuVersion"
    }
    
    # Configure DCU for silent operation
    if ($SuppressNotifications) {
        Set-DellCommandUpdateConfiguration -SuppressNotifications
        Write-Host "  (OK) DCU configured for silent operation" -ForegroundColor Green
    }
    
} catch {
    Write-Host "  (X) DCU setup failed: $($_.Exception.Message)" -ForegroundColor Red
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Error" -Category "DCU" -Message "DCU setup failed" -Details $_.Exception.Message
    exit 1
}

# ==============================================================================
# SCAN FOR UPDATES
# ==============================================================================

Write-Host ""
Write-Host "[5/8] Scanning for available updates..." -ForegroundColor Cyan
Write-Host "Progress: [" -NoNewline -ForegroundColor Gray
Write-Host "================================================>" -NoNewline -ForegroundColor Green
Write-Host "          ] 62%" -ForegroundColor Gray
Write-Host ""

try {
    Write-Host "  Scanning for updates" -NoNewline -ForegroundColor Cyan
    
    # Run scan with inline animation
    $animationChars = @('|', '/', '-', '\')
    $charIndex = 0
    
    # Start a timer
    $scanStart = Get-Date
    
    # Create a runspace for the scan
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    
    # Set up the PowerShell command
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    
    # Add the scan script
    [void]$ps.AddScript({
        param($scriptRoot)
        
        # Import modules
        $modulePath = Join-Path $scriptRoot "modules"
        Import-Module (Join-Path $modulePath "ErrorHandler.psm1") -Force
        Import-Module (Join-Path $modulePath "DellCommandService.psm1") -Force
        Import-Module (Join-Path $modulePath "UpdateCatalogService.psm1") -Force
        
        # Run scan
        return Get-UpdatesFromDcu
        
    }).AddArgument($PSScriptRoot)
    
    # Start the scan
    $handle = $ps.BeginInvoke()
    
    # Animate while waiting
    while (-not $handle.IsCompleted) {
        $elapsed = [math]::Floor(((Get-Date) - $scanStart).TotalSeconds)
        $char = $animationChars[$charIndex % $animationChars.Count]
        Write-Host "`r  Scanning for updates $char ($($elapsed)s)" -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 200
        $charIndex++
    }
    
    # Get results
    $updates = $ps.EndInvoke($handle)
    
    # Cleanup
    $ps.Dispose()
    $runspace.Close()
    $runspace.Dispose()
    
    # Show completion
    $scanDuration = [math]::Floor(((Get-Date) - $scanStart).TotalSeconds)
    Write-Host "`r  Scanning for updates... Done ($($scanDuration)s)          " -ForegroundColor Green
    Write-Host ""
    
    if (-not $updates -or $updates.Count -eq 0) {
        Write-Host "  No updates available" -ForegroundColor Green
        Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "Updates" -Message "No updates found" -Details "System is up to date"
        exit 0
    }
    
    Write-Host ""
    Write-Host "+----------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "|  UPDATES FOUND: $($updates.Count) update(s) available" -ForegroundColor Cyan
    $padding = " " * (64 - 2)
    Write-Host "|$padding|" -ForegroundColor Cyan
    Write-Host "+----------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
    
    # Display each update with box
    $updateNum = 1
    foreach ($update in $updates) {
        Write-Host ""
        Write-Host "  +-- Update $updateNum " -NoNewline -ForegroundColor Cyan
        Write-Host ("-" * 50) -ForegroundColor Cyan
        Write-Host "  |" -ForegroundColor Cyan
        Write-Host "  |  Name       : $($update.Name)" -ForegroundColor White
        Write-Host "  |  Type       : $($update.Type)" -ForegroundColor White
        Write-Host "  |  Severity   : $($update.Severity)" -ForegroundColor $(if ($update.Severity -eq 'Urgent') { 'Red' } elseif ($update.Severity -eq 'Recommended') { 'Yellow' } else { 'White' })
        Write-Host "  |  Category   : $($update.Category)" -ForegroundColor White
        if ($update.RebootRequired) {
            Write-Host "  |  Reboot Req : Yes" -ForegroundColor Yellow
        }
        Write-Host "  |" -ForegroundColor Cyan
        Write-Host "  +" -NoNewline -ForegroundColor Cyan
        Write-Host ("-" * 62) -ForegroundColor Cyan
        $updateNum++
    }
    
    Write-Host ""
    Write-Host "  Synchronizing update catalog..." -ForegroundColor Cyan
    
    # Sync catalog with better error handling
    try {
        $syncSuccess = Sync-CatalogWithDcu -CatalogPath $CatalogPath -Updates $updates
        if (-not $syncSuccess) {
            Write-Host "  ! Catalog sync skipped (file may be locked)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ! Catalog sync error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "  (OK) Found $($updates.Count) available update(s)" -ForegroundColor Green
    
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "Updates" -Message "Scan completed" -Details "Updates found: $($updates.Count)"
    
} catch {
    Write-Host " Failed" -ForegroundColor Red
    Write-Host "  Scan failed: $($_.Exception.Message)" -ForegroundColor Red
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Error" -Category "Updates" -Message "Scan failed" -Details $_.Exception.Message
    exit 1
}

# ==============================================================================
# CHECK ONLY MODE EXIT
# ==============================================================================

if ($CheckOnly) {
    Write-Host ""
    Write-Host "+================================================================+" -ForegroundColor Yellow
    Write-Host "|                    CHECK ONLY MODE - EXITING                   |" -ForegroundColor Yellow
    Write-Host "+================================================================+" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Update catalog has been updated. Run without -CheckOnly to install." -ForegroundColor White
    Write-Host ""
    
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "System" -Message "Check only mode completed" -Details "Updates available: $($updates.Count)"
    
    exit 0
}

# Stop here if WhatIf
if ($WhatIfPreference) {
    Write-Host ""
    Write-Host "+================================================================+" -ForegroundColor Cyan
    Write-Host "|                      WHATIF MODE - EXITING                     |" -ForegroundColor Cyan
    Write-Host "+================================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "No changes were made to the system." -ForegroundColor Green
    Write-Host "Remove -WhatIf to perform actual installation." -ForegroundColor White
    Write-Host ""
    
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "System" -Message "WhatIf mode completed" -Details "Updates found: $($updates.Count)"
    
    exit 0
}

# ==============================================================================
# INSTALL UPDATES
# ==============================================================================

Write-Host ""
Write-Host "[6/8] Processing updates..." -ForegroundColor Cyan
Write-Host "Progress: [" -NoNewline -ForegroundColor Gray
Write-Host "==========================================================>" -NoNewline -ForegroundColor Green
Write-Host "  ] 75%" -ForegroundColor Gray
Write-Host ""

try {
    if ($WhatIfPreference) {
        Write-Host "  [WHATIF] Installation skipped - dry run mode" -ForegroundColor Yellow
        Write-Host "  [WHATIF] Would install $($updates.Count) update(s)" -ForegroundColor Yellow
        Write-Host "  [WHATIF] Reboot: $(if ($NoReboot) { 'Disabled' } else { 'Enabled' })" -ForegroundColor Yellow
        Write-Host "  [WHATIF] Update Type: $UpdateType" -ForegroundColor Yellow
        Write-Host ""
        
        $installResults = @{
            Success = $true
            UpdatesInstalled = $updates.Count
            Failed = @()
            RebootRequired = $false
        }
        
        Write-Host "  (OK) Dry run completed - no changes made" -ForegroundColor Green
        
        Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "Installation" -Message "WhatIf mode completed" -Details "Would install: $($updates.Count)"
        
    } else {
        # Start timer for installation
        $installStart = Get-Date
        
        Write-Host "  Installing $($updates.Count) update(s)..." -ForegroundColor Cyan
        Write-Host "  Elapsed time: 0m 0s" -ForegroundColor Gray
        Write-Host ""
        
        # Create a job for installation with progress updates
        $installJob = Start-Job -ScriptBlock {
            param($updates, $updateType, $noReboot)
            
            # Installation logic here
            $result = Install-DellUpdates -Updates $updates -UpdateType $updateType -NoReboot:$noReboot
            return $result
            
        } -ArgumentList $updates, $UpdateType, $NoReboot
        
        # Monitor installation with elapsed time
        $lastUpdate = Get-Date
        while ($installJob.State -eq 'Running') {
            $elapsed = (Get-Date) - $installStart
            $elapsedStr = "$($elapsed.Minutes)m $($elapsed.Seconds)s"
            
            # Update every 5 seconds
            if (((Get-Date) - $lastUpdate).TotalSeconds -ge 5) {
                Write-Host "`r  Elapsed time: $elapsedStr" -NoNewline -ForegroundColor Gray
                $lastUpdate = Get-Date
            }
            
            Start-Sleep -Milliseconds 500
        }
        
        # Get results
        $installResults = Receive-Job -Job $installJob
        Remove-Job -Job $installJob
        
        # Final elapsed time
        $installDuration = (Get-Date) - $installStart
        Write-Host "`r  Elapsed time: $($installDuration.Minutes)m $($installDuration.Seconds)s" -ForegroundColor Cyan
        Write-Host ""
        
        if ($installResults.Success) {
            Write-Host "  (OK) Updates processed: $($installResults.UpdatesInstalled)" -ForegroundColor Green
            Write-Host "  (OK) Catalog updated" -ForegroundColor Green
            
            if ($installResults.RebootRequired) {
                Write-Host "  ! Reboot required" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  (X) Some updates failed" -ForegroundColor Yellow
            Write-Host "  (OK) Completed: $($installResults.UpdatesInstalled)" -ForegroundColor Green
            Write-Host "  (X) Failed: $($installResults.Failed.Count)" -ForegroundColor Red
        }
    }
    
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Success" -Category "Installation" -Message "Update processing completed" -Details "Mode: $(if ($WhatIfPreference) { 'WhatIf' } else { 'Real' }), Count: $($updates.Count), Duration: $($installDuration.TotalSeconds)s"
    
} catch {
    Write-Host "  (X) Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Error" -Category "Installation" -Message "Installation failed" -Details $_.Exception.Message
    exit 1
}

# ==============================================================================
# POST-INSTALL SCAN
# ==============================================================================

Write-Host ""
Write-Host "[7/8] Checking for remaining updates..." -ForegroundColor Cyan

try {
    $postInstallUpdates = Get-UpdatesFromDcu
    
    if ($postInstallUpdates.Count -eq 0) {
        Write-Host "  (OK) No additional updates found" -ForegroundColor Green
    } else {
        Write-Host "  ! $($postInstallUpdates.Count) update(s) still available" -ForegroundColor Yellow
        Write-Host "    (May require reboot before installing)" -ForegroundColor Gray
        
        # Add to catalog
        foreach ($update in $postInstallUpdates) {
            Add-UpdateToCatalog -FilePath $CatalogPath -UpdateInfo $update
        }
    }
    
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "PostInstall" -Message "Post-install scan completed" -Details "Remaining updates: $($postInstallUpdates.Count)"
    
} catch {
    Write-Host "  ! Post-install scan failed (non-critical): $($_.Exception.Message)" -ForegroundColor Yellow
}

# ==============================================================================
# GENERATE SUMMARY REPORT
# ==============================================================================

Write-Host ""
Write-Host "[8/8] Generating reports..." -ForegroundColor Cyan

try {
    $stats = Get-UpdateStatistics -CatalogPath $CatalogPath
    $reportsDir = Split-Path $CatalogPath -Parent
    
    # Export reports
    Export-UpdateReport -CatalogPath $CatalogPath -OutputPath $reportsDir -Format 'All'
    
    Write-Host "  (OK) Reports generated in: $reportsDir" -ForegroundColor Green
    
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Info" -Category "Report" -Message "Reports generated" -Details "Location: $reportsDir"
    
} catch {
    Write-Host "  ! Report generation failed (non-critical): $($_.Exception.Message)" -ForegroundColor Yellow
}

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

$endTime = Get-Date
$duration = $endTime - $script:StartTime

Write-Host ""
Write-Host "+================================================================+" -ForegroundColor Cyan
Write-Host "|                      EXECUTION SUMMARY                         |" -ForegroundColor Cyan
Write-Host "+================================================================+" -ForegroundColor Cyan
Write-Host ""

# Status with color coding
Write-Host "  Status          : " -NoNewline -ForegroundColor White
if ($installResults.UpdatesInstalled -gt 0) {
    if ($installResults.RebootRequired) {
        Write-Host "COMPLETED - REBOOT REQUIRED" -ForegroundColor Yellow
    } else {
        Write-Host "SUCCESS" -ForegroundColor Green
    }
} elseif ($updates.Count -eq 0) {
    Write-Host "NO UPDATES AVAILABLE" -ForegroundColor Cyan
} else {
    Write-Host "NO UPDATES INSTALLED" -ForegroundColor Yellow
}

# Duration with formatting
$durationMinutes = $duration.Minutes
$durationSeconds = $duration.Seconds
Write-Host "  Duration        : " -NoNewline -ForegroundColor White
Write-Host "$($durationMinutes)m $($durationSeconds)s" -ForegroundColor Cyan

# Updates found with color
Write-Host "  Updates Found   : " -NoNewline -ForegroundColor White
if ($updates.Count -gt 0) {
    Write-Host "$($updates.Count)" -ForegroundColor Yellow
} else {
    Write-Host "0" -ForegroundColor Green
}

# Updates installed with color
Write-Host "  Updates Installed: " -NoNewline -ForegroundColor White
if ($installResults.UpdatesInstalled -gt 0) {
    Write-Host "$($installResults.UpdatesInstalled)" -ForegroundColor Green
} else {
    Write-Host "0" -ForegroundColor Gray
}

# Reboot status with icon
Write-Host "  Reboot Required : " -NoNewline -ForegroundColor White
if ($installResults.RebootRequired) {
    Write-Host "Yes " -NoNewline -ForegroundColor Red
    Write-Host "[!]" -ForegroundColor Yellow -BackgroundColor DarkRed
} else {
    Write-Host "No" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Catalog         : " -NoNewline -ForegroundColor Gray
Write-Host "$CatalogPath" -ForegroundColor DarkGray
Write-Host "  Verbose Log     : " -NoNewline -ForegroundColor Gray
Write-Host "$VerboseLogPath" -ForegroundColor DarkGray

Write-Host ""

if ($installResults.RebootRequired -and -not $NoReboot) {
    Write-Host ""
    Write-Host "+================================================================+" -ForegroundColor Yellow
    Write-Host "|                REBOOT WILL OCCUR IN 60 SECONDS                 |" -ForegroundColor Yellow
    Write-Host "+================================================================+" -ForegroundColor Yellow
    Write-Host ""
    
    Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Warning" -Category "Reboot" -Message "System reboot initiated" -Details "Countdown: 60 seconds"
    
    Start-CountdownTimer -Seconds 60 -Message "System will reboot"
    
    shutdown.exe /r /t 5 /c "Dell updates installed. System restart required." /d p:2:18
} else {
    Write-Host "Dell Update Automation completed successfully!" -ForegroundColor Green
    Write-Host ""
}

Add-VerboseLogEntry -FilePath $VerboseLogPath -Level "Success" -Category "System" -Message "Dell Update Automation completed" -Details "Duration: $($duration.TotalSeconds)s"

exit 0
