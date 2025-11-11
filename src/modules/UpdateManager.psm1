function Get-AvailableUpdates {
    $updates = & "C:\Program Files\Dell\CommandUpdate\DellCommandUpdate.exe" /check
    return $updates
}

function Download-Updates {
    $updates = Get-AvailableUpdates
    if ($updates) {
        & "C:\Program Files\Dell\CommandUpdate\DellCommandUpdate.exe" /download
        return $true
    }
    return $false
}

function Install-Updates {
    $installResult = & "C:\Program Files\Dell\CommandUpdate\DellCommandUpdate.exe" /install
    return $installResult
}

function Update-System {
    $downloadSuccess = Download-Updates
    if ($downloadSuccess) {
        $installSuccess = Install-Updates
        if ($installSuccess) {
            Write-Host "Updates installed successfully."
        } else {
            Write-Host "Failed to install updates."
        }
    } else {
        Write-Host "No updates available or failed to download."
    }
}

Export-ModuleMember -Function Get-AvailableUpdates, Download-Updates, Install-Updates, Update-System