<#
.SYNOPSIS
    Error handling and logging module
.DESCRIPTION
    Provides comprehensive error handling, logging, and recovery mechanisms
#>

$script:LogFilePath = $null
$script:VerboseLogPath = $null

function Initialize-ErrorHandler {
    <#
    .SYNOPSIS
        Initializes the error handler with log file paths
    .PARAMETER LogPath
        Path to the main log file
    .PARAMETER VerboseLogPath
        Path to the verbose Excel log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        
        [string]$VerboseLogPath
    )
    
    $script:LogFilePath = $LogPath
    $script:VerboseLogPath = $VerboseLogPath
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    Write-Verbose "Error handler initialized. Log: $LogPath"
}

function Write-ErrorLog {
    <#
    .SYNOPSIS
        Writes an error to the log file
    .PARAMETER Message
        Error message
    .PARAMETER Exception
        Exception object
    .PARAMETER Severity
        Error severity (Info, Warning, Error, Critical)
    .PARAMETER Category
        Error category
    .PARAMETER LogPath
        Override default log path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [System.Management.Automation.ErrorRecord]$Exception,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Critical')]
        [string]$Severity = 'Error',
        
        [string]$Category = 'General',
        
        [string]$LogPath
    )
    
    $targetLogPath = if ($LogPath) { $LogPath } else { $script:LogFilePath }
    
    if (-not $targetLogPath) {
        Write-Warning "Error handler not initialized. Call Initialize-ErrorHandler first."
        return
    }
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        $logEntry = "[$timestamp] [$Severity] [$Category] $Message"
        
        if ($Exception) {
            $logEntry += "`n  Exception: $($Exception.Exception.Message)"
            $logEntry += "`n  Script: $($Exception.InvocationInfo.ScriptName)"
            $logEntry += "`n  Line: $($Exception.InvocationInfo.ScriptLineNumber)"
            $logEntry += "`n  Stack Trace: $($Exception.ScriptStackTrace)"
        }
        
        # Write to file
        Add-Content -Path $targetLogPath -Value $logEntry -ErrorAction SilentlyContinue
        
        # Also write to verbose log if available
        if ($script:VerboseLogPath -and (Get-Module -Name ExcelService)) {
            Add-VerboseLogEntry -FilePath $script:VerboseLogPath -Level $Severity -Category $Category -Message $Message -Details $(if($Exception){$Exception.Exception.Message}else{""})
        }
        
    } catch {
        Write-Warning "Failed to write to log: $($_.Exception.Message)"
    }
}

function Invoke-SafeOperation {
    <#
    .SYNOPSIS
        Executes a script block with error handling
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [string]$ErrorMessage = "Operation failed",
        
        [Parameter()]
        [switch]$SuppressErrors
    )
    
    try {
        $result = & $ScriptBlock
        
        return @{
            Success = $true
            Result = $result
            Error = $null
        }
        
    } catch {
        $errorDetails = @{
            Success = $false
            Result = $null
            Error = $_
        }
        
        if (-not $SuppressErrors) {
            Write-Verbose "$ErrorMessage : $($_.Exception.Message)"
        }
        
        return $errorDetails
    }
}

function Test-CriticalError {
    <#
    .SYNOPSIS
        Determines if an error is critical and should halt execution
    .PARAMETER Exception
        Exception to evaluate
    .OUTPUTS
        Boolean - True if critical
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$Exception
    )
    
    # Define critical error patterns
    $criticalPatterns = @(
        'Access.*denied',
        'Administrator.*required',
        'Insufficient.*privileges',
        'Not.*Dell.*system',
        'PowerShell.*version',
        'Module.*not.*found'
    )
    
    $errorMessage = $Exception.Exception.Message
    
    foreach ($pattern in $criticalPatterns) {
        if ($errorMessage -match $pattern) {
            Write-Verbose "Critical error detected: $pattern"
            return $true
        }
    }
    
    return $false
}

function Stop-WithError {
    <#
    .SYNOPSIS
        Stops execution with a formatted error message
    .PARAMETER Message
        Error message
    .PARAMETER Exception
        Exception object
    .PARAMETER ExitCode
        Exit code to return
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [System.Management.Automation.ErrorRecord]$Exception,
        
        [int]$ExitCode = 1
    )
    
    Write-Host ""
    Write-Host "" -ForegroundColor Red
    Write-Host "                       CRITICAL ERROR                           " -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Red
    
    if ($Exception) {
        Write-Host ""
        Write-Host "  Exception Details:" -ForegroundColor Yellow
        Write-Host "    $($Exception.Exception.Message)" -ForegroundColor White
        Write-Host ""
        Write-Host "  Location:" -ForegroundColor Yellow
        Write-Host "    Script: $($Exception.InvocationInfo.ScriptName)" -ForegroundColor White
        Write-Host "    Line: $($Exception.InvocationInfo.ScriptLineNumber)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "  Execution halted. Please resolve the issue and try again." -ForegroundColor Yellow
    Write-Host ""
    
    Write-ErrorLog -Message $Message -Exception $Exception -Severity 'Critical'
    
    exit $ExitCode
}

function Get-ErrorSummary {
    <#
    .SYNOPSIS
        Gets a summary of errors from the log file
    .PARAMETER LogPath
        Path to log file
    .PARAMETER LastHours
        Only include errors from the last N hours
    .OUTPUTS
        Array of error entries
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        
        [int]$LastHours = 24
    )
    
    $targetLogPath = if ($LogPath) { $LogPath } else { $script:LogFilePath }
    
    if (-not (Test-Path $targetLogPath)) {
        return @()
    }
    
    try {
        $logContent = Get-Content $targetLogPath
        $cutoffTime = (Get-Date).AddHours(-$LastHours)
        
        $errors = $logContent | Where-Object {
            $_ -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]' -and
            $_ -match '\[Error\]|\[Critical\]'
        } | ForEach-Object {
            if ($_ -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
                $timestamp = [DateTime]::ParseExact($matches[1], "yyyy-MM-dd HH:mm:ss", $null)
                if ($timestamp -gt $cutoffTime) {
                    $_
                }
            }
        }
        
        return $errors
        
    } catch {
        Write-Warning "Failed to read error log: $($_.Exception.Message)"
        return @()
    }
}

function Clear-OldLogs {
    <#
    .SYNOPSIS
        Clears log files older than specified days
    .PARAMETER LogDirectory
        Directory containing log files
    .PARAMETER DaysToKeep
        Number of days of logs to keep
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,
        
        [int]$DaysToKeep = 30
    )
    
    try {
        if (-not (Test-Path $LogDirectory)) {
            Write-Verbose "Log directory does not exist: $LogDirectory"
            return
        }
        
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        
        $oldLogs = Get-ChildItem -Path $LogDirectory -Filter "*.log" | 
            Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        if ($oldLogs) {
            foreach ($log in $oldLogs) {
                if ($PSCmdlet.ShouldProcess($log.FullName, "Delete old log file")) {
                    Remove-Item $log.FullName -Force
                    Write-Verbose "Deleted old log: $($log.Name)"
                }
            }
            
            Write-Host "  (OK) Cleaned up $($oldLogs.Count) old log file(s)" -ForegroundColor Green
        }
        
    } catch {
        Write-Warning "Failed to clear old logs: $($_.Exception.Message)"
    }
}

function Show-ConfirmationPrompt {
    <#
    .SYNOPSIS
        Shows a confirmation prompt to the user
    .PARAMETER Message
        Message to display
    .PARAMETER DefaultYes
        If true, default answer is Yes
    .OUTPUTS
        Boolean - True if user confirmed
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [switch]$DefaultYes
    )
    
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Yellow
    
    $prompt = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    $response = Read-Host "  Continue? $prompt"
    
    if ($DefaultYes) {
        return ($response -eq '' -or $response -match '^[Yy]')
    } else {
        return ($response -match '^[Yy]')
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-ErrorHandler',
    'Write-ErrorLog',
    'Invoke-SafeOperation',
    'Test-CriticalError',
    'Stop-WithError',
    'Get-ErrorSummary',
    'Clear-OldLogs',
    'Show-ConfirmationPrompt'
)