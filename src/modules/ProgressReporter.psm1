<#
.SYNOPSIS
    Progress reporting module for Dell Update Automation
.DESCRIPTION
    Provides beautiful console progress bars and status reporting
#>

function Show-ProgressBar {
    <#
    .SYNOPSIS
        Displays a progress bar in the console
    .PARAMETER Percent
        Progress percentage (0-100)
    .PARAMETER Status
        Status message to display
    .PARAMETER Activity
        Activity description
    .PARAMETER Width
        Width of the progress bar in characters
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$Percent,
        
        [string]$Status = "Processing...",
        
        [string]$Activity = "Dell Update Automation",
        
        [int]$Width = 50
    )
    
    try {
        # Calculate progress bar fill
        $filled = [math]::Floor(($Percent / 100) * $Width)
        $empty = $Width - $filled
        
        # Create progress bar string
        $progressBar = "[" + ("" * $filled) + ("" * $empty) + "]"
        
        # Determine color based on progress
        $color = switch ($Percent) {
            { $_ -lt 33 } { 'Red' }
            { $_ -lt 66 } { 'Yellow' }
            default { 'Green' }
        }
        
        # Build output string
        $output = "$Activity : $progressBar $Percent% - $Status"
        
        # Clear current line and write progress
        Write-Host "`r$(' ' * 120)`r" -NoNewline
        Write-Host $output -ForegroundColor $color -NoNewline
        
    } catch {
        Write-Warning "Failed to display progress bar: $($_.Exception.Message)"
    }
}

function Write-StepHeader {
    <#
    .SYNOPSIS
        Writes a formatted step header to the console
    .PARAMETER StepNumber
        Step number
    .PARAMETER TotalSteps
        Total number of steps
    .PARAMETER Description
        Step description
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$StepNumber,
        
        [Parameter(Mandatory)]
        [int]$TotalSteps,
        
        [Parameter(Mandatory)]
        [string]$Description
    )
    
    Write-Host "`n" -NoNewline
    Write-Host "" -ForegroundColor Cyan
    Write-Host "  Step $StepNumber of $TotalSteps : " -NoNewline -ForegroundColor Yellow
    Write-Host $Description -ForegroundColor White
    Write-Host "" -ForegroundColor Cyan
}

function Write-StatusMessage {
    <#
    .SYNOPSIS
        Writes a formatted status message
    .PARAMETER Message
        Message to display
    .PARAMETER Type
        Message type (Info, Success, Warning, Error)
    .PARAMETER Indent
        Indentation level
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug')]
        [string]$Type = 'Info',
        
        [int]$Indent = 2
    )
    
    $indentStr = " " * $Indent
    
    $symbol = switch ($Type) {
        'Info'    { '' }
        'Success' { '(OK)' }
        'Warning' { '' }
        'Error'   { '(X)' }
        'Debug'   { '' }
    }
    
    $color = switch ($Type) {
        'Info'    { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Debug'   { 'Gray' }
    }
    
    Write-Host "$indentStr$symbol " -NoNewline -ForegroundColor $color
    Write-Host $Message -ForegroundColor White
}

function Write-Banner {
    <#
    .SYNOPSIS
        Writes a formatted banner to the console
    .PARAMETER Title
        Banner title
    .PARAMETER Subtitle
        Optional subtitle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        
        [string]$Subtitle
    )
    
    $width = 70
    $border = "" * $width
    
    Write-Host ""
    Write-Host "$border" -ForegroundColor Cyan
    
    # Center the title
    $titlePadding = [math]::Floor(($width - $Title.Length) / 2)
    $titleLine = (" " * $titlePadding) + $Title
    Write-Host "$titleLine" -NoNewline -ForegroundColor Cyan
    Write-Host (" " * ($width - $titleLine.Length)) -NoNewline
    Write-Host "" -ForegroundColor Cyan
    
    if ($Subtitle) {
        $subtitlePadding = [math]::Floor(($width - $Subtitle.Length) / 2)
        $subtitleLine = (" " * $subtitlePadding) + $Subtitle
        Write-Host "$subtitleLine" -NoNewline -ForegroundColor Cyan
        Write-Host (" " * ($width - $subtitleLine.Length)) -NoNewline
        Write-Host "" -ForegroundColor Cyan
    }
    
    Write-Host "$border" -ForegroundColor Cyan
    Write-Host ""
}

function Write-SummaryTable {
    <#
    .SYNOPSIS
        Writes a formatted summary table
    .PARAMETER Data
        Array of hashtables with Label and Value properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Data
    )
    
    $maxLabelLength = ($Data | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
    
    foreach ($item in $Data) {
        $label = $item.Label.PadRight($maxLabelLength)
        Write-Host "  $label : $($item.Value)" -ForegroundColor White
    }
}

function Start-CountdownTimer {
    <#
    .SYNOPSIS
        Displays a countdown timer
    .PARAMETER Seconds
        Number of seconds to count down
    .PARAMETER Message
        Message to display during countdown
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Seconds,
        
        [Parameter()]
        [string]$Message = "Countdown"
    )
    
    Write-Host ""
    Write-Host "  $Message in:" -ForegroundColor Yellow
    
    for ($i = $Seconds; $i -gt 0; $i--) {
        Write-Host "`r  $i seconds remaining... " -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
    
    Write-Host "`r  Starting now...           " -ForegroundColor Green
    Write-Host ""
}

function Show-UpdateList {
    <#
    .SYNOPSIS
        Displays a formatted list of updates
    .PARAMETER Updates
        Array of update objects
    .PARAMETER Title
        List title
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Updates,
        
        [string]$Title = "Available Updates"
    )
    
    if ($Updates.Count -eq 0) {
        Write-StatusMessage -Message "No updates found" -Type Info
        return
    }
    
    # Highlight update count
    Write-Host ""
    Write-Host "" -ForegroundColor Magenta
    Write-Host "  " -NoNewline -ForegroundColor Magenta
    Write-Host "UPDATES FOUND: " -NoNewline -ForegroundColor Yellow
    Write-Host "$($Updates.Count)" -NoNewline -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host " update(s) available                                " -NoNewline -ForegroundColor Magenta
    Write-Host "" -ForegroundColor Magenta
    Write-Host "" -ForegroundColor Magenta
    Write-Host ""
    Write-Host ""  # Extra space for readability
    
    $counter = 1
    foreach ($update in $Updates) {
        Write-Host "   Update $counter " -NoNewline -ForegroundColor Cyan
        Write-Host ("" * 50) -ForegroundColor Cyan
        Write-Host "  " -ForegroundColor Cyan
        
        Write-Host "    " -NoNewline -ForegroundColor Cyan
        Write-Host "Name       : " -NoNewline -ForegroundColor Gray
        Write-Host $update.Name -ForegroundColor White
        
        if ($update.Version) {
            Write-Host "    " -NoNewline -ForegroundColor Cyan
            Write-Host "Version    : " -NoNewline -ForegroundColor Gray
            Write-Host $update.Version -ForegroundColor Cyan
        }
        
        Write-Host "    " -NoNewline -ForegroundColor Cyan
        Write-Host "Type       : " -NoNewline -ForegroundColor Gray
        $typeColor = switch ($update.Type) {
            'BIOS' { 'Magenta' }
            'Firmware' { 'Yellow' }
            'Driver' { 'Cyan' }
            'Application' { 'Green' }
            default { 'White' }
        }
        Write-Host $update.Type -ForegroundColor $typeColor
        
        if ($update.Severity) {
            Write-Host "    " -NoNewline -ForegroundColor Cyan
            Write-Host "Severity   : " -NoNewline -ForegroundColor Gray
            $severityColor = switch ($update.Severity) {
                'Urgent' { 'Red' }
                'Critical' { 'Red' }
                'Recommended' { 'Yellow' }
                'Optional' { 'Green' }
                default { 'White' }
            }
            Write-Host $update.Severity -ForegroundColor $severityColor
        }
        
        if ($update.Category) {
            Write-Host "    " -NoNewline -ForegroundColor Cyan
            Write-Host "Category   : " -NoNewline -ForegroundColor Gray
            Write-Host $update.Category -ForegroundColor White
        }
        
        if ($update.RebootRequired -and $update.RebootRequired -ne "Unknown") {
            Write-Host "    " -NoNewline -ForegroundColor Cyan
            Write-Host "Reboot Req : " -NoNewline -ForegroundColor Gray
            $rebootColor = if ($update.RebootRequired -eq "Yes") { 'Yellow' } else { 'Green' }
            Write-Host $update.RebootRequired -ForegroundColor $rebootColor
        }
        
        Write-Host "  " -ForegroundColor Cyan
        Write-Host "  " -NoNewline -ForegroundColor Cyan
        Write-Host ("" * 60) -ForegroundColor Cyan
        Write-Host ""
        
        $counter++
    }
}

function Write-OperationResult {
    <#
    .SYNOPSIS
        Displays the result of an operation
    .PARAMETER Success
        Whether the operation was successful
    .PARAMETER Message
        Result message
    .PARAMETER Details
        Additional details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Success,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [string]$Details
    )
    
    $symbol = if ($Success) { "(OK)" } else { "(X)" }
    $color = if ($Success) { "Green" } else { "Red" }
    
    Write-Host ""
    Write-Host "  $symbol " -NoNewline -ForegroundColor $color
    Write-Host $Message -ForegroundColor White
    
    if ($Details) {
        Write-Host "     " -NoNewline -ForegroundColor Gray
        Write-Host $Details -ForegroundColor Gray
    }
}

function Show-ProcessingAnimation {
    <#
    .SYNOPSIS
        Shows a processing animation
    .PARAMETER Message
        Message to display
    .PARAMETER ScriptBlock
        Script block to execute while animating
    #>
    [CmdletBinding()]
    param(
        [string]$Message = "Processing",
        
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )
    
    $frames = @('', '', '', '', '', '', '', '', '', '')
    $job = Start-Job -ScriptBlock $ScriptBlock
    
    $frameIndex = 0
    while ($job.State -eq 'Running') {
        $frame = $frames[$frameIndex % $frames.Count]
        Write-Host "`r  $frame $Message..." -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 100
        $frameIndex++
    }
    
    Write-Host "`r$(' ' * 80)`r" -NoNewline
    
    $result = Receive-Job -Job $job -Wait -AutoRemoveJob
    return $result
}

function Show-ScanningAnimation {
    <#
    .SYNOPSIS
        Shows a scanning animation with dots
    .PARAMETER ScriptBlock
        The script to run while showing animation
    .PARAMETER Message
        Message to display before animation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [string]$Message = "Scanning"
    )
    
    Write-Host "  $Message" -NoNewline -ForegroundColor Cyan
    
    # Execute the script block directly (no background job)
    # This ensures all module functions are available
    $dots = @('.', '..', '...', '....')
    $dotIndex = 0
    
    try {
        # For operations that take time, we'll handle animation differently
        # This function is now just a simple wrapper
        $result = & $ScriptBlock
        
        # Show completion
        Write-Host "`r  $Message... Done                    " -ForegroundColor Green
        
        return $result
        
    } catch {
        Write-Host "`r  $Message... Failed                  " -ForegroundColor Red
        throw
    }
}

function Show-ElapsedTime {
    <#
    .SYNOPSIS
        Displays elapsed time during a long operation
    .PARAMETER ScriptBlock
        The script block to execute
    .PARAMETER Message
        Message to display
    .PARAMETER UpdateInterval
        How often to update the display (in seconds)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [string]$Message = "Processing",
        
        [Parameter()]
        [int]$UpdateInterval = 5
    )
    
    $startTime = Get-Date
    $lastUpdate = Get-Date
    
    # Start background job
    $job = Start-Job -ScriptBlock $ScriptBlock
    
    Write-Host "  $Message..." -ForegroundColor Cyan
    Write-Host "  Elapsed: 0m 0s" -NoNewline -ForegroundColor Gray
    
    # Monitor with elapsed time
    while ($job.State -eq 'Running') {
        $elapsed = (Get-Date) - $startTime
        
        if (((Get-Date) - $lastUpdate).TotalSeconds -ge $UpdateInterval) {
            $elapsedStr = "$($elapsed.Minutes)m $($elapsed.Seconds)s"
            Write-Host "`r  Elapsed: $elapsedStr" -NoNewline -ForegroundColor Gray
            $lastUpdate = Get-Date
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    # Get results
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    
    # Final elapsed time
    $totalElapsed = (Get-Date) - $startTime
    Write-Host "`r  Elapsed: $($totalElapsed.Minutes)m $($totalElapsed.Seconds)s - Done" -ForegroundColor Green
    
    return $result
}

# Export module members
Export-ModuleMember -Function @(
    'Show-ProgressBar',
    'Write-StepHeader',
    'Write-StatusMessage',
    'Write-Banner',
    'Write-SummaryTable',
    'Start-CountdownTimer',
    'Show-UpdateList',
    'Write-OperationResult',
    'Show-ProcessingAnimation',
    'Show-ScanningAnimation',
    'Show-ElapsedTime'
)