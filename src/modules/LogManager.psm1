function Write-Log {
    param (
        [string]$Message,
        [string]$LogFilePath,
        [string]$LogLevel = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp [$LogLevel] $Message"
    Add-Content -Path $LogFilePath -Value $LogEntry
}

function Log-Error {
    param (
        [string]$ErrorMessage,
        [string]$LogFilePath
    )

    Write-Log -Message $ErrorMessage -LogFilePath $LogFilePath -LogLevel "ERROR"
}

function Log-Info {
    param (
        [string]$InfoMessage,
        [string]$LogFilePath
    )

    Write-Log -Message $InfoMessage -LogFilePath $LogFilePath -LogLevel "INFO"
}

function Log-Status {
    param (
        [string]$StatusMessage,
        [string]$LogFilePath
    )

    Write-Log -Message $StatusMessage -LogFilePath $LogFilePath -LogLevel "STATUS"
}

function Initialize-Log {
    param (
        [string]$LogFilePath
    )

    if (-Not (Test-Path $LogFilePath)) {
        New-Item -Path $LogFilePath -ItemType File -Force | Out-Null
        Log-Info -InfoMessage "Log file created." -LogFilePath $LogFilePath
    }
}

function Clear-Log {
    param (
        [string]$LogFilePath
    )

    if (Test-Path $LogFilePath) {
        Clear-Content -Path $LogFilePath
        Log-Info -InfoMessage "Log file cleared." -LogFilePath $LogFilePath
    }
}