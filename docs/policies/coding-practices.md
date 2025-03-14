# PiM-Manager: Tokeneffiziente Entwicklung mit Claude 3.7

## Grundprinzipien für jede Anfrage

1. **Zusammenfasse die Aufgabe** mit eigenen Worten
2. **Stelle gezielte Fragen** zu fehlenden Details
3. **Erstelle Beispiel-Outputs oder Vorschauen** vor der Code-Implementierung
4. **Entwickle schrittweise** - ein Skript oder Schritt auf einmal, dann warte auf Bestätigung
5. **Gehe von Entwicklerkenntnissen 1/10 aus** - alles explizit erklären
6. **Mache unmissverständlich klar**, welche Änderungen wo vorzunehmen sind

## Aktiv nachzufragende Aspekte

**Bei jeder Codeentwicklung diese Informationen einholen:**

- "Welche **konkreten Funktionen** soll das Skript enthalten?"
- "In welchen **Anwendungsfällen** wird es verwendet?"
- "Wie soll die **Benutzerinteraktion** aussehen? (Menü/Kommandozeile)"
- "Sind **Admin-Rechte** erforderlich?"
- "Mit welchen **Modulen** muss dieser Code interagieren?"
- "Wie soll die **Fehlerbehandlung** erfolgen?"
- "Welche **Konfigurationseinstellungen** sollen gespeichert werden?"

## PowerShell-Optimierungen

### Token-Sparmuster für PowerShell (maximale Effizienz)

✅ **Funktionsnamen kürzen**: `Write-Log` → `Log`, `Get-Config` → `GetCfg`  
✅ **Parameter vereinfachen**: `$message` → `$m`, `$configFile` → `$f`  
✅ **Operators verwenden**: `>>` statt `Out-File -Append`, `>$null` statt `Out-Null`  
✅ **Aliases nutzen**: `cls` statt `Clear-Host`, `?` statt `Where-Object`  
✅ **Hashtables für if-else-Ketten**: `$actions[$choice].Invoke()` statt mehrerer if-Blöcke  
✅ **Verschachtelte Ausdrücke**: `(cmd1).Method(cmd2)` statt separate Zeilen  
✅ **Einzeilige Funktionen**: `function Get($k) { $cfg[$k] }` statt Blockform  
✅ **Pfadberechnungen vereinfachen**: Schlanke Expressions für Pfade entwickeln

### Beispiel: Logging-Funktion

**Vorher (ineffizient):**
```powershell
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$message,
        [string]$logFile = ".\logs\pim-log.txt"
    )
    
    # Ensure directory exists
    $logDir = Split-Path -Path $logFile -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append -FilePath $logFile
    Write-Host "$timestamp - $message" -ForegroundColor Gray
}
```

**Nachher (tokeneffizient):**
```powershell
function Log($m, $f=".\logs\pim-log.txt") {
    $d = Split-Path $f -Parent
    if(!(Test-Path $d)) { mkdir $d -Force >$null }
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$t - $m" | Add-Content $f
    Write-Host "$t - $m" -ForegroundColor Gray
}
```

## Python-Optimierungen

### Token-Sparmuster für Python (maximale Effizienz)

✅ **List/Dict Comprehensions**: `[x for x in items if condition]` statt for-Schleifen  
✅ **Kürzere Namen**: `config` → `cfg`, `message` → `msg`, `settings` → `sets`  
✅ **F-Strings nutzen**: `f"{var} text"` statt `.format()` oder `%`  
✅ **Ternary-Operatoren**: `x = a if cond else b` statt if-else Blöcke  
✅ **Lambda-Funktionen**: `lambda x: x*2` für kleine Funktionen  
✅ **Methoden verketten**: `data.strip().split(',')[0].lower()`  
✅ **Mehrfach-Zuweisungen**: `a, b, c = 1, 2, 3` oder `a = b = c = 0`  
✅ **Dict-Operationen optimieren**: `.setdefault()`, `.get()` mit Default-Wert

### Beispiel: Config-Manager

**Vorher (ineffizient):**
```python
class ConfigManager:
    def __init__(self, config_file="./config/settings.json"):
        self.config_file = config_file
        self.config = self.load_config()
    
    def load_config(self):
        """Load configuration from file or create default if not exists."""
        if not os.path.exists(self.config_file):
            print("Configuration file not found. Creating default...")
            
            # Create default configuration
            default_config = {
                "logging": {
                    "enabled": False,
                    "path": "docs/logs",
                    "level": "INFO"
                },
                "updates": {
                    "auto_update": True,
                    "check_frequency": "daily",
                    "last_check": datetime.now().strftime("%Y-%m-%d")
                }
            }
            
            # Create directory if it doesn't exist
            config_dir = os.path.dirname(self.config_file)
            if not os.path.exists(config_dir):
                os.makedirs(config_dir, exist_ok=True)
            
            # Write default config to file
            with open(self.config_file, 'w') as f:
                json.dump(default_config, f, indent=4)
            
            return default_config
        else:
            try:
                with open(self.config_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Error loading configuration: {e}")
                return {}
```

**Nachher (tokeneffizient):**
```python
class Cfg:
    def __init__(self, f="./config/settings.json"):
        self.f = f
        self.data = self._load()
    
    def _load(self):
        if not os.path.exists(self.f):
            cfg = {
                "log": {"on": False, "path": "docs/logs", "level": "INFO"},
                "updates": {"auto": True, "freq": "daily", 
                           "last": datetime.now().strftime("%Y-%m-%d")}
            }
            os.makedirs(os.path.dirname(self.f), exist_ok=True)
            with open(self.f, 'w') as f: json.dump(cfg, f, indent=2)
            return cfg
        
        try:
            with open(self.f) as f: return json.load(f)
        except Exception as e:
            print(f"Config error: {e}")
            return {}
```

## PiM-Manager Standardmuster

### Standardisierte Pfadberechnung
```powershell
if ($PSScriptRoot -match "admin$") {
    $rootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $isAdmin = $true
} else {
    $rootPath = Split-Path -Parent $PSScriptRoot
    $isAdmin = $false
}
```

### Konsistenter Modul-Import
```powershell
$modPath = Join-Path -Path $rootPath -ChildPath "modules\ux.psm1"
if (Test-Path $modPath) {
    try { Import-Module $modPath -Force -EA Stop }
    catch { Write-Host "Modul-Fehler: $_" -ForegroundColor Red }
}
```

### Einheitliches Konfigurationsmanagement
```powershell
$cfgPath = Join-Path $rootPath "config"
$cfgFile = Join-Path $cfgPath "settings.json"
if (Test-Path $cfgFile) {
    try { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json }
    catch { $cfg = @{} }  # Default-Werte bei Bedarf setzen
}
```

### Optimierte Menüstruktur
```powershell
$opts = @{
    "1" = @{Display = "[option] Option 1"; Action = {OptFunc1}}
    "2" = @{Display = "[option] Option 2"; Action = {OptFunc2}}
}

if (Get-Command Show-ScriptMenu -EA SilentlyContinue) {
    Show-ScriptMenu -title $title -mode $mode -options $opts -enableBack -enableExit
} else {
    # Kompakte Fallback-Implementation
}
```

## Checkliste für Entwicklungsphasen

### Vor der Entwicklung
- [ ] Kernfunktionalität geklärt
- [ ] Funktionale Grenzen definiert
- [ ] Modulabhängigkeiten identifiziert
- [ ] Erwartetes Verhalten beschrieben
- [ ] Besondere Anforderungen spezifiziert

### Während der Entwicklung
- [ ] PiM-Manager-Strukturen übernehmen
- [ ] Nur relevante Teilfunktionen implementieren
- [ ] Bei komplexen Funktionen Bestätigungen einholen
- [ ] Fehlerbehandlung und Logging integrieren
- [ ] Konsistente Formatierung und Namenskonventionen

### Nach der Entwicklung
- [ ] Funktionsüberblick geben
- [ ] Erweiterungsoptionen aufzeigen
- [ ] Abhängigkeiten hervorheben
- [ ] Einschränkungen erwähnen
- [ ] Bestätigung einholen

## Zielkriterien für optimierten Code

- **30-50% Token-Reduktion** im Vergleich zum Original
- **Volle Funktionalität** erhalten (kein Funktionsverlust)
- **Lesbarkeit** bewahren (kein kryptischer Code)
- **Debugging-Fähigkeit** bewahren (nachvollziehbare Fehler)
- **Konsistenz** mit dem PiM-Manager-Codebase sicherstellen
- **Wartbarkeit** nicht kompromittieren