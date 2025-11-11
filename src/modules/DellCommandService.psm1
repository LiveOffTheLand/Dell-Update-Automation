<#
.SYNOPSIS
    Dell Command Update service module
.DESCRIPTION
    Manages Dell Command Update CLI installation, configuration, and operations
#>

# Define centralized log directory
$script:DcuLogPath = "C:\DellUpdatesCLI"

function Initialize-DcuLogDirectory {
    <#
    .SYNOPSIS
        Ensures the DCU log directory exists
    #>
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path $script:DcuLogPath)) {
        try {
            New-Item -Path $script:DcuLogPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created DCU log directory: $script:DcuLogPath"
        } catch {
            Write-Warning "Failed to create DCU log directory, falling back to TEMP"
            $script:DcuLogPath = Join-Path $env:TEMP "DellUpdatesCLI"
            if (-not (Test-Path $script:DcuLogPath)) {
                New-Item -Path $script:DcuLogPath -ItemType Directory -Force | Out-Null
            }
        }
    }
}

function Test-DellCommandUpdateInstalled {
    <#
    .SYNOPSIS
        Checks if Dell Command Update CLI is installed
    .OUTPUTS
        Boolean - True if installed
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $dcuPaths = @(
        "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe",
        "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
    )
    
    foreach ($path in $dcuPaths) {
        if (Test-Path $path) {
            Write-Verbose "Dell Command Update found at: $path"
            return $true
        }
    }
    
    Write-Verbose "Dell Command Update CLI not found"
    return $false
}

function Get-DellCommandUpdatePath {
    <#
    .SYNOPSIS
        Gets the path to dcu-cli.exe
    .OUTPUTS
        String - Path to dcu-cli.exe or $null if not found
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    $dcuPaths = @(
        "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe",
        "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
    )
    
    foreach ($path in $dcuPaths) {
        if (Test-Path $path) {
            Write-Verbose "DCU CLI path: $path"
            return $path
        }
    }
    
    return $null
}

function Get-DellCommandUpdateVersion {
    <#
    .SYNOPSIS
        Gets the installed version of Dell Command Update
    .OUTPUTS
        String - Version number or $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    $dcuPath = Get-DellCommandUpdatePath
    if (-not $dcuPath) {
        return $null
    }
    
    try {
        Initialize-DcuLogDirectory
        
        $versionFile = Join-Path $script:DcuLogPath "dcu_version.txt"
        $process = Start-Process -FilePath $dcuPath -ArgumentList "/version" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $versionFile -RedirectStandardError "$($versionFile).err"
        
        if (Test-Path $versionFile) {
            $versionOutput = Get-Content $versionFile -Raw
            Remove-Item $versionFile -Force -ErrorAction SilentlyContinue
            Remove-Item "$versionFile.err" -Force -ErrorAction SilentlyContinue
            
            if ($versionOutput -match "(\d+\.\d+\.\d+)") {
                return $matches[1]
            }
        }
        
        return "Unknown"
    } catch {
        Write-Warning "Failed to get DCU version: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-DellUpdateScan {
    <#
    .SYNOPSIS
        Scans for available Dell updates using DCU CLI
    .OUTPUTS
        Array of update objects
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    $dcuPath = Get-DellCommandUpdatePath
    if (-not $dcuPath) {
        throw "Dell Command Update CLI not found"
    }
    
    try {
        Initialize-DcuLogDirectory
        
        Write-Verbose "Executing DCU scan..."
        Write-Verbose "DCU Path: $dcuPath"
        
        # Create scan log path
        $scanLogPath = Join-Path $script:DcuLogPath "dcu_scan_$(Get-Date -Format 'yyyyMMddHHmmss').log"
        
        # Step 1: Run the scan with output redirect
        # DCU CLI proper syntax: dcu-cli.exe /scan
        $scanProcess = Start-Process -FilePath $dcuPath -ArgumentList "/scan" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $scanLogPath -RedirectStandardError "$scanLogPath.err"
        
        $scanExitCode = $scanProcess.ExitCode
        Write-Verbose "DCU scan exit code: $scanExitCode"
        
        # Read the scan output
        $scanOutput = ""
        if (Test-Path $scanLogPath) {
            $scanOutput = Get-Content $scanLogPath -Raw
            Write-Verbose "Scan output length: $($scanOutput.Length)"
        }
        
        # DCU Exit Codes for /scan:
        # 0 = Success, no updates available
        # 1 = Success, updates available  
        # 2 = Reboot required before scan
        # 5 = Invalid system configuration
        # 500 = Another DCU process running
        
        if ($scanExitCode -eq 2) {
            Write-Warning "A reboot is required before scanning for updates"
            return @()
        }
        
        if ($scanExitCode -eq 500) {
            Write-Warning "Another Dell Command Update process is running"
            return @()
        }
        
        # Parse the scan output directly (DCU outputs update info to stdout)
        if ($scanOutput) {
            $updates = Parse-DcuScanOutput -Output $scanOutput
            
            if ($updates.Count -gt 0) {
                Write-Verbose "Found $($updates.Count) update(s) from scan output"
                return $updates
            }
        }
        
        # If no updates found in scan output
        if ($scanExitCode -eq 0) {
            Write-Verbose "No updates available (exit code 0)"
            return @()
        }
        
        # If we get here with exit code 1 but no parsed updates, something went wrong
        if ($scanExitCode -eq 1) {
            Write-Warning "Scan indicated updates available but none were parsed"
        }
        
        return @()
        
    } catch {
        Write-Error "Failed to scan for updates: $($_.Exception.Message)"
        return @()
    } finally {
        # Clean up old log files (keep last 10)
        try {
            $oldLogs = Get-ChildItem -Path $script:DcuLogPath -Filter "dcu_scan_*.log*" | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -Skip 10
            
            $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {
            # Ignore cleanup errors
        }
    }
}

function ConvertTo-ReadableCategory {
    <#
    .SYNOPSIS
        Converts Dell category codes to readable names
    .PARAMETER CategoryCode
        Dell category code (AP, BI, DR, FW, etc.)
    #>
    [CmdletBinding()]
    param(
        [string]$CategoryCode
    )
    
    $categoryMap = @{
        'AP' = 'Application'
        'BI' = 'BIOS'
        'DR' = 'Driver'
        'FW' = 'Firmware'
        'UT' = 'Utility'
        'OS' = 'Operating System'
        'NW' = 'Network'
        'AU' = 'Audio'
        'VI' = 'Video'
        'CH' = 'Chipset'
    }
    
    if ($categoryMap.ContainsKey($CategoryCode)) {
        return $categoryMap[$CategoryCode]
    }
    
    return $CategoryCode
}

function Parse-DcuScanOutput {
    <#
    .SYNOPSIS
        Parses DCU scan output text
    .PARAMETER Output
        Raw text output from DCU scan
    .OUTPUTS
        Array of update objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Output
    )
    
    $updates = @()
    $lines = $Output -split "`r?`n"
    
    Write-Verbose "Parsing DCU output ($($lines.Count) lines)..."
    
    # Parse the count line
    $updateCount = 0
    foreach ($line in $lines) {
        # Look for: "Number of applicable updates for the current system configuration: X"
        if ($line -match "Number of.*?:\s*(\d+)") {
            $updateCount = [int]$matches[1]
            Write-Verbose "Update count from output: $updateCount"
            break
        }
    }
    
    if ($updateCount -eq 0) {
        Write-Verbose "No updates indicated in output"
        return @()
    }
    
    # Parse update details
    # Format: "ID: Name - Type -- Severity -- Category"
    # Example: "3CDV4: Dell Precision 3590/3591 and Latitude 5550 System BIOS - BIOS -- Urgent -- BI"
    
    foreach ($line in $lines) {
        # Match update line pattern
        if ($line -match "^([A-Z0-9]+):\s*(.+?)\s*-\s*([^-]+?)\s*--\s*([^-]+?)\s*--\s*(.+)$") {
            $updateId = $matches[1].Trim()
            $name = $matches[2].Trim()
            $type = $matches[3].Trim()
            $severity = $matches[4].Trim()
            $category = ConvertTo-ReadableCategory -CategoryCode $matches[5].Trim()
            
            $update = @{
                UpdateID = $updateId
                Name = $name
                Version = ""  # Not provided in scan output
                Type = $type
                Severity = $severity
                Category = $category
                ReleaseDate = ""
                Status = "Available"
                InstallDate = ""
                RebootRequired = if ($type -match "BIOS|Firmware") { "Yes" } else { "Unknown" }
                Notes = ""
            }
            
            Write-Verbose "Parsed update: $name"
            $updates += $update
        }
    }
    
    if ($updates.Count -eq 0 -and $updateCount -gt 0) {
        # Fallback: create generic update entries if parsing failed but count was found
        Write-Verbose "Creating generic update entries based on count"
        for ($i = 1; $i -le $updateCount; $i++) {
            $updates += @{
                UpdateID = [guid]::NewGuid().ToString()
                Name = "Dell Update $i"
                Version = ""
                Type = "Unknown"
                Severity = "Unknown"
                Category = "Unknown"
                ReleaseDate = ""
                Status = "Available"
                InstallDate = ""
                RebootRequired = "Unknown"
                Notes = "Parse scan output for details"
            }
        }
    }
    
    return $updates
}

function Install-DellUpdates {
    <#
    .SYNOPSIS
        Installs Dell updates using DCU CLI
    .PARAMETER Reboot
        Allow automatic reboot if required
    .PARAMETER UpdateType
        Type of updates to install
    .OUTPUTS
        Hashtable with installation results
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [switch]$Reboot,
        [string]$UpdateType = 'all'
    )
    
    $dcuPath = Get-DellCommandUpdatePath
    if (-not $dcuPath) {
        throw "Dell Command Update CLI not found"
    }
    
    try {
        Initialize-DcuLogDirectory
        
        Write-Verbose "Installing Dell updates..."
        
        $results = @{
            Success = $false
            ExitCode = -1
            RebootRequired = $false
            UpdatesInstalled = 0
            Errors = @()
        }
        
        if ($PSCmdlet.ShouldProcess("Dell Updates", "Install")) {
            # Build arguments for /applyUpdates
            $arguments = "/applyUpdates"
            
            if ($Reboot) {
                $arguments += " -reboot=enable"
            } else {
                $arguments += " -reboot=disable"
            }
            
            # Add update type filter if not 'all'
            if ($UpdateType -ne 'all') {
                $arguments += " -updateType=$UpdateType"
            }
            
            Write-Verbose "Executing: `"$dcuPath`" $arguments"
            
            $installLogPath = Join-Path $script:DcuLogPath "dcu_install_$(Get-Date -Format 'yyyyMMddHHmmss').log"
            $process = Start-Process -FilePath $dcuPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $installLogPath -RedirectStandardError "$installLogPath.err"
            
            $results.ExitCode = $process.ExitCode
            
            Write-Verbose "DCU install exit code: $($results.ExitCode)"
            
            # Parse exit codes
            switch ($results.ExitCode) {
                0 { 
                    $results.Success = $true
                    $results.UpdatesInstalled = 1
                    Write-Verbose "Updates installed successfully"
                }
                1 {
                    $results.Success = $true
                    $results.RebootRequired = $true
                    $results.UpdatesInstalled = 1
                    Write-Verbose "Updates installed, reboot required"
                }
                2 {
                    $results.Errors += "Reboot from previous update is pending"
                }
                3 {
                    $results.Errors += "Invalid command line parameters"
                }
                4 {
                    $results.Success = $true
                    $results.UpdatesInstalled = 0
                    $results.Errors += "No updates to install"
                }
                5 {
                    $results.Errors += "Updates available but not applicable to this system"
                }
                500 {
                    $results.Errors += "Another Dell Command Update process is running"
                }
                default {
                    $results.Errors += "Unknown exit code: $($results.ExitCode)"
                }
            }
        }
        
        return $results
        
    } catch {
        Write-Error "Failed to install updates: $($_.Exception.Message)"
        return @{
            Success = $false
            ExitCode = -1
            RebootRequired = $false
            UpdatesInstalled = 0
            Errors = @($_.Exception.Message)
        }
    }
}

function Install-DellCommandUpdate {
    <#
    .SYNOPSIS
        Downloads and installs Dell Command Update
    .OUTPUTS
        Boolean - True if installation successful
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param()
    
    try {
        Write-Verbose "Starting Dell Command Update installation..."
        
        # DCU download URL (latest version)
        $dcuUrl = "https://dl.dell.com/FOLDER11738576M/1/Dell-Command-Update-Windows-Universal-Application_5N4X7_WIN_5.4.0_A00.EXE"
        $installerPath = Join-Path $env:TEMP "DCU_Setup.exe"
        
        if ($PSCmdlet.ShouldProcess("Dell Command Update", "Download and Install")) {
            Write-Host "  Downloading Dell Command Update..." -ForegroundColor Cyan
            
            try {
                Invoke-WebRequest -Uri $dcuUrl -OutFile $installerPath -UseBasicParsing
            } catch {
                Write-Warning "Primary download failed, trying alternate location..."
                $dcuUrl = "https://dl.dell.com/FOLDER09235009M/1/Dell-Command-Update-Windows-Universal-Application_601KT_WIN_5.3.0_A00.EXE"
                Invoke-WebRequest -Uri $dcuUrl -OutFile $installerPath -UseBasicParsing
            }
            
            if (-not (Test-Path $installerPath)) {
                throw "Failed to download DCU installer"
            }
            
            Write-Verbose "Installer downloaded to: $installerPath"
            Write-Host "  Installing Dell Command Update..." -ForegroundColor Cyan
            
            $installArgs = "/s"
            $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-Verbose "DCU installation completed successfully"
                
                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                
                Start-Sleep -Seconds 10
                
                $maxRetries = 5
                $retryCount = 0
                while ($retryCount -lt $maxRetries) {
                    if (Test-DellCommandUpdateInstalled) {
                        return $true
                    }
                    Start-Sleep -Seconds 5
                    $retryCount++
                }
                
                Write-Warning "DCU appears to be installed but CLI not found after $maxRetries attempts"
                return $false
                
            } else {
                throw "DCU installation failed with exit code: $($process.ExitCode)"
            }
        }
        
        return $false
        
    } catch {
        Write-Error "Failed to install Dell Command Update: $($_.Exception.Message)"
        return $false
    }
}

function Set-DellCommandUpdateConfiguration {
    <#
    .SYNOPSIS
        Configures Dell Command Update settings
    .PARAMETER SuppressNotifications
        Suppress user notifications
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$SuppressNotifications
    )
    
    $dcuPath = Get-DellCommandUpdatePath
    if (-not $dcuPath) {
        throw "Dell Command Update CLI not found"
    }
    
    try {
        if ($PSCmdlet.ShouldProcess("Dell Command Update", "Configure Settings")) {
            Write-Verbose "Configuring Dell Command Update settings..."
            
            if ($SuppressNotifications) {
                $arguments = "/configure -userConsent=disable -silent"
                $process = Start-Process -FilePath $dcuPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                Write-Verbose "Configuration exit code: $($process.ExitCode)"
            }
            
            Write-Verbose "DCU configuration completed"
        }
        
    } catch {
        Write-Warning "Failed to configure DCU: $($_.Exception.Message)"
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-DcuLogDirectory',
    'Test-DellCommandUpdateInstalled',
    'Get-DellCommandUpdatePath',
    'Get-DellCommandUpdateVersion',
    'Invoke-DellUpdateScan',
    'ConvertTo-ReadableCategory',
    'Parse-DcuScanOutput',
    'Install-DellUpdates',
    'Install-DellCommandUpdate',
    'Set-DellCommandUpdateConfiguration'
)