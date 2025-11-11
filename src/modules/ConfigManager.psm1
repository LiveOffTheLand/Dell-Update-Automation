function Get-ConfigValue {
    param (
        [string]$Key
    )
    $config = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\config\settings.json') | ConvertFrom-Json
    return $config.$Key
}

function Set-ConfigValue {
    param (
        [string]$Key,
        [string]$Value
    )
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath '..\config\settings.json'
    $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    $config.$Key = $Value
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath
}

function Get-LogLevel {
    return Get-ConfigValue -Key 'LogLevel'
}

function Get-UpdatePreference {
    return Get-ConfigValue -Key 'UpdatePreference'
}

function Get-LogPath {
    return Get-ConfigValue -Key 'LogPath'
}

function Get-ReportPath {
    return Get-ConfigValue -Key 'ReportPath'
}