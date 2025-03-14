# PiM-Manager Konfigurationsdateien

Dieses Dokument beschreibt die Konfigurationsdateien, die vom PiM-Manager verwendet werden.

## Überblick

Alle Konfigurationsdateien werden im `config/`-Verzeichnis gespeichert und haben das JSON-Format. Diese Dateien werden vom Git-Repository ausgeschlossen, um lokale Einstellungen zu ermöglichen und sensitive Daten zu schützen.

## Automatische Erstellung

Die Konfigurationsdateien werden automatisch erstellt, wenn sie nicht existieren. Dies geschieht:

1. Durch einzelne Skripte, wenn sie auf Konfigurationsdateien zugreifen
2. Durch das zentrale Skript `scripts/admin/Initialize-DefaultSettings.ps1`, das bei einer neuen Installation ausgeführt werden sollte

## Standardkonfigurationsdateien

### settings.json

Enthält globale Einstellungen für den PiM-Manager, insbesondere für das Logging.

```json
{
  "Logging": {
    "Enabled": false,
    "Path": "docs\\logs",
    "Mode": "PiM"
  }
}
```

- `Enabled`: Aktiviert oder deaktiviert das Logging
- `Path`: Relativer Pfad zum Logging-Verzeichnis
- `Mode`: Logging-Modus ("PiM" oder "PowerShell")

### user-settings.json

Enthält benutzerspezifische Einstellungen.

```json
{
  "Theme": "Default",
  "Language": "de-DE",
  "AutoUpdate": true,
  "LastCheck": "2025-03-14"
}
```

## Zurücksetzen auf Standardwerte

Um alle Konfigurationsdateien auf ihre Standardwerte zurückzusetzen, führen Sie das Skript `scripts/admin/Initialize-DefaultSettings.ps1` aus und bestätigen Sie die Anfrage zum Zurücksetzen.

## Hinzufügen neuer Konfigurationsdateien

Wenn Sie eine neue Konfigurationsdatei hinzufügen:

1. Fügen Sie sie zum Skript `Initialize-DefaultSettings.ps1` hinzu
2. Dokumentieren Sie sie in dieser README-Datei
3. Stellen Sie sicher, dass alle Skripte, die darauf zugreifen, die Datei bei Bedarf erstellen können
4. Prüfen Sie, ob die Datei in `.gitignore` ausgeschlossen werden sollte