# Generate-Report.ps1 - v0.2
# Generates update reports and sends them to Apache web server with MariaDB

# Import necessary modules
Import-Module ../modules/LogManager.psm1
Import-Module ../modules/UpdateManager.psm1
Import-Module ../modules/ConfigManager.psm1

function Send-ReportToDatabase {
    param (
        [Parameter(Mandatory=$true)]
        [array]$UpdateHistory
    )
    
    # Get database configuration
    $dbConfig = Get-DatabaseConfig
    
    # PLACEHOLDER: Database connection string
    $connectionString = "Server=$($dbConfig.server);Port=$($dbConfig.port);Database=$($dbConfig.database);Uid=$($dbConfig.username);Pwd=$($dbConfig.password);"
    
    try {
        # Load MySQL .NET Connector (requires MySql.Data.dll)
        Add-Type -Path "C:\Path\To\MySql.Data.dll"  # PLACEHOLDER: Update path to MySQL connector
        
        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connectionString)
        $connection.Open()
        
        foreach ($update in $UpdateHistory) {
            $query = @"
INSERT INTO $($dbConfig.tableName) (update_id, title, status, date, computer_name, generated_at)
VALUES (@UpdateId, @Title, @Status, @Date, @ComputerName, @GeneratedAt)
"@
            
            $command = $connection.CreateCommand()
            $command.CommandText = $query
            $command.Parameters.AddWithValue("@UpdateId", $update.Id) | Out-Null
            $command.Parameters.AddWithValue("@Title", $update.Title) | Out-Null
            $command.Parameters.AddWithValue("@Status", $update.Status) | Out-Null
            $command.Parameters.AddWithValue("@Date", $update.Date) | Out-Null
            $command.Parameters.AddWithValue("@ComputerName", $env:COMPUTERNAME) | Out-Null
            $command.Parameters.AddWithValue("@GeneratedAt", (Get-Date)) | Out-Null
            
            $command.ExecuteNonQuery() | Out-Null
        }
        
        $connection.Close()
        Log-Message "Successfully sent report to database" "INFO"
        return $true
        
    } catch {
        Log-Message "Failed to send report to database: $_" "ERROR"
        return $false
    }
}

function Send-ReportToWebServer {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$ReportData
    )
    
    # Get web server configuration
    $webConfig = Get-WebServerConfig
    
    # PLACEHOLDER: API endpoint and authentication
    $apiUrl = $webConfig.apiEndpoint
    $apiKey = $webConfig.apiKey
    
    try {
        $headers = @{
            "Content-Type" = "application/json"
            "X-API-Key" = $apiKey  # PLACEHOLDER: Authentication header
        }
        
        $body = $ReportData | ConvertTo-Json -Depth 10
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -TimeoutSec $webConfig.timeout
        
        Log-Message "Successfully sent report to web server API" "INFO"
        return $response
        
    } catch {
        Log-Message "Failed to send report to web server: $_" "ERROR"
        return $null
    }
}

# Main execution
try {
    # Get update history
    $updateHistory = Get-UpdateHistory
    
    # Create report data structure
    $reportData = @{
        GeneratedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        ComputerName = $env:COMPUTERNAME
        Updates = @()
    }
    
    if ($updateHistory) {
        foreach ($update in $updateHistory) {
            $reportData.Updates += @{
                Id = $update.Id
                Title = $update.Title
                Status = $update.Status
                Date = $update.Date
            }
        }
    } else {
        Log-Message "No updates found" "INFO"
    }
    
    # Save local JSON report (optional backup)
    $reportFilePath = Get-ReportPath
    $reportData | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFilePath -Encoding UTF8
    Log-Message "Local report saved to $reportFilePath" "INFO"
    
    # Send to database
    if ($updateHistory) {
        $dbSuccess = Send-ReportToDatabase -UpdateHistory $updateHistory
        
        # Send to web server API
        $apiSuccess = Send-ReportToWebServer -ReportData $reportData
        
        if ($dbSuccess -and $apiSuccess) {
            Log-Message "Report successfully sent to both database and web server" "INFO"
        }
    }
    
} catch {
    Log-Message "Error generating report: $_" "ERROR"
}