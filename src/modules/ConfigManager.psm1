# ConfigManager.psm1 - v0.2
# Manages configuration settings including database connection parameters

function Get-ConfigValue {
    param (
        [string]$Key
    )
    $config = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\config\settings.json') | ConvertFrom-Json
    
    # Handle nested properties (e.g., paths.reportFilePath)
    $keys = $Key -split '\.'
    $value = $config
    foreach ($k in $keys) {
        $value = $value.$k
    }
    return $value
}

function Set-ConfigValue {
    param (
        [string]$Key,
        [string]$Value
    )
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath '..\config\settings.json'
    $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    
    # Handle nested properties
    $keys = $Key -split '\.'
    $target = $config
    for ($i = 0; $i -lt $keys.Length - 1; $i++) {
        $target = $target.$($keys[$i])
    }
    $target.$($keys[-1]) = $Value
    
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath
}

function Get-LogLevel {
    return Get-ConfigValue -Key 'loggingLevel'
}

function Get-UpdatePreference {
    return Get-ConfigValue -Key 'updatePreferences'
}

function Get-LogPath {
    return Get-ConfigValue -Key 'paths.logFilePath'
}

function Get-ReportPath {
    return Get-ConfigValue -Key 'paths.reportFilePath'
}

function Get-DatabaseConfig {
    # PLACEHOLDER: Returns database connection settings
    return Get-ConfigValue -Key 'database'
}

function Get-WebServerConfig {
    # PLACEHOLDER: Returns web server API endpoint settings
    return Get-ConfigValue -Key 'webServer'
}

Export-ModuleMember -Function Get-ConfigValue, Set-ConfigValue, Get-LogLevel, Get-UpdatePreference, Get-LogPath, Get-ReportPath, Get-DatabaseConfig, Get-WebServerConfig