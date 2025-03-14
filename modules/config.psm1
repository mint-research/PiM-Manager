# config.psm1 - Zentrales Konfigurationsmanagement für PiM-Manager
# Speicherort: modules\config.psm1

# Pfadmodul laden, falls verfügbar
$pathsMod = Join-Path (Split-Path -Parent $PSScriptRoot) "modules\paths.psm1"
if (Test-Path $pathsMod) {
    try { 
        Import-Module $pathsMod -Force -EA Stop 
        $p = GetPaths $PSScriptRoot
    } catch { 
        # Stille Fehlerbehandlung, da wir im Modul sind
        $p = @{
            root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            cfg = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "config"
            errMod = Join-Path (Split-Path -Parent $PSScriptRoot) "modules\error.psm1"
        }
    }
} else {
    # Fallback ohne Pfadmodul
    $p = @{
        root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        cfg = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "config"
        errMod = Join-Path (Split-Path -Parent $PSScriptRoot) "modules\error.psm1"
    }
}

# Fehlermodul laden, falls verfügbar
if (Test-Path $p.errMod) {
    try { 
        Import-Module $p.errMod -Force -EA Stop 
    } catch { 
        # Stille Fehlerbehandlung, da wir im Modul sind
    }
}

# Schemas für Konfigurationen
$defaultSchemas = @{
    # Schema für settings.json
    "settings" = @{
        Version = "1.0"
        Type = "Object"
        Properties = @{
            Logging = @{
                Type = "Object"
                Properties = @{
                    Enabled = @{
                        Type = "Boolean"
                        Default = $false
                    }
                    Path = @{
                        Type = "String"
                        Default = "temp\logs"
                    }
                    Mode = @{
                        Type = "String"
                        Enum = @("PiM", "PowerShell")
                        Default = "PiM"
                    }
                }
                Required = @("Enabled", "Path")
            }
        }
        Required = @("Logging")
    }
    
    # Schema für user-settings.json
    "user-settings" = @{
        Version = "1.0"
        Type = "Object"
        Properties = @{
            Theme = @{
                Type = "String"
                Enum = @("Default", "Dark", "Light")
                Default = "Default"
            }
            Language = @{
                Type = "String"
                Default = "de-DE"
            }
            AutoUpdate = @{
                Type = "Boolean"
                Default = $true
            }
            LastCheck = @{
                Type = "String"
                Default = (Get-Date).ToString("yyyy-MM-dd")
            }
        }
        Required = @("Theme", "Language", "AutoUpdate")
    }
}

# Werte nach Typ validieren
function ValidateValue {
    param (
        [Parameter(Mandatory)]
        $value,
        
        [Parameter(Mandatory)]
        [hashtable]$schema
    )
    
    # Typ prüfen
    switch ($schema.Type) {
        "Boolean" {
            # Boolean-Wert prüfen
            if ($value -is [bool]) {
                return $value
            }
            
            # Versuche Konvertierung
            if ($value -is [string]) {
                if ($value -eq "true" -or $value -eq "1") { return $true }
                if ($value -eq "false" -or $value -eq "0") { return $false }
            }
            
            # Verwende Standardwert
            return $schema.Default
        }
        "String" {
            # String-Wert prüfen
            if ($value -is [string]) {
                # Enum-Wert prüfen, falls verfügbar
                if ($schema.Enum -and $schema.Enum -notcontains $value) {
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Ungültiger Enumerationswert: $value. Erlaubte Werte: $($schema.Enum -join ", ")" -t "Warning"
                    }
                    return $schema.Default
                }
                return $value
            }
            
            # Versuche Konvertierung
            try {
                return $value.ToString()
            } catch {
                # Verwende Standardwert
                return $schema.Default
            }
        }
        "Number" {
            # Numerischen Wert prüfen
            if ($value -is [int] -or $value -is [double]) {
                # Bereichsprüfung, falls verfügbar
                if ($schema.Minimum -ne $null -and $value -lt $schema.Minimum) {
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Wert zu klein: $value. Minimum: $($schema.Minimum)" -t "Warning"
                    }
                    return $schema.Default
                }
                if ($schema.Maximum -ne $null -and $value -gt $schema.Maximum) {
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Wert zu groß: $value. Maximum: $($schema.Maximum)" -t "Warning"
                    }
                    return $schema.Default
                }
                return $value
            }
            
            # Versuche Konvertierung
            if ($value -is [string] -and $value -match "^\d+(\.\d+)?$") {
                $num = [double]::Parse($value)
                # Bereichsprüfung, falls verfügbar
                if ($schema.Minimum -ne $null -and $num -lt $schema.Minimum) { return $schema.Default }
                if ($schema.Maximum -ne $null -and $num -gt $schema.Maximum) { return $schema.Default }
                return $num
            }
            
            # Verwende Standardwert
            return $schema.Default
        }
        "Object" {
            # Objekt-Wert prüfen
            if ($value -is [PSCustomObject] -or $value -is [hashtable]) {
                return $value
            }
            
            # Verwende Standardwert (leeres Objekt, wenn kein Default)
            return $schema.Default ?? @{}
        }
        "Array" {
            # Array-Wert prüfen
            if ($value -is [array]) {
                return $value
            }
            
            # Einzelwert in Array umwandeln
            if ($value -ne $null) {
                return @($value)
            }
            
            # Verwende Standardwert (leeres Array, wenn kein Default)
            return $schema.Default ?? @()
        }
        default {
            # Unbekannter Typ, Wert unverändert zurückgeben
            return $value
        }
    }
}

# Konfiguration gegen Schema validieren und reparieren
function ValidateConfig {
    param (
        [Parameter(Mandatory)]
        $config,
        
        [Parameter(Mandatory)]
        [hashtable]$schema,
        
        [string]$path = ""
    )
    
    # Wenn Config null ist, erstelle leeres Objekt
    if ($null -eq $config) {
        $config = [PSCustomObject]@{}
    }
    
    # Objekt-Schema validieren
    if ($schema.Type -eq "Object") {
        # Erforderliche Eigenschaften prüfen und hinzufügen, falls fehlend
        foreach ($prop in $schema.Required) {
            $propPath = $path ? "$path.$prop" : $prop
            
            if (!(Get-Member -InputObject $config -Name $prop -MemberType Properties)) {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Erforderliche Eigenschaft fehlt: $propPath" -t "Warning"
                }
                
                # Eigenschaft mit Standardwert hinzufügen
                $propSchema = $schema.Properties[$prop]
                $defaultValue = if ($propSchema.Type -eq "Object") {
                    # Rekursiv Objekt erstellen
                    $obj = [PSCustomObject]@{}
                    foreach ($subProp in $propSchema.Required) {
                        $subSchema = $propSchema.Properties[$subProp]
                        $obj | Add-Member -MemberType NoteProperty -Name $subProp -Value $subSchema.Default
                    }
                    $obj
                } else {
                    $propSchema.Default
                }
                
                $config | Add-Member -MemberType NoteProperty -Name $prop -Value $defaultValue
            }
        }
        
        # Alle vorhandenen Eigenschaften validieren
        foreach ($prop in $schema.Properties.Keys) {
            $propPath = $path ? "$path.$prop" : $prop
            $propSchema = $schema.Properties[$prop]
            
            if (Get-Member -InputObject $config -Name $prop -MemberType Properties) {
                $propValue = $config.$prop
                
                if ($propSchema.Type -eq "Object") {
                    # Rekursiv Objekt validieren
                    $config.$prop = ValidateConfig -config $propValue -schema $propSchema -path $propPath
                } else {
                    # Wert validieren
                    $validValue = ValidateValue -value $propValue -schema $propSchema
                    if ($validValue -ne $propValue) {
                        if (Get-Command Err -EA SilentlyContinue) {
                            Err "Eigenschaft '$propPath' repariert: $propValue -> $validValue" -t "Warning"
                        }
                        $config.$prop = $validValue
                    }
                }
            } elseif ($schema.Required -contains $prop) {
                # Fehlende, erforderliche Eigenschaft hinzufügen
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Erforderliche Eigenschaft fehlt: $propPath" -t "Warning"
                }
                
                $config | Add-Member -MemberType NoteProperty -Name $prop -Value $propSchema.Default
            }
        }
    }
    
    return $config
}

# Hauptfunktion: Konfiguration laden mit Schema-Validierung
function GetConfig {
    param (
        [Parameter(Mandatory)]
        [string]$name,
        
        [hashtable]$schema = $null,
        
        [switch]$noValidate,
        
        [switch]$noCreate
    )
    
    # Dateiname erzeugen
    $fileName = if ($name -match "\.json$") { $name } else { "$name.json" }
    $filePath = Join-Path $p.cfg $fileName
    
    # Schema auswählen
    if (!$schema) {
        $schemaName = $name -replace "\.json$", ""
        $schema = $defaultSchemas[$schemaName]
        
        if (!$schema) {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Kein Schema für '$name' gefunden. Keine Validierung möglich." -t "Warning"
            }
            $noValidate = $true
        }
    }
    
    # Prüfen, ob Datei existiert
    if (!(Test-Path $filePath)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Konfigurationsdatei nicht gefunden: $filePath" -t "Warning"
        }
        
        # Config-Verzeichnis prüfen/erstellen
        if (!(Test-Path $p.cfg) -and !$noCreate) {
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    New-Item -Path $p.cfg -ItemType Directory -Force >$null
                } -m "Konfigurationsverzeichnis konnte nicht erstellt werden" -t "Error"
            } else {
                try {
                    New-Item -Path $p.cfg -ItemType Directory -Force >$null
                } catch {
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Konfigurationsverzeichnis konnte nicht erstellt werden" $_ "Error"
                    }
                }
            }
        }
        
        # Bei bestimmten Dateien alternativ Initialize-DefaultSettings.ps1 versuchen
        $initScript = Join-Path $p.cfg "Initialize-DefaultSettings.ps1"
        if (!$noCreate -and (Test-Path $initScript) -and 
            ($name -eq "settings" -or $name -eq "settings.json" -or
             $name -eq "user-settings" -or $name -eq "user-settings.json")) {
            
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Versuche Initialisierung mit Initialize-DefaultSettings.ps1..." -t "Info"
            }
            
            # Skript ausführen
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    & $initScript
                } -m "Initialisierungsskript konnte nicht ausgeführt werden" -t "Warning"
            } else {
                try {
                    & $initScript
                } catch {
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Initialisierungsskript konnte nicht ausgeführt werden" $_ "Warning"
                    }
                }
            }
            
            # Nochmals prüfen, ob Datei jetzt existiert
            if (Test-Path $filePath) {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Konfigurationsdatei wurde erstellt: $filePath" -t "Info"
                }
            }
        }
        
        # Wenn Datei immer noch nicht existiert und wir ein Schema haben
        if (!(Test-Path $filePath) -and $schema -and !$noCreate) {
            # Standardkonfiguration aus Schema erstellen
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Erstelle Standardkonfiguration aus Schema..." -t "Info"
            }
            
            $defaultConfig = CreateFromSchema -schema $schema
            
            # Speichern
            if (Get-Command SafeOp -EA SilentlyContinue) {
                SafeOp {
                    $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content $filePath
                } -m "Standardkonfiguration konnte nicht gespeichert werden" -t "Error"
            } else {
                try {
                    $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content $filePath
                } catch {
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Standardkonfiguration konnte nicht gespeichert werden" $_ "Error"
                    }
                }
            }
        }
        
        # Wenn die Datei immer noch nicht existiert oder nicht erstellt werden sollte
        if (!(Test-Path $filePath) -or $noCreate) {
            # Fallback: leeres Objekt oder Schema-Default
            if ($noValidate -or !$schema) {
                return [PSCustomObject]@{}
            } else {
                # Erstelle Default-Objekt aus Schema
                return CreateFromSchema -schema $schema
            }
        }
    }
    
    # Konfiguration laden
    $config = $null
    
    if (Get-Command SafeOp -EA SilentlyContinue) {
        $config = SafeOp {
            Get-Content $filePath -Raw | ConvertFrom-Json
        } -m "Konfiguration konnte nicht geladen werden" -def $null
    } else {
        try {
            $config = Get-Content $filePath -Raw | ConvertFrom-Json
        } catch {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Konfiguration konnte nicht geladen werden" $_ "Error"
            }
            $config = $null
        }
    }
    
    # Wenn Config null ist, leeres Objekt verwenden
    if ($null -eq $config) {
        $config = [PSCustomObject]@{}
    }
    
    # Validieren und reparieren, falls Schema vorhanden und Validierung gewünscht
    if ($schema -and !$noValidate) {
        $config = ValidateConfig -config $config -schema $schema
        
        # Speichern der reparierten Konfiguration
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                $config | ConvertTo-Json -Depth 10 | Set-Content $filePath
            } -m "Reparierte Konfiguration konnte nicht gespeichert werden" -t "Warning"
        } else {
            try {
                $config | ConvertTo-Json -Depth 10 | Set-Content $filePath
            } catch {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Reparierte Konfiguration konnte nicht gespeichert werden" $_ "Warning"
                }
            }
        }
    }
    
    return $config
}

# Konfiguration speichern
function SaveConfig {
    param (
        [Parameter(Mandatory)]
        [string]$name,
        
        [Parameter(Mandatory)]
        $config,
        
        [hashtable]$schema = $null,
        
        [switch]$noValidate
    )
    
    # Dateiname erzeugen
    $fileName = if ($name -match "\.json$") { $name } else { "$name.json" }
    $filePath = Join-Path $p.cfg $fileName
    
    # Schema auswählen
    if (!$schema) {
        $schemaName = $name -replace "\.json$", ""
        $schema = $defaultSchemas[$schemaName]
        
        if (!$schema) {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Kein Schema für '$name' gefunden. Keine Validierung möglich." -t "Warning"
            }
            $noValidate = $true
        }
    }
    
    # Validieren und reparieren, falls Schema vorhanden und Validierung gewünscht
    if ($schema -and !$noValidate) {
        $config = ValidateConfig -config $config -schema $schema
    }
    
    # Config-Verzeichnis prüfen/erstellen
    if (!(Test-Path $p.cfg)) {
        if (Get-Command SafeOp -EA SilentlyContinue) {
            SafeOp {
                New-Item -Path $p.cfg -ItemType Directory -Force >$null
            } -m "Konfigurationsverzeichnis konnte nicht erstellt werden" -t "Error"
        } else {
            try {
                New-Item -Path $p.cfg -ItemType Directory -Force >$null
            } catch {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Konfigurationsverzeichnis konnte nicht erstellt werden" $_ "Error"
                    return $false
                }
            }
        }
    }
    
    # Konfiguration speichern
    if (Get-Command SafeOp -EA SilentlyContinue) {
        return SafeOp {
            $config | ConvertTo-Json -Depth 10 | Set-Content $filePath
            return $true
        } -m "Konfiguration konnte nicht gespeichert werden" -def $false
    } else {
        try {
            $config | ConvertTo-Json -Depth 10 | Set-Content $filePath
            return $true
        } catch {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Konfiguration konnte nicht gespeichert werden" $_ "Error"
            }
            return $false
        }
    }
}

# Standardkonfiguration aus Schema erstellen
function CreateFromSchema {
    param (
        [Parameter(Mandatory)]
        [hashtable]$schema
    )
    
    # Objekt erstellen basierend auf Schema-Typ
    switch ($schema.Type) {
        "Object" {
            $obj = [PSCustomObject]@{}
            
            # Eigenschaften hinzufügen
            foreach ($prop in $schema.Properties.Keys) {
                $propSchema = $schema.Properties[$prop]
                
                if ($propSchema.Type -eq "Object") {
                    # Rekursiv Objekt erstellen
                    $value = CreateFromSchema -schema $propSchema
                } else {
                    # Standardwert verwenden
                    $value = $propSchema.Default
                }
                
                $obj | Add-Member -MemberType NoteProperty -Name $prop -Value $value
            }
            
            return $obj
        }
        "Array" {
            # Standardwert oder leeres Array
            return $schema.Default ?? @()
        }
        default {
            # Standardwert oder null
            return $schema.Default
        }
    }
}

# Schema für eine Konfiguration festlegen/ändern
function SetSchema {
    param (
        [Parameter(Mandatory)]
        [string]$name,
        
        [Parameter(Mandatory)]
        [hashtable]$schema
    )
    
    $schemaName = $name -replace "\.json$", ""
    $defaultSchemas[$schemaName] = $schema
    
    return $true
}

# Verfügbare Schemas auflisten
function GetSchemas {
    return $defaultSchemas.Keys
}

# Aktuelles Schema abfragen
function GetSchema {
    param (
        [Parameter(Mandatory)]
        [string]$name
    )
    
    $schemaName = $name -replace "\.json$", ""
    return $defaultSchemas[$schemaName]
}

# Funktionen exportieren
Export-ModuleMember -Function GetConfig, SaveConfig, GetSchemas, GetSchema, SetSchema