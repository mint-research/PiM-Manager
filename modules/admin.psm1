# admin.psm1 - Modul zur Prüfung von Administratorrechten (Tokenoptimiert)
# Speicherort: modules\admin.psm1

# Benötigten .NET-Typ für Sicherheitsidentitäten laden
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public class AdminHelper {
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetTokenInformation(IntPtr TokenHandle, uint TokenInformationClass, IntPtr TokenInformation, uint TokenInformationLength, out uint ReturnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    private const uint TOKEN_QUERY = 0x0008;
    private const uint TokenElevation = 20;

    public static bool IsElevated() {
        IntPtr hToken = IntPtr.Zero;
        IntPtr hProcess = GetCurrentProcess();
        
        try {
            if (!OpenProcessToken(hProcess, TOKEN_QUERY, out hToken)) {
                return false;
            }
            
            // TokenElevation ist 4 Bytes (Int32)
            IntPtr elevationPtr = Marshal.AllocHGlobal(4);
            try {
                uint returnLength = 0;
                if (!GetTokenInformation(hToken, TokenElevation, elevationPtr, 4, out returnLength)) {
                    return false;
                }
                
                return Marshal.ReadInt32(elevationPtr) != 0;
            }
            finally {
                Marshal.FreeHGlobal(elevationPtr);
            }
        }
        finally {
            if (hToken != IntPtr.Zero) {
                CloseHandle(hToken);
            }
        }
    }
}
"@

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
            errMod = Join-Path (Split-Path -Parent $PSScriptRoot) "modules\error.psm1"
        }
    }
} else {
    # Fallback ohne Pfadmodul
    $p = @{
        root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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

# Prüfen, ob PowerShell als Administrator ausgeführt wird
function IsAdmin {
    param (
        [switch]$checkScript,
        [string]$script = $PSCommandPath
    )
    
    # Tatsächliche Windows-Berechtigungsprüfung
    $elevated = $false
    
    # Methode 1: .NET WindowsIdentity (einfach, aber nicht so detailliert wie Methode 2)
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        if (Get-Command Err -EA SilentlyContinue) {
            Err "Fehler bei WindowsIdentity-Berechtigungsprüfung" $_ "Warning"
        } else {
            Write-Host "Fehler bei WindowsIdentity-Berechtigungsprüfung: $_" -ForegroundColor Yellow
        }
        
        # Methode 2: Unsere API-basierte Methode als Fallback
        try {
            $elevated = [AdminHelper]::IsElevated()
        } catch {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Fehler bei API-basierter Berechtigungsprüfung" $_ "Warning"
            } else {
                Write-Host "Fehler bei API-basierter Berechtigungsprüfung: $_" -ForegroundColor Yellow
            }
            
            # Letzter Fallback: #Requires-Trick mit temporärem Skript
            try {
                $tempFile = Join-Path $env:TEMP "PiM_Admin_Check_$([Guid]::NewGuid().ToString()).ps1"
                "#Requires -RunAsAdministrator`nreturn `$true" | Set-Content $tempFile
                $elevated = & $tempFile
                Remove-Item $tempFile -Force -EA SilentlyContinue
            } catch {
                # Wir gehen davon aus, dass keine Admin-Rechte vorliegen, wenn der #Requires-Test fehlschlägt
                $elevated = $false
            }
        }
    }
    
    # Optional: Zusätzlich Skriptpfad prüfen für "Admin-Bereich" (für Abwärtskompatibilität)
    if ($checkScript -and $script) {
        $inAdminArea = $false
        
        if (Get-Command IsAdminScript -EA SilentlyContinue) {
            # Pfadmodul verfügbar
            $inAdminArea = IsAdminScript $script
        } else {
            # Pfadmodul nicht verfügbar, eigene Prüfung
            $inAdminArea = $script -match "\\scripts\\admin\\" -or $script -match "\\admin\\"
        }
        
        # Warnung ausgeben, wenn Diskrepanz vorliegt
        if ($elevated -and !$inAdminArea) {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Skript wird mit Administratorrechten ausgeführt, befindet sich aber nicht im Admin-Bereich" -t "Warning"
            } else {
                Write-Host "Warnung: Skript wird mit Administratorrechten ausgeführt, befindet sich aber nicht im Admin-Bereich" -ForegroundColor Yellow
            }
        } elseif (!$elevated -and $inAdminArea) {
            if (Get-Command Err -EA SilentlyContinue) {
                Err "Skript befindet sich im Admin-Bereich, wird aber ohne Administratorrechte ausgeführt" -t "Warning"
            } else {
                Write-Host "Warnung: Skript befindet sich im Admin-Bereich, wird aber ohne Administratorrechte ausgeführt" -ForegroundColor Yellow
            }
        }
    }
    
    return $elevated
}

# Erzwingen von Administratorrechten
function RequireAdmin {
    param (
        [string]$message = "Dieses Skript erfordert Administratorrechte.",
        [switch]$exit
    )
    
    if (!(IsAdmin)) {
        if (Get-Command Err -EA SilentlyContinue) {
            Err $message -t "Error"
        } else {
            Write-Host $message -ForegroundColor Red
        }
        
        # Optional: PowerShell neu starten mit Admin-Rechten
        $restart = Read-Host "PowerShell mit Administratorrechten neu starten? (j/n)"
        
        if ($restart -eq "j") {
            $currentScript = $MyInvocation.MyCommand.Definition
            
            if ([string]::IsNullOrEmpty($currentScript) -or !(Test-Path $currentScript)) {
                $currentScript = $PSCommandPath
            }
            
            if (Test-Path $currentScript) {
                try {
                    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$currentScript`"" -Verb RunAs
                } catch {
                    if (Get-Command Err -EA SilentlyContinue) {
                        Err "Fehler beim Starten mit Administratorrechten" $_ "Error"
                    } else {
                        Write-Host "Fehler beim Starten mit Administratorrechten: $_" -ForegroundColor Red
                    }
                }
            } else {
                if (Get-Command Err -EA SilentlyContinue) {
                    Err "Skriptpfad konnte nicht ermittelt werden" -t "Error"
                } else {
                    Write-Host "Skriptpfad konnte nicht ermittelt werden" -ForegroundColor Red
                }
            }
        }
        
        if ($exit) {
            exit 1
        }
        
        return $false
    }
    
    return $true
}

# Funktionen exportieren
Export-ModuleMember -Function IsAdmin, RequireAdmin