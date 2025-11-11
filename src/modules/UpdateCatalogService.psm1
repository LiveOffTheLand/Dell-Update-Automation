<#
.SYNOPSIS
    Update catalog service module
.DESCRIPTION
    Manages Dell update catalog operations, parsing, and processing
#>

function Get-UpdatesFromDcu {
    <#
    .SYNOPSIS
        Gets available updates from Dell Command Update
    .OUTPUTS
        Array of update objects
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    try {
        Write-Verbose "Getting updates from DCU..."
        
        # Import DellCommandService module function
        $updates = Invoke-DellUpdateScan
        
        Write-Verbose "Retrieved $($updates.Count) update(s) from DCU"
        
        return $updates
        
    } catch {
        Write-Error "Failed to get updates from DCU: $($_.Exception.Message)"
        return @()
    }
}

function Sync-CatalogWithDcu {
    <#
    .SYNOPSIS
        Synchronizes the Excel catalog with DCU scan results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath,
        
        [Parameter(Mandatory)]
        [array]$Updates
    )
    
    try {
        $catalogLocked = $false
        $maxRetries = 3
        $retryCount = 0
        
        while ($retryCount -lt $maxRetries) {
            try {
                # Try to open the file to check if locked
                $fileStream = [System.IO.File]::Open($CatalogPath, 'Open', 'ReadWrite', 'None')
                $fileStream.Close()
                $fileStream.Dispose()
                break
            } catch {
                $catalogLocked = $true
                $retryCount++
                
                if ($retryCount -eq 1) {
                    Write-Host ""
                    Write-Host "  ! Catalog file is open in another program (Excel?)" -ForegroundColor Yellow
                    Write-Host "    Please close it and press Enter to retry..." -ForegroundColor Yellow
                    Read-Host
                } elseif ($retryCount -lt $maxRetries) {
                    Write-Host "    Retrying... ($retryCount/$maxRetries)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                } else {
                    Write-Host "    ! Could not access catalog file after $maxRetries attempts" -ForegroundColor Red
                    Write-Host "    Catalog sync skipped - continuing..." -ForegroundColor Yellow
                    return $false
                }
            }
        }
        
        # Sync each update
        $syncCount = 0
        foreach ($update in $Updates) {
            try {
                # Create update info with ALL required fields
                $updateInfo = @{
                    UpdateID = if ($update.UpdateID) { $update.UpdateID } else { [guid]::NewGuid().ToString() }
                    Name = $update.Name
                    Version = if ($update.Version) { $update.Version } else { "N/A" }
                    Type = $update.Type
                    Severity = $update.Severity
                    Category = $update.Category
                    ReleaseDate = if ($update.ReleaseDate) { $update.ReleaseDate } else { (Get-Date -Format 'yyyy-MM-dd') }
                    Status = 'Available'
                    InstallDate = ""
                    RebootRequired = if ($update.RebootRequired) { 'Yes' } else { 'No' }
                    Notes = "Detected by scan on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    LastSeen = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                    ScanDate = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                }
                
                # Add to catalog
                $addResult = Add-UpdateToCatalog -FilePath $CatalogPath -UpdateInfo $updateInfo
                
                if ($addResult) {
                    $syncCount++
                }
                
            } catch {
                Write-Warning "Failed to sync update '$($update.Name)': $($_.Exception.Message)"
                continue
            }
        }
        
        if ($syncCount -gt 0) {
            Write-Host "  (OK) Catalog synchronized: $syncCount update(s) added/updated" -ForegroundColor Green
        } else {
            Write-Host "  ! No updates were synchronized" -ForegroundColor Yellow
        }
        
        return $true
        
    } catch {
        Write-Host "  ! Catalog sync failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "    Continuing without catalog sync..." -ForegroundColor Gray
        return $false
    }
}

function Get-UpdateStatistics {
    <#
    .SYNOPSIS
        Gets statistics about updates in the catalog
    .PARAMETER CatalogPath
        Path to catalog Excel file
    .OUTPUTS
        Hashtable with statistics
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath
    )
    
    try {
        if (-not (Test-Path $CatalogPath)) {
            return @{
                TotalUpdates = 0
                Available = 0
                Installed = 0
                Failed = 0
                Pending = 0
            }
        }
        
        $updates = Import-Excel -Path $CatalogPath -WorksheetName "Updates"
        
        $stats = @{
            TotalUpdates = $updates.Count
            Available = ($updates | Where-Object { $_.Status -eq 'Available' }).Count
            Installed = ($updates | Where-Object { $_.Status -eq 'Installed' }).Count
            Failed = ($updates | Where-Object { $_.Status -eq 'Failed' }).Count
            Pending = ($updates | Where-Object { $_.Status -eq 'Pending' }).Count
        }
        
        return $stats
        
    } catch {
        Write-Warning "Failed to get statistics: $($_.Exception.Message)"
        return @{
            TotalUpdates = 0
            Available = 0
            Installed = 0
            Failed = 0
            Pending = 0
        }
    }
}

function Export-UpdateReport {
    <#
    .SYNOPSIS
        Exports update catalog to various formats
    .PARAMETER CatalogPath
        Path to catalog Excel file
    .PARAMETER OutputPath
        Output directory path
    .PARAMETER Format
        Export format (HTML, CSV, JSON, All)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [ValidateSet('HTML', 'CSV', 'JSON', 'All')]
        [string]$Format = 'All'
    )
    
    try {
        if (-not (Test-Path $CatalogPath)) {
            Write-Warning "Catalog not found: $CatalogPath"
            return
        }
        
        $updates = Import-Excel -Path $CatalogPath -WorksheetName "Updates"
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        
        # CSV Export
        if ($Format -in @('CSV', 'All')) {
            $csvPath = Join-Path $OutputPath "UpdateReport_$timestamp.csv"
            $updates | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Verbose "CSV report exported: $csvPath"
        }
        
        # JSON Export
        if ($Format -in @('JSON', 'All')) {
            $jsonPath = Join-Path $OutputPath "UpdateReport_$timestamp.json"
            $updates | ConvertTo-Json -Depth 10 | Out-File $jsonPath
            Write-Verbose "JSON report exported: $jsonPath"
        }
        
        # HTML Export
        if ($Format -in @('HTML', 'All')) {
            $htmlPath = Join-Path $OutputPath "UpdateReport_$timestamp.html"
            
            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Dell Update Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0076ce; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background: #0076ce; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f0f0f0; }
        .status-installed { color: green; font-weight: bold; }
        .status-failed { color: red; font-weight: bold; }
        .status-available { color: orange; font-weight: bold; }
        .stats { background: white; padding: 20px; margin-bottom: 20px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <h1>Dell Update Report</h1>
    <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    
    <div class="stats">
        <h2>Statistics</h2>
        <p>Total Updates: $($updates.Count)</p>
        <p>Installed: $(($updates | Where-Object { $_.Status -eq 'Installed' }).Count)</p>
        <p>Available: $(($updates | Where-Object { $_.Status -eq 'Available' }).Count)</p>
        <p>Failed: $(($updates | Where-Object { $_.Status -eq 'Failed' }).Count)</p>
    </div>
    
    <table>
        <tr>
            <th>Update ID</th>
            <th>Name</th>
            <th>Version</th>
            <th>Type</th>
            <th>Severity</th>
            <th>Status</th>
            <th>Install Date</th>
        </tr>
"@
            
            foreach ($update in $updates) {
                $statusClass = "status-$($update.Status.ToLower())"
                $html += @"
        <tr>
            <td>$($update.UpdateID)</td>
            <td>$($update.Name)</td>
            <td>$($update.Version)</td>
            <td>$($update.Type)</td>
            <td>$($update.Severity)</td>
            <td class="$statusClass">$($update.Status)</td>
            <td>$($update.InstallDate)</td>
        </tr>
"@
            }
            
            $html += @"
    </table>
</body>
</html>
"@
            
            $html | Out-File $htmlPath
            Write-Verbose "HTML report exported: $htmlPath"
        }
        
    } catch {
        Write-Warning "Failed to export report: $($_.Exception.Message)"
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-UpdatesFromDcu',
    'Sync-CatalogWithDcu',
    'Get-UpdateStatistics',
    'Export-UpdateReport'
)