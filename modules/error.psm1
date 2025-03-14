# error.psm1 - Zentrale Fehlerbehandlung für PiM-Manager
# Speicherort: modules\error.psm1

function Err {
    param (
        [Parameter(Mandatory)]
        [string]$m,
        
        [System.Management.Automation.ErrorRecord]$e,
        
        [ValidateSet("Info", "Warning", "Error", "Fatal")]
        [string]$t = "Error",
        
        [switch]$exit
    )
    
    # Skript-Kontext erfassen
    $src = try { Split-Path -Leaf $MyInvocation.ScriptName } catch { "unknown" }
    $ln = try { $MyInvocation.ScriptLineNumber } catch { 0 }
    
    # Fehlermeldung zusammensetzen
    $msg = if ($e) { "$m - $($e.Exception.Message)" } else { $m }
    
    # Logging-Funktion nutzen wenn vorhanden
    if (Get-Command Log -EA SilentlyContinue) {
        Log $msg $t
    } else {
        # Farbe basierend auf Typ
        $c = switch ($t) {
            "Info" { "Gray" }
            "Warning" { "Yellow" }
            "Error" { "Red" }
            "Fatal" { "DarkRed" }
            default { "White" }
        }
        
        # Zeitstempel
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Ausgabe
        Write-Host "[$ts] [$src:$ln] [$t] $msg" -ForegroundColor $c
    }
    
    # Bei fatal error: Skript beenden
    if ($t -eq "Fatal" -or $exit) {
        Write-Host "Skript wird beendet aufgrund eines kritischen Fehlers." -ForegroundColor Red
        exit 1
    }
}

# Hilfsfunktion für try-catch-Blöcke
function SafeOp {
    param (
        [Parameter(Mandatory)]
        [scriptblock]$sb,
        
        [string]$m = "Operation fehlgeschlagen",
        
        [string]$t = "Error",
        
        [object]$def = $null
    )
    
    try {
        return & $sb
    } catch {
        Err -m $m -e $_ -t $t
        return $def
    }
}

# Exportiere Funktionen
Export-ModuleMember -Function Err, SafeOp