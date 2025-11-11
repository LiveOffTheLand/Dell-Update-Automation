# Install-DellCommandUpdate.ps1

# Check if Dell Command Update is already installed
$installed = Get-Command "dcu-cli" -ErrorAction SilentlyContinue

if (-not $installed) {
    Write-Host "Dell Command Update is not installed. Installing now..."

    # Define the installer path
    $installerPath = "C:\Path\To\Dell\Command\Update\Installer.exe"

    # Check if the installer exists
    if (Test-Path $installerPath) {
        # Start the installation
        Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Dell Command Update installed successfully."
        } else {
            Write-Host "Failed to install Dell Command Update. Exit code: $LASTEXITCODE"
        }
    } else {
        Write-Host "Installer not found at path: $installerPath"
    }
} else {
    Write-Host "Dell Command Update is already installed."
}