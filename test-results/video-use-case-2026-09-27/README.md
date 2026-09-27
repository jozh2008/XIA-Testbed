# XIA Video-Use-Case: synthetischer Funktionstest

## Teststand

- Datum: 27.09.2026
- Repository: https://github.com/jozh2008/XIA-Testbed
- Branch: `6-test-new-features-on-the-network`
- Commit des Testbeds: `9613f779b709404c6b2301cd6d97cc2890b5ac29`
- Umgebung: Apple-Silicon-Mac, Docker Desktop, Linux/amd64-Container unter Emulation.
- Die hier gesicherten Hilfsdateien ergänzen diesen Commit; sie sind kein Bestandteil des oben genannten Teststands.

## Ziel und Aufbau

Prüfen, ob die vorhandenen Video-Anwendungen einen Videoinhalt veröffentlichen und über XIA abrufen können und ob die abgerufenen Daten im Browser abspielbar sind.

XIA-Testbed: `host0 — router0 — router1 — router2 — server0`.

Auf `server0` laufen `manifest_server` und `video_publisher origin`. Auf `host0` läuft der HTTP/XIA-Proxy auf Port 8080. Eine zusätzliche Python-Brücke auf dem Mac (Port 8765, nur localhost) führt Abrufe mittels `docker exec` über diesen Proxy aus. Der zusätzliche Browser-Player lädt das Manifest und hängt die Videofragmente mittels MediaSource aneinander.

Der Browser spricht somit nicht selbst XIA. Für diesen Test ist keine Veröffentlichung des Container-Ports 8080 am Mac erforderlich.

## Testmaterial und Anpassungen

Da der verlinkte Beispielvideo-Download nicht verfügbar war, wurde mit FFmpeg 9.0.2 ein synthetischer Clip erzeugt:

- 12 Sekunden, 320 × 180 Pixel, 25 Bilder/s, H.264, ohne Ton;
- eine Qualitätsstufe, Initialisierungsdatei und sechs Segmente zu jeweils etwa zwei Sekunden;
- ursprüngliches MPD-Manifest unter `fixture/synthetic12/synthetic12.mpd`.

`helpers/create-test-video.sh` dokumentiert die Erzeugung. Für eine Wiederholung vorzugsweise die gesicherten Dateien verwenden: Eine Neuerzeugung mit anderen Werkzeugversionen muss nicht dieselben Bytes/CIDs liefern.

Die Abrufhilfen normalisieren den Hostteil der DAG-URLs auf Kleinschreibung und ergänzen bei leerem Pfad `/`, passend zum Legacy-Proxy. Vor dieser Anpassung scheiterte der Prüfabruf mit `BadStatusLine: No status line received`. Der erfolgreiche Retest ist unten dokumentiert. Für diesen Video-Test wurde der XIA-Anwendungscode nicht geändert; bestehende Testbed-Patches bleiben Bestandteil des verwendeten Images.

## Wiederholung

Alle folgenden Mac-Befehle werden im Repository-Hauptverzeichnis ausgeführt. Docker und das passende Testbed-Image müssen verfügbar sein. Der getestete Container heisst `host0`; die lokale Brücke setzt diesen Namen voraus.

### 1. Testbed und Fixture vorbereiten

Falls das Testbed noch nicht läuft:

```bash
make up
```

Zustand prüfen und den gesicherten Clip in den Container kopieren:

```bash
make check
docker compose exec server0 mkdir -p /opt/xia-core/applications/video-use-case/src/resources
docker cp test-results/video-use-case-2026-09-27/fixture/synthetic12 server0:/opt/xia-core/applications/video-use-case/src/resources/
```

### 2. Drei Programme in getrennten Terminals starten

Terminal 1, Manifest-Server:

```bash
docker compose exec server0 bash -lc "cd /opt/xia-core/applications/video-use-case/src && ./manifest_server"
```

Terminal 2, Publisher:

```bash
docker compose exec server0 bash -lc "cd /opt/xia-core/applications/video-use-case/src && ./video_publisher origin"
```

Am Publisher-Prompt `>>` eingeben:

```text
synthetic12 host
```

Die Rückkehr zum Prompt allein ist noch kein Erfolgsnachweis; entscheidend sind die anschliessenden Abrufe. Publisher weiterlaufen lassen.

Terminal 3, Proxy:

```bash
docker compose exec host0 bash -lc "cd /opt/xia-core/applications/video-use-case/src && ./proxy 8080"
```

### 3. Optional: Abruf ohne Browser prüfen

```bash
docker cp test-results/video-use-case-2026-09-27/helpers/check-video-fetch.py host0:/tmp/check-video-fetch.py
docker compose exec host0 timeout 45s python2 -u /tmp/check-video-fetch.py
```

### 4. Browser-Wiedergabe

In einem zusätzlichen Mac-Terminal:

```bash
python3 test-results/video-use-case-2026-09-27/helpers/browser-test.py
```

`http://127.0.0.1:8765/` öffnen und „Video über XIA laden und abspielen“ anklicken. `player.html` muss neben `browser-test.py` liegen. Die drei XIA-Programme und die lokale Brücke während des Tests laufen lassen.

Nach einer Container-Neuerstellung können ADs/HIDs wechseln. Den Clip dann neu veröffentlichen und das aktuelle Manifest verwenden; alte DAG-URLs nicht fest übernehmen.

## Beobachtetes Ergebnis

Der Nutzer bestätigte die sichtbare Wiedergabe. Die Testseite meldete den vollständigen Abschluss nach 12,0 Sekunden.

| Datei | Empfangene Bytes | CID-Prüfung |
|---|---:|---|
| Initialisierung | 826 | erfolgreich |
| Segment 1 | 55 037 | erfolgreich |
| Segment 2 | 71 074 | erfolgreich |
| Segment 3 | 62 921 | erfolgreich |
| Segment 4 | 69 030 | erfolgreich |
| Segment 5 | 57 784 | erfolgreich |
| Segment 6 | 59 736 | erfolgreich |
| **Gesamt (ohne Manifest)** | **376 408** | **7 von 7** |

Die Abrufhilfe vergleicht den SHA-1-Hash jedes empfangenen Medienobjekts mit dessen CID aus der URL. Auch der vorherige Terminaltest meldete: `SUCCESS: all 7 files fetched and verified (376408 bytes)`.

Zwei vom Nutzer gesicherte Screenshots liegen unter `screenshots/`. Eine separate Textdatei der Browser-Ausgabe wurde nicht angelegt.

## Aussagekraft und Grenzen

Erfolgreicher Funktionstest des Veröffentlichungs-/Abrufpfads mit anschliessender vollständiger Browser-Wiedergabe des Testclips. Dies ist keine vollständige Validierung der ursprünglichen Video-Demo.

- Synthetisches Ersatzmaterial und zusätzlicher lokaler Test-Player, nicht der ursprüngliche Demo-Player.
- Keine Prüfung adaptiver Qualitätswechsel, CDN-Auswahl, Failover oder Audio.
- Kein Durchsatz-, Latenz- oder unterbrechungsfreier Echtzeit-Streaming-Benchmark.
- Bereits geladene Inhalte können aus XIA-Caches stammen. Es wurde nicht nachgewiesen, dass jeder Browserabruf erneut bis `server0` lief.
- Die erfolgreiche CID-Prüfung belegt die Übereinstimmung der empfangenen Medienbytes mit den angegebenen CIDs, nicht eine weitergehende Sicherheitsbewertung.
- Der Git-Commit allein pinnt nicht alle Build-Abhängigkeiten oder den im Image enthaltenen XIA-Core-Stand. Image-Digest und XIA-Core-Commit sind in dieser Notiz noch nicht erfasst.

## Ablage

- `helpers/`: Erzeugungsskript, Terminal-Prüfskript, lokale Brücke und Player.
- `fixture/`: Originalmanifest und die sieben Mediendateien.
- `screenshots/`: sichtbare Testnachweise.
- `logs/`: für zusätzliche Ausgaben vorgesehen; bislang keine separaten Logs gesichert.

## Beenden

Lokale Brücke und Proxy/Manifest-Server mit Ctrl+C beenden; beim Publisher `quit` eingeben. Wenn keine weiteren Tests laufen, kann das Testbed anschliessend mit `make down` beendet werden. Die auf dem Mac gesicherten Dateien bleiben erhalten.
