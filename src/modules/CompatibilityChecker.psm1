function Get-WindowsVersion {
    $os = Get-CimInstance Win32_OperatingSystem
    return $os.Caption
}

function Check-Compatibility {
    $windowsVersion = Get-WindowsVersion
    $compatibleVersions = @("Windows 10", "Windows 11")

    if ($compatibleVersions -contains $windowsVersion) {
        return $true
    } else {
        return $false
    }
}

function Verify-SystemRequirements {
    if (-not (Check-Compatibility)) {
        Write-Error "The system is not compatible with the required Windows versions (Windows 10 or Windows 11)."
        return $false
    }
    return $true
}

Export-ModuleMember -Function Get-WindowsVersion, Check-Compatibility, Verify-SystemRequirements