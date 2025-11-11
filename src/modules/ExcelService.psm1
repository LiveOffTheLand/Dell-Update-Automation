<#
.SYNOPSIS
    Excel service module for Dell Update Automation
.DESCRIPTION
    Manages Excel workbook creation, updates, and data management using ImportExcel
#>

function Test-ImportExcelModule {
    <#
    .SYNOPSIS
        Checks if ImportExcel module is installed
    .PARAMETER AutoInstall
        Automatically install if not found
    .OUTPUTS
        Boolean - True if available
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$AutoInstall
    )
    
    try {
        $module = Get-Module -ListAvailable -Name ImportExcel
        
        if ($module) {
            Write-Verbose "ImportExcel module found - Version: $($module.Version)"
            Import-Module ImportExcel -ErrorAction Stop
            return $true
        } else {
            Write-Verbose "ImportExcel module not found"
            
            if ($AutoInstall) {
                Write-Host "  Installing ImportExcel module..." -ForegroundColor Cyan
                Install-Module -Name ImportExcel -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
                Import-Module ImportExcel -ErrorAction Stop
                Write-Host "  (OK) ImportExcel module installed" -ForegroundColor Green
                return $true
            }
            
            return $false
        }
        
    } catch {
        Write-Warning "Failed to load ImportExcel module: $($_.Exception.Message)"
        return $false
    }
}

function Initialize-UpdateCatalog {
    <#
    .SYNOPSIS
        Creates or initializes the update catalog Excel file
    .PARAMETER FilePath
        Path to the Excel catalog file
    .OUTPUTS
        Boolean - True if successful
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    try {
        Write-Verbose "Initializing update catalog: $FilePath"
        
        # Ensure ImportExcel is loaded
        if (-not (Test-ImportExcelModule -AutoInstall)) {
            throw "ImportExcel module is required"
        }
        
        # Create directory if it doesn't exist
        $directory = Split-Path $FilePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Check if file exists
        if (-not (Test-Path $FilePath)) {
            Write-Verbose "Creating new catalog file"
            
            # Create initial catalog with headers
            $initialData = @(
                [PSCustomObject]@{
                    UpdateID = ""
                    Name = ""
                    Version = ""
                    Type = ""
                    Severity = ""
                    Category = ""
                    ReleaseDate = ""
                    Status = ""
                    InstallDate = ""
                    RebootRequired = ""
                    Notes = ""
                }
            )
            
            $initialData | Export-Excel -Path $FilePath -WorksheetName "Updates" -AutoSize -AutoFilter -FreezeTopRow
            
            Write-Host "  (OK) Created new update catalog" -ForegroundColor Green
        } else {
            Write-Verbose "Catalog file already exists"
        }
        
        return $true
        
    } catch {
        Write-Error "Failed to initialize catalog: $($_.Exception.Message)"
        return $false
    }
}

function Add-UpdateToCatalog {
    <#
    .SYNOPSIS
        Adds or updates an entry in the update catalog
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [hashtable]$UpdateInfo
    )
    
    try {
        # Check if file is locked
        $isLocked = $false
        try {
            $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            $fileStream.Close()
            $fileStream.Dispose()
        } catch {
            $isLocked = $true
            Write-Verbose "File is locked: $FilePath"
            return $false
        }
        
        if (-not (Test-Path $FilePath)) {
            Write-Warning "Catalog file not found: $FilePath"
            return $false
        }
        
        # Import existing data
        $existingData = @(Import-Excel -Path $FilePath -WorksheetName "Updates")
        
        # Create a proper object with all fields
        $newUpdate = [PSCustomObject]@{
            UpdateID = $UpdateInfo.UpdateID
            Name = $UpdateInfo.Name
            Version = $UpdateInfo.Version
            Type = $UpdateInfo.Type
            Severity = $UpdateInfo.Severity
            Category = $UpdateInfo.Category
            ReleaseDate = $UpdateInfo.ReleaseDate
            Status = $UpdateInfo.Status
            InstallDate = $UpdateInfo.InstallDate
            RebootRequired = $UpdateInfo.RebootRequired
            Notes = $UpdateInfo.Notes
            LastSeen = if ($UpdateInfo.LastSeen) { $UpdateInfo.LastSeen } else { (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
            ScanDate = if ($UpdateInfo.ScanDate) { $UpdateInfo.ScanDate } else { (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
        }
        
        # Check if update already exists
        $existingUpdate = $existingData | Where-Object { 
            $_.UpdateID -eq $UpdateInfo.UpdateID -or 
            ($_.Name -eq $UpdateInfo.Name -and $_.Version -eq $UpdateInfo.Version)
        } | Select-Object -First 1
        
        if ($existingUpdate) {
            # Update existing entry
            $existingUpdate.LastSeen = $newUpdate.LastSeen
            $existingUpdate.Status = $newUpdate.Status
            
            if ($UpdateInfo.InstallDate) {
                $existingUpdate.InstallDate = $UpdateInfo.InstallDate
            }
            
            if ($UpdateInfo.Notes) {
                $existingUpdate.Notes = $UpdateInfo.Notes
            }
            
            Write-Verbose "Updated existing entry: $($UpdateInfo.Name)"
        } else {
            # Add new entry
            $existingData += $newUpdate
            Write-Verbose "Added new entry: $($UpdateInfo.Name)"
        }
        
        # Export back to Excel
        $existingData | Export-Excel -Path $FilePath -WorksheetName "Updates" -AutoSize -FreezeTopRow -BoldTopRow
        
        return $true
        
    } catch {
        Write-Warning "Failed to update catalog: $($_.Exception.Message)"
        return $false
    }
}

function Get-CatalogUpdates {
    <#
    .SYNOPSIS
        Retrieves updates from the catalog
    .PARAMETER FilePath
        Path to the Excel catalog file
    .PARAMETER Status
        Filter by status
    .OUTPUTS
        Array of update objects
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [ValidateSet('Available', 'Installed', 'Failed', 'Pending', 'All')]
        [string]$Status = 'All'
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            Write-Warning "Catalog file not found: $FilePath"
            return @()
        }
        
        $updates = Import-Excel -Path $FilePath -WorksheetName "Updates"
        
        if ($Status -ne 'All') {
            $updates = $updates | Where-Object { $_.Status -eq $Status }
        }
        
        return $updates
        
    } catch {
        Write-Error "Failed to read catalog: $($_.Exception.Message)"
        return @()
    }
}

function Update-CatalogStatus {
    <#
    .SYNOPSIS
        Updates the status of an existing catalog entry
    .PARAMETER FilePath
        Path to catalog Excel file
    .PARAMETER UpdateID
        Update identifier
    .PARAMETER Status
        New status
    .PARAMETER InstallDate
        Installation date
    .PARAMETER RebootRequired
        Whether reboot is required
    .PARAMETER Notes
        Additional notes
    .OUTPUTS
        Boolean - True if successful
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$UpdateID,
        
        [Parameter()]
        [string]$Status,
        
        [Parameter()]
        [string]$InstallDate,
        
        [Parameter()]
        [string]$RebootRequired,
        
        [Parameter()]
        [string]$Notes
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            Write-Warning "Catalog file not found: $FilePath"
            return $false
        }
        
        # Check if file is locked
        try {
            $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            $fileStream.Close()
            $fileStream.Dispose()
        } catch [System.IO.IOException] {
            if ($_.Exception.Message -match "being used by another process") {
                throw "The catalog file is currently open in another application. Please close '$FilePath' and try again."
            }
            throw
        }
        
        # Import existing data
        $catalogData = Import-Excel -Path $FilePath -WorksheetName "Updates"
        
        # Find the update
        $update = $catalogData | Where-Object { $_.UpdateID -eq $UpdateID }
        
        if (-not $update) {
            Write-Verbose "Update not found in catalog: $UpdateID"
            return $false
        }
        
        # Update fields
        if ($Status) { $update.Status = $Status }
        if ($InstallDate) { $update.InstallDate = $InstallDate }
        if ($RebootRequired) { $update.RebootRequired = $RebootRequired }
        if ($Notes) { $update.Notes = $Notes }
        $update.LastSeen = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Save changes
        $catalogData | Export-Excel -Path $FilePath -WorksheetName "Updates" -AutoSize -FreezeTopRow -BoldTopRow -TableName "UpdatesTable"
        
        Write-Verbose "Catalog status updated for: $UpdateID"
        return $true
        
    } catch {
        # Check for specific error types
        if ($_.Exception.Message -match "open in another application|currently open|being used by another process") {
            Write-Warning "WARNING: Catalog file is locked - Please close Excel and try again"
            Write-Warning "         File: $FilePath"
        } elseif ($_.Exception.Message -match "Error saving file") {
            Write-Warning "WARNING: Cannot save catalog - File may be open in Excel"
            Write-Warning "         File: $FilePath"
        } else {
            Write-Warning "Failed to update catalog status: $($_.Exception.Message)"
        }
        return $false
    }
}

function Initialize-VerboseLog {
    <#
    .SYNOPSIS
        Creates or initializes the verbose log Excel file
    .PARAMETER FilePath
        Path to the Excel log file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    try {
        Write-Verbose "Initializing verbose log: $FilePath"
        
        # Create directory if it doesn't exist
        $directory = Split-Path $FilePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        if (-not (Test-Path $FilePath)) {
            $initialData = @(
                [PSCustomObject]@{
                    Timestamp = ""
                    Level = ""
                    Category = ""
                    Message = ""
                    Details = ""
                }
            )
            
            $initialData | Export-Excel -Path $FilePath -WorksheetName "Log" -AutoSize -AutoFilter -FreezeTopRow
        }
        
    } catch {
        Write-Error "Failed to initialize verbose log: $($_.Exception.Message)"
    }
}

function Add-VerboseLogEntry {
    <#
    .SYNOPSIS
        Adds an entry to the verbose log
    .PARAMETER FilePath
        Path to the Excel log file
    .PARAMETER Level
        Log level (Info, Warning, Error, Debug, Success)
    .PARAMETER Category
        Log category
    .PARAMETER Message
        Log message
    .PARAMETER Details
        Additional details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug', 'Success')]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Category,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [string]$Details = ""
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            Initialize-VerboseLog -FilePath $FilePath
        }
        
        # Check if file is locked - but don't fail logging for this
        try {
            $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            $fileStream.Close()
            $fileStream.Dispose()
        } catch [System.IO.IOException] {
            if ($_.Exception.Message -match "being used by another process") {
                # Silently skip if log is open (don't spam warnings)
                Write-Verbose "Log file is locked, skipping entry"
                return
            }
            throw
        }
        
        $logEntry = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Level = $Level
            Category = $Category
            Message = $Message
            Details = $Details
            ComputerName = $env:COMPUTERNAME
            User = $env:USERNAME
        }
        
        # Append to log
        $logEntry | Export-Excel -Path $FilePath -WorksheetName "Log" -Append -AutoSize -TableName "LogTable"
        
        Write-Verbose "Log entry added: [$Level] $Category - $Message"
        
    } catch {
        # Don't show warnings for log file locks (it's not critical)
        if ($_.Exception.Message -notmatch "open in another application|currently open|being used by another process|Error saving file") {
            Write-Verbose "Failed to add log entry: $($_.Exception.Message)"
        }
    }
}

function Export-CatalogToHtml {
    <#
    .SYNOPSIS
        Exports the update catalog to HTML for easy viewing
    .PARAMETER ExcelPath
        Path to the Excel catalog file
    .PARAMETER HtmlPath
        Output HTML file path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExcelPath,
        
        [Parameter(Mandatory)]
        [string]$HtmlPath
    )
    
    try {
        $updates = Import-Excel -Path $ExcelPath -WorksheetName "Updates"
        
        $html = $updates | ConvertTo-Html -Title "Dell Update Catalog" -PreContent "<h1>Dell Update Catalog</h1><p>Generated: $(Get-Date)</p>"
        
        $html | Out-File -FilePath $HtmlPath -Encoding UTF8
        
        Write-Verbose "HTML report generated: $HtmlPath"
        
    } catch {
        Write-Error "Failed to export to HTML: $($_.Exception.Message)"
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Test-ImportExcelModule',
    'Initialize-UpdateCatalog',
    'Add-UpdateToCatalog',
    'Get-CatalogUpdates',
    'Update-CatalogStatus',
    'Initialize-VerboseLog',
    'Add-VerboseLogEntry',
    'Export-CatalogToHtml'
)