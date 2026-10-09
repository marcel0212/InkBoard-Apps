# InkBoard Apps (Katalog)

Der Katalog des InkBoard-Stores: alle Apps für das [InkBoard](https://github.com/marcel0212/InkBoard)
als Skript-Pakete. In Studio, in der Mac-App und in der iPhone-App findest du sie
unter **Store**; dort installierst du sie, schaltest sie ein oder aus und stellst
sie ein. Du musst hier nichts herunterladen.

Das Studio lädt `index.json` standardmäßig von
`https://raw.githubusercontent.com/marcel0212/InkBoard-Apps/main/index.json`
(unter Store → „Quelle ändern“ umstellbar). Datenschutz: [PRIVACY.md](PRIVACY.md).

## Für Entwickler: Katalog bauen und veröffentlichen

Dieser Ordner (`store/`) liegt im Hauptrepo und wird daraus in dieses öffentliche
Repo exportiert, damit das Hauptrepo privat bleiben kann (ein privates Repo liefert
dem Browser keine Dateien ohne Anmeldung).

```
python3 tools/store_build.py                     # Katalog aktuell bauen
python3 tools/store_export.py ../InkBoard-Apps   # in einen leeren Ordner exportieren
cd ../InkBoard-Apps && git add -A && git commit -m "Katalog" && git push origin main
```

Bei jeder Katalog-Änderung wiederholen. Zum lokalen Testen ohne GitHub:
`python3 tools/store_serve.py` zeigt eine Adresse wie `http://192.168.1.20:8099/index.json`,
die du im Studio unter Store → „Quelle ändern“ einträgst.

## Aufbau einer App

```
store/apps/<id>/
  manifest.json   aufs Gerät: Kennung, Name, Version, apiLevel, Seiten, Einstellungen
  main.src.lua    Quelltext des Skripts (optional, mit Includes); daraus wird main.lua erzeugt
  main.lua        Skript (Einstiegspunkte on_fetch/on_draw/on_widget/on_settings)
  widget.lua      optional
  i18n.json       optional
  store.json      nur für den Store: Kategorie, Beschreibung (DE/EN), Funktionen, Vorschaubilder
  icon.svg        App-Symbol
  preview-*.svg   Vorschaubilder (display = 800x480, widget = Dashboard-Widget)
  package.json    ERZEUGT: Bundle {manifest, files}, das ans Gerät geht
```

Jede Änderung an einem Paket braucht eine höhere `version` im Manifest, sonst
erkennt das Gerät kein Update. Danach den Katalog neu bauen und mit committen:

```
python3 tools/store_build.py          # schreibt package.json + index.json
python3 tools/store_build.py --check  # prüft, ob alles aktuell ist (Host-Tests)
```

`index.json` enthält je App sha256, Signatur (`sig`) und Größe des Pakets. Das Studio
und die Apps schicken Prüfsumme und Signatur beim Installieren mit; die Firmware rechnet die
Prüfsumme nach und prüft die Signatur (RSA-2048, SHA-256) gegen den eingebauten Schlüssel
(`src/store_public_key.h`). Ohne gültige Signatur installiert das Gerät nichts aus dem Katalog.
Kategorien und Empfehlungen: `categories.json`. Eigene Apps schreiben: `docs/SKRIPT_APPS.md` im
Hauptrepo.

## Signieren

`python3 tools/store_build.py` signiert jedes Paket mit `tools/store/store_private_key.pem`
(liegt nur auf dem Rechner des Katalog-Betreibers, steht in `.gitignore`, nie committen und
sichern!). Ohne diese Datei (z. B. in der CI) kann der Build nur unveränderte Pakete mit ihrer
bisherigen Signatur übernehmen; `--check` prüft jede Signatur gegen `tools/store/store_public_key.pem`.
Schlüsselwechsel: neues Paar mit `openssl genrsa -out tools/store/store_private_key.pem 2048` und
`openssl rsa -in tools/store/store_private_key.pem -pubout -out tools/store/store_public_key.pem`,
`src/store_public_key.h` aus dem neuen öffentlichen Schlüssel erzeugen, Firmware und Katalog neu bauen.

Folge: Kataloge anderer Betreiber (Store → „Quelle ändern“) lassen sich nur installieren, wenn sie
mit diesem Schlüssel signiert sind. Eine selbst gewählte Paketdatei (Store → „Paket aus Datei“) bleibt
möglich, weil sie der Nutzer selbst auswählt.
