<#
.SYNOPSIS
    System validation module for Dell Update Automation
.DESCRIPTION
    Validates system requirements, Dell hardware, and prerequisites
#>

function Get-IsRunningOnDell {
    <#
    .SYNOPSIS
        Checks if the system is a physical Dell machine
    .OUTPUTS
        Boolean - True if Dell machine, False otherwise
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        Write-Verbose "Checking system manufacturer..."
        
        # Check using CIM (preferred method)
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $manufacturer = $computerSystem.Manufacturer
        
        Write-Verbose "Manufacturer detected: $manufacturer"
        
        # Check for Dell in various formats
        $isDell = $manufacturer -match "Dell"
        
        if ($isDell) {
            $model = $computerSystem.Model
            Write-Verbose "Dell system detected - Model: $model"
            
            # Additional check for BIOS to confirm physical hardware
            $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
            if ($bios) {
                Write-Verbose "BIOS Manufacturer: $($bios.Manufacturer)"
                Write-Verbose "BIOS Version: $($bios.SMBIOSBIOSVersion)"
            }
        }
        
        return $isDell
        
    } catch {
        Write-Warning "Failed to determine system manufacturer: $($_.Exception.Message)"
        return $false
    }
}

function Test-PowerShellVersion {
    <#
    .SYNOPSIS
        Validates PowerShell version meets requirements
    .OUTPUTS
        Boolean - True if compatible version
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $version = $PSVersionTable.PSVersion
        Write-Verbose "PowerShell Version: $($version.Major).$($version.Minor).$($version.Build)"
        
        # Require PowerShell 5.1 or higher
        $isCompatible = $version.Major -ge 5 -and $version.Minor -ge 1
        
        if ($isCompatible) {
            Write-Verbose "PowerShell version is compatible"
        } else {
            Write-Warning "PowerShell 5.1 or higher is required. Current version: $($version.Major).$($version.Minor)"
        }
        
        return $isCompatible
        
    } catch {
        Write-Warning "Failed to check PowerShell version: $($_.Exception.Message)"
        return $false
    }
}

function Test-AdministratorPrivileges {
    <#
    .SYNOPSIS
        Checks if script is running with Administrator privileges
    .OUTPUTS
        Boolean - True if running as Administrator
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if ($isAdmin) {
            Write-Verbose "Running with Administrator privileges"
        } else {
            Write-Warning "Not running with Administrator privileges - some operations may fail"
        }
        
        return $isAdmin
        
    } catch {
        Write-Warning "Failed to check Administrator privileges: $($_.Exception.Message)"
        return $false
    }
}

function Get-WindowsVersion {
    <#
    .SYNOPSIS
        Gets detailed Windows version information
    .OUTPUTS
        PSCustomObject with Windows version details
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        
        $versionInfo = [PSCustomObject]@{
            Caption = $os.Caption
            Version = $os.Version
            BuildNumber = $os.BuildNumber
            OSArchitecture = $os.OSArchitecture
            IsWindows10 = $os.Caption -match "Windows 10"
            IsWindows11 = $os.Caption -match "Windows 11"
            InstallDate = $os.InstallDate
        }
        
        Write-Verbose "OS: $($versionInfo.Caption)"
        Write-Verbose "Version: $($versionInfo.Version)"
        Write-Verbose "Build: $($versionInfo.BuildNumber)"
        
        return $versionInfo
        
    } catch {
        Write-Warning "Failed to get Windows version: $($_.Exception.Message)"
        return $null
    }
}

function Test-SystemRequirements {
    <#
    .SYNOPSIS
        Performs comprehensive system requirements check
    .PARAMETER SkipDellCheck
        Skip the Dell hardware validation
    .OUTPUTS
        Hashtable with validation results
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [switch]$SkipDellCheck
    )
    
    Write-Verbose "Performing system requirements validation..."
    
    $results = @{
        IsValid = $true
        IsDell = $false
        IsAdmin = $false
        PowerShellOK = $false
        WindowsVersion = $null
        Errors = @()
        Warnings = @()
    }
    
    # Check PowerShell version
    $results.PowerShellOK = Test-PowerShellVersion
    if (-not $results.PowerShellOK) {
        $results.IsValid = $false
        $results.Errors += "PowerShell 5.1 or higher is required"
    }
    
    # Check Administrator privileges
    $results.IsAdmin = Test-AdministratorPrivileges
    if (-not $results.IsAdmin) {
        $results.IsValid = $false
        $results.Errors += "Administrator privileges are required"
    }
    
    # Check Dell hardware
    if (-not $SkipDellCheck) {
        $results.IsDell = Get-IsRunningOnDell
        if (-not $results.IsDell) {
            $results.IsValid = $false
            $results.Errors += "This is not a Dell system. Use -SkipDellCheck to override for testing."
        }
    } else {
        $results.Warnings += "Dell hardware check was skipped"
    }
    
    # Get Windows version
    $results.WindowsVersion = Get-WindowsVersion
    if ($null -eq $results.WindowsVersion) {
        $results.Warnings += "Could not determine Windows version"
    } elseif (-not ($results.WindowsVersion.IsWindows10 -or $results.WindowsVersion.IsWindows11)) {
        $results.Warnings += "This script is designed for Windows 10/11"
    }
    
    return $results
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Gathers comprehensive system information
    .OUTPUTS
        PSCustomObject with system details
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $bios = Get-CimInstance -ClassName Win32_BIOS
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        
        $systemInfo = [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Manufacturer = $computerSystem.Manufacturer
            Model = $computerSystem.Model
            SerialNumber = $bios.SerialNumber
            BIOSVersion = $bios.SMBIOSBIOSVersion
            OSName = $os.Caption
            OSVersion = $os.Version
            OSBuild = $os.BuildNumber
            OSArchitecture = $os.OSArchitecture
            TotalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
            Domain = $computerSystem.Domain
            Timestamp = Get-Date
        }
        
        return $systemInfo
        
    } catch {
        Write-Warning "Failed to gather system information: $($_.Exception.Message)"
        return $null
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-IsRunningOnDell',
    'Test-PowerShellVersion',
    'Test-AdministratorPrivileges',
    'Get-WindowsVersion',
    'Test-SystemRequirements',
    'Get-SystemInfo'
)