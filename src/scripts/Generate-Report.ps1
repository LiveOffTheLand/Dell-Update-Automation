# Generate-Report.ps1

# This script generates a report of the update activities, including successes and failures, and saves it to the reports directory.

# Import necessary modules
Import-Module ../modules/LogManager.psm1
Import-Module ../modules/UpdateManager.psm1

# Define the report file path
$reportFilePath = "../reports/UpdateReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Initialize report content
$reportContent = @()
$reportContent += "Update Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "--------------------------------------------------"

# Get update history
$updateHistory = Get-UpdateHistory

if ($updateHistory) {
    foreach ($update in $updateHistory) {
        $reportContent += "Update ID: $($update.Id)"
        $reportContent += "Title: $($update.Title)"
        $reportContent += "Status: $($update.Status)"
        $reportContent += "Date: $($update.Date)"
        $reportContent += "--------------------------------------------------"
    }
} else {
    $reportContent += "No updates found."
}

# Save report to file
$reportContent | Out-File -FilePath $reportFilePath -Encoding UTF8

# Log the report generation
Log-Message "Report generated and saved to $reportFilePath" "INFO"