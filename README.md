# InkBoard App Store (Katalog)

Dieser Ordner ist die Quelle des InkBoard App Stores. Das Studio laedt
`index.json` standardmaessig aus einem EIGENEN, oeffentlichen Repo
`https://raw.githubusercontent.com/marcel0212/InkBoard-Apps/main/index.json`
(im Studio unter Store -> "Quelle aendern" umstellbar). Das Hauptrepo kann
privat bleiben: ein privates Repo liefert dem Browser keine Dateien ohne
Anmeldung, deshalb liegt nur der fertige Katalog (der ohnehin oeffentlich
sein soll) in einem eigenen Repo.

## Veroeffentlichen (Hauptrepo bleibt privat)

```
python3 tools/store_build.py              # Katalog aktuell bauen
python3 tools/store_export.py ../InkBoard-Apps   # leeren Ordner befuellen
cd ../InkBoard-Apps && git init && git add -A && git commit -m "Katalog"
# auf GitHub ein OEFFENTLICHES Repo "InkBoard-Apps" anlegen, dann pushen
```

Bei jeder Katalog-Aenderung wiederholen (Export in einen frischen Ordner,
oder dessen Inhalt ersetzen und committen).

## Lokal testen (ohne GitHub)

```
python3 tools/store_serve.py          # zeigt z. B. http://192.168.1.20:8099/index.json
```

Diese Adresse im Studio unter Store -> "Quelle aendern" eintragen.

## Aufbau einer App

```
store/apps/<id>/
  manifest.json   aufs Geraet: Kennung, Name, Version, apiLevel, Seiten, Einstellungs-Schema
  main.lua        Skript (Einstiegspunkte on_fetch/on_draw/on_widget/on_settings)
  widget.lua      optional
  i18n.json       optional
  store.json      nur fuer den Store: Kategorie, Beschreibung, Funktionen, Vorschaubilder
  icon.svg        App-Symbol
  preview-*.svg   Vorschaubilder (display = 800x480, widget = Dashboard-Widget)
  package.json    ERZEUGT: Bundle {manifest, files}, das ans Geraet geht
```

Nach jeder Aenderung den Katalog neu bauen und mit committen:

```
python3 tools/store_build.py          # schreibt package.json + index.json
python3 tools/store_build.py --check  # prueft, ob alles aktuell ist (Host-Tests)
```

`index.json` enthaelt je App sha256 und Groesse des Pakets. Das Studio schickt
die Pruefsumme beim Installieren mit, die Firmware rechnet sie nach.

Kategorien und Empfehlungen: `store/categories.json`.
Wichtig: Der Katalog sichert gegen Uebertragungsfehler, nicht gegen einen
boesartigen Katalog - die Signatur der Pakete folgt (docs/V2_APPSTORE.md, 4.).
