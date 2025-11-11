# Run-UpdateCheck.ps1

# Import necessary modules
Import-Module ..\modules\UpdateManager.psm1
Import-Module ..\modules\LogManager.psm1
Import-Module ..\modules\ConfigManager.psm1
Import-Module ..\modules\CompatibilityChecker.psm1

# Define log file path
$logFilePath = Get-ConfigValue -Key "LogFilePath"

# Start logging
Start-Log -Message "Update check process started."

# Check system compatibility
if (-not (Check-Compatibility)) {
    $errorMessage = "System is not compatible with Windows 10 or Windows 11."
    Start-Log -Message $errorMessage -LogLevel "Error"
    exit 1
}

# Trigger update check
$updateCheckResult = Check-ForUpdates

# Log the results
if ($updateCheckResult) {
    Start-Log -Message "Updates are available."
} else {
    Start-Log -Message "No updates available."
}

# End logging
Start-Log -Message "Update check process completed."