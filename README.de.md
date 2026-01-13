# Docker-Image zum Erstellen von restic und rclone mit Windows 7-Unterstützung

**[English](README.md) | [Русский](README.ru.md)**

## Beschreibung

Eigenständiges Docker-Image zur Cross-Kompilierung von [restic](https://restic.net/) und [rclone](https://rclone.org/) mit **Windows 7 / Windows Server 2008 R2**-Unterstützung.

### Problem

Ab Go 1.21 wurde die offizielle Windows 7-Unterstützung eingestellt. Mit Standard-Go 1.21+ erstellte Binärdateien funktionieren nicht unter Windows 7.

### Lösung

Dieses Image verwendet [XTLS/go-win7](https://github.com/XTLS/go-win7) — einen Go-Fork mit Patches zur Wiederherstellung der Windows 7-Kompatibilität.

### Funktionen

- **Eigenständig**: Kann in jedem Verzeichnis platziert werden, muss nicht im Quellbaum liegen
- **Automatischer Download**: Wenn Quellen nicht gefunden werden, werden sie automatisch von GitHub heruntergeladen
- **Alles inklusive**: Alles Notwendige ist im Image enthalten
- **Multi-Projekt**: Unterstützt sowohl restic als auch rclone

## Schnellstart

### Option 1: Vollautomatisch (lädt Quellen selbst herunter)

```bash
# Build-Verzeichnis erstellen
mkdir win7-build && cd win7-build

# Dockerfile und build.sh hierher kopieren (oder herunterladen)
# ...

# Image erstellen
docker build -t win7-builder .

# Ausführen (lädt Quellen herunter und baut)
# -v win7-go-cache:/go — behält Go-Modul-Cache zwischen Ausführungen
docker run --rm \
    -v $(pwd):/workspace \
    -v win7-go-cache:/go \
    win7-builder
```

Ergebnisse erscheinen in `./output/`.

### Option 2: Mit vorhandenen Quellen

```bash
mkdir win7-build && cd win7-build

# Quellen holen
git clone https://github.com/restic/restic.git
git clone https://github.com/rclone/rclone.git

# Image erstellen
docker build -t win7-builder .

# Ausführen
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

### Option 3: Quellen an anderem Ort

```bash
docker run --rm \
    -v /pfad/zu/restic/quellen:/workspace/restic:ro \
    -v /pfad/zu/rclone/quellen:/workspace/rclone:ro \
    -v $(pwd)/output:/workspace/output \
    win7-builder all:all
```

## Verwendung

### Befehle (Neues Format: projekt:arch)

| Befehl | Beschreibung |
|--------|--------------|
| `restic:all` | restic für Windows 64-Bit und 32-Bit erstellen |
| `restic:amd64` | restic nur für Windows 64-Bit erstellen |
| `restic:386` | restic nur für Windows 32-Bit erstellen |
| `rclone:all` | rclone für Windows 64-Bit und 32-Bit erstellen |
| `rclone:amd64` | rclone nur für Windows 64-Bit erstellen |
| `rclone:386` | rclone nur für Windows 32-Bit erstellen |
| `all:all` | Alles erstellen (restic + rclone, beide Architekturen) |
| `all:amd64` | Alles nur für 64-Bit erstellen |
| `help` | Hilfe anzeigen |

### Befehle (Legacy-Format: nur restic)

| Befehl | Beschreibung |
|--------|--------------|
| `all` | restic für Windows 64-Bit und 32-Bit erstellen (Standard) |
| `amd64` | Nur Windows 64-Bit |
| `386` | Nur Windows 32-Bit |
| `linux` | Linux 64-Bit |

### Beispiele

```bash
# restic für beide Windows-Architekturen erstellen (Standard)
docker run --rm -v $(pwd):/workspace win7-builder

# restic nur für 64-Bit erstellen
docker run --rm -v $(pwd):/workspace win7-builder restic:amd64

# rclone für beide Windows-Architekturen erstellen
docker run --rm -v $(pwd):/workspace win7-builder rclone:all

# Alles erstellen
docker run --rm -v $(pwd):/workspace win7-builder all:all

# Mehrere spezifische Ziele erstellen
docker run --rm -v $(pwd):/workspace win7-builder restic:amd64 rclone:amd64
```

### Interaktiver Modus

```bash
docker run --rm -it \
    -v $(pwd):/workspace \
    --entrypoint /bin/bash \
    win7-builder
```

## Quellerkennungslogik

Das Skript sucht Quellen in folgender Reihenfolge:

1. **Im /workspace-Stammverzeichnis** — wenn das gemountete Verzeichnis selbst das Projekt-Repository ist
2. **In Unterverzeichnissen** — `restic/`, `rclone/`, `*-master/`, `*-main/`, `src/`, `source/`
3. **In allen Unterverzeichnissen der ersten Ebene** — wenn das Verzeichnis einen anderen Namen hat

### Wie Projekte erkannt werden

- **restic**: Vorhandensein von `go.mod` mit `module github.com/restic/restic`, oder `VERSION`-Datei + `cmd/restic/`-Verzeichnis
- **rclone**: Vorhandensein von `go.mod` mit `module github.com/rclone/rclone`, oder `VERSION`-Datei + `cmd/rclone/`-Verzeichnis

### Wenn Quellen nicht gefunden werden

Das Skript versucht herunterzuladen:

1. **git clone** von GitHub
2. **Archiv** von GitHub-Releases

Wenn beide Methoden fehlschlagen, werden Anweisungen angezeigt.

## Struktur

```
docker-win7-build/
├── Dockerfile      # Image basierend auf debian:bookworm-slim
├── build.sh        # Build-Skript mit automatischem Download
└── README.md       # Diese Dokumentation

Nach dem Build:
/workspace/
├── restic/         # restic-Quellen (heruntergeladen oder gemountet)
├── rclone/         # rclone-Quellen (heruntergeladen oder gemountet)
└── output/         # Build-Ergebnisse
    ├── restic-v0.18.1-win7-64.exe
    ├── restic-v0.18.1-win7-32.exe
    ├── rclone-v1.69.0-win7-64.exe
    └── rclone-v1.69.0-win7-32.exe
```

Dateinamenformat: `{projekt}-{version}-win7-{arch}.exe`

## Go-Modul-Caching

Um nachfolgende Builds zu beschleunigen, verwenden Sie ein benanntes Volume für den Go-Cache:

```bash
# Erster Build (~2-5 Minuten) — lädt alle Abhängigkeiten herunter
docker run --rm -v $(pwd):/workspace -v win7-go-cache:/go win7-builder all:all

# Nachfolgende Builds (~6-30 Sekunden) — verwendet Cache
docker run --rm -v $(pwd):/workspace -v win7-go-cache:/go win7-builder all:all
```

Ohne das Volume `-v win7-go-cache:/go` werden Abhängigkeiten jedes Mal heruntergeladen.

## Umgebungsvariablen

| Variable | Standard | Beschreibung |
|----------|----------|--------------|
| `WORKSPACE` | `/workspace` | Arbeitsverzeichnis |
| `GOPATH` | `/go` | Go-Cache-Pfad (Volume hier mounten) |
| `RESTIC_VERSION` | *(neuestes Release)* | restic Version (Tag, Branch oder Commit) |
| `RCLONE_VERSION` | *(neuestes Release)* | rclone Version (Tag, Branch oder Commit) |
| `RESTIC_GIT_URL` | `https://github.com/restic/restic.git` | URL für git clone (restic) |
| `RCLONE_GIT_URL` | `https://github.com/rclone/rclone.git` | URL für git clone (rclone) |
| `CGO_ENABLED` | `0` | Statisches Linken |

## Bestimmte Version/Tag erstellen

### Mit Umgebungsvariablen (empfohlen)

```bash
# Bestimmte Versionen erstellen
docker run --rm \
    -v $(pwd):/workspace \
    -v win7-go-cache:/go \
    -e RESTIC_VERSION=v0.17.3 \
    -e RCLONE_VERSION=v1.68.2 \
    win7-builder all:all

# Von einem bestimmten Commit erstellen
docker run --rm \
    -v $(pwd):/workspace \
    -e RESTIC_VERSION=abc1234 \
    win7-builder restic:amd64

# Neueste Versionen erstellen (Standardverhalten)
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

### Mit lokalen Quellen

```bash
# Mit bestimmtem Tag klonen
git clone --branch v0.17.3 --depth 1 https://github.com/restic/restic.git
git clone --branch v1.68.2 --depth 1 https://github.com/rclone/rclone.git

# Erstellen
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

## Kompatibilitätsprüfung

Erstellte Binärdateien sind als Windows 6.01 (Windows 7) kompatibel markiert:

```bash
file output/restic-v0.18.1-win7-64.exe
# PE32+ executable for MS Windows 6.01 (console), x86-64

file output/rclone-v1.69.0-win7-64.exe
# PE32+ executable for MS Windows 6.01 (console), x86-64
```

## Go SDK aktualisieren

Um eine andere Version des gepatchten Go zu verwenden:

```bash
docker build \
    --build-arg GO_WIN7_VERSION=1.25.5 \
    --build-arg GO_WIN7_TAG=patched-1.25.5 \
    -t win7-builder .
```

Verfügbare Versionen: https://github.com/XTLS/go-win7/releases

## Technische Details

- **Basis-Image**: `debian:bookworm-slim`
- **Go-Version**: 1.25.5 (gepatcht für Windows 7)
- **Image-Größe**: ~350 MB
- **Ausgabedateien**: kompatibel mit Windows 7 (PE für Windows 6.01)

## Fehlerbehebung

### "Quellen konnten nicht gefunden oder heruntergeladen werden"

1. Überprüfen Sie den Internetzugang im Container
2. Laden Sie Quellen manuell herunter:
   ```bash
   git clone https://github.com/restic/restic.git
   git clone https://github.com/rclone/rclone.git
   ```
3. Mounten Sie das Quellverzeichnis

### "Permission denied" beim Schreiben der Ergebnisse

Stellen Sie sicher, dass das Verzeichnis `/workspace/output` beschreibbar ist:
```bash
mkdir -p output && chmod 777 output
```

## Links

- [restic](https://restic.net/) — Backup-Programm
- [rclone](https://rclone.org/) — Cloud-Speicher-Synchronisierungstool
- [XTLS/go-win7](https://github.com/XTLS/go-win7) — gepatchtes Go für Windows 7
- [Diskussion über Windows 7-Support-Ende in Go](https://github.com/golang/go/issues/57003)
