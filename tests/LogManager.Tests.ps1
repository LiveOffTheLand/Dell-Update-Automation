# LogManager.Tests.ps1

# Import the LogManager module
Import-Module ..\src\modules\LogManager.psm1

# Define the log file path for testing
$logFilePath = "..\logs\test_log.txt"

# Clear the log file before running tests
if (Test-Path $logFilePath) {
    Remove-Item $logFilePath
}

# Test logging a message
Describe "LogManager" {
    It "Should log a message successfully" {
        Log-Message -Message "Test log message" -LogFilePath $logFilePath
        $logContents = Get-Content $logFilePath
        $logContents | Should -Contain "Test log message"
    }

    It "Should log an error message successfully" {
        Log-Error -Message "Test error message" -LogFilePath $logFilePath
        $logContents = Get-Content $logFilePath
        $logContents | Should -Contain "ERROR: Test error message"
    }

    It "Should log a status update successfully" {
        Log-Status -Message "Test status update" -LogFilePath $logFilePath
        $logContents = Get-Content $logFilePath
        $logContents | Should -Contain "STATUS: Test status update"
    }
}

# Clean up the log file after tests
if (Test-Path $logFilePath) {
    Remove-Item $logFilePath
}