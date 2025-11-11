$file = "C:\Users\ericd\Downloads\Scripts\dell-update-automation\dell-update-automation\src\DellUpdateAutomation.ps1"
$modulesPath = "C:\Users\ericd\Downloads\Scripts\dell-update-automation\dell-update-automation\src\Modules"

Write-Host "Reading file..." -ForegroundColor Cyan
$content = Get-Content $file -Raw

Write-Host "Removing fancy box characters..." -ForegroundColor Yellow
# Remove all box drawing characters
$content = $content -replace '[═║╔╗╚╝]', ''

Write-Host "Fixing quotes..." -ForegroundColor Yellow
# Remove smart quotes using character codes
$content = $content -replace [char]0x201C, '"'  # Left double quote
$content = $content -replace [char]0x201D, '"'  # Right double quote
$content = $content -replace [char]0x2018, "'"  # Left single quote
$content = $content -replace [char]0x2019, "'"  # Right single quote
$content = $content -replace [char]0x2013, '-'  # En dash
$content = $content -replace [char]0x2014, '-'  # Em dash

# Remove any remaining non-ASCII characters except line breaks
$cleanContent = ""
foreach ($char in $content.ToCharArray()) {
    $charCode = [int]$char
    if (($charCode -ge 32 -and $charCode -le 126) -or $charCode -eq 9 -or $charCode -eq 10 -or $charCode -eq 13) {
        $cleanContent += $char
    }
}

Write-Host "Saving cleaned file..." -ForegroundColor Cyan
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($file, $cleanContent, $utf8NoBom)

Write-Host ""
Write-Host "File cleaned! All special characters removed." -ForegroundColor Green
Write-Host ""
Write-Host "Now run: .\src\DellUpdateAutomation.ps1 -WhatIf" -ForegroundColor Cyan

Write-Host "Fixing all module files..." -ForegroundColor Cyan
Write-Host ""

$files = Get-ChildItem -Path $modulesPath -Filter "*.psm1"

foreach ($file in $files) {
    Write-Host "Processing: $($file.Name)" -ForegroundColor Yellow
    
    $content = Get-Content $file.FullName -Raw
    
    # Remove smart quotes
    $content = $content -replace [char]0x201C, '"'
    $content = $content -replace [char]0x201D, '"'
    $content = $content -replace [char]0x2018, "'"
    $content = $content -replace [char]0x2019, "'"
    $content = $content -replace [char]0x2013, '-'
    $content = $content -replace [char]0x2014, '-'
    
    # Remove non-ASCII but keep line breaks
    $cleanContent = ""
    foreach ($char in $content.ToCharArray()) {
        $charCode = [int]$char
        if (($charCode -ge 32 -and $charCode -le 126) -or $charCode -eq 9 -or $charCode -eq 10 -or $charCode -eq 13) {
            $cleanContent += $char
        }
    }
    
    # Save
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($file.FullName, $cleanContent, $utf8NoBom)
    
    Write-Host "  [FIXED] $($file.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "All module files cleaned!" -ForegroundColor Green
Write-Host "Run: .\src\DellUpdateAutomation.ps1 -WhatIf" -ForegroundColor Cyan