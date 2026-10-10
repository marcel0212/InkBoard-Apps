# InkBoard-Skript-Apps entwickeln

Eine Skript-App ist ein kleines Paket aus Lua-Skript und Beschreibung. Sie wird im Studio (oder in der Mac-/iOS-App) aus dem Store installiert, ohne dass die Firmware neu geflasht werden muss. Auf dem Gerät sieht sie aus und verhält sich wie eine eingebaute App: eigene Seiten, Einstellungen, Dashboard-Widget, Rotation.

Stand: Skript-API Level 1 (CHANGELOG 483). Diese Doku beschreibt nur, was die Firmware heute kann. Mehr dazu steht am Ende unter „Noch nicht möglich“.

## 1. Schnellstart (10 Minuten)

1. Ordner `docs/skript-vorlage/` nach `store/apps/<deine-id>/` kopieren (Kennung: Kleinbuchstaben, Ziffern, `-` und `_`, höchstens 24 Zeichen, nicht identisch mit einer eingebauten App).
2. In `manifest.json` die `id` auf den Ordnernamen setzen, Name und Einstellungen anpassen.
3. `main.lua` schreiben (Abschnitt 4 bis 6).
4. Katalog bauen: `python3 tools/store_build.py` (prüft Manifest und Größen, schreibt `package.json` und `index.json`).
5. Lokal anbieten: `python3 tools/store_serve.py`, im Studio unter Store → „Quelle ändern“ die angezeigte Adresse eintragen, App installieren.

Die Vorlage ist ein vollständiges Beispiel (Seite, Widget, drei Einstellungen) und wird bei jedem Testlauf des Projekts mit ausgeführt, sie läuft also garantiert.

## 2. Aufbau eines Pakets

```
store/apps/<id>/
  manifest.json   Pflicht   Kennung, Name, Version, Seiten, Einstellungen, Rechte
  main.lua        Pflicht   Skript mit den Einstiegspunkten
  widget.lua      optional  eigenes Widget-Skript (sonst gilt on_widget aus main.lua)
  i18n.json       optional  Texte
  assets/*.ibm    optional  Bilder (Abschnitt 8)
  store.json      Store    Kategorie, Beschreibung, Vorschaubilder (nur fürs Studio)
  icon.svg        Store    App-Symbol im Store
```

Grenzen: ganzes Paket höchstens 96 KB, je Datei höchstens 64 KB, bis zu 32 Apps gleichzeitig installiert (so viele Plätze gibt es).

## 3. manifest.json

```json
{
  "id": "hello",
  "name": {"de": "Hallo", "en": "Hello"},
  "version": "1.0.0",
  "apiLevel": 1,
  "pages": 1,
  "refreshMinutes": 60,
  "widget": {"w": 320, "h": 130},
  "permissions": {"net": ["api.example.org"]},
  "settings": [ ... ]
}
```

- `name`: Text oder `{"de":..., "en":...}`.
- `version`: bis 16 Zeichen. **Bei jeder Änderung erhöhen**, sonst erkennt der Store kein Update.
- `apiLevel`: die API-Stufe, die das Paket mindestens braucht (1 bis 22; die Stufen stehen bei den jeweiligen Funktionen). Ein Gerät mit älterer Firmware lehnt höhere Level ab und zeigt „Firmware-Update nötig“.
- `pages`: Anzahl der Seiten (1 bis 6) oder Liste von Seitennamen `[{"de":"Heute","en":"Today"}, ...]`. `on_draw` bekommt die Seitennummer (ab 1). Ab API-Stufe 18 kann ein Listeneintrag `"fullscreen": true` tragen: Die Seite wird dann ohne Standard-Kopfzeile über die ganze Fläche gezeichnet (`draw.top` ist 0; die Firmware blendet nur eine kleine Positions-Pille ein). Ab API-Stufe 20 kann ein Eintrag `"ownDate": true` tragen: Die Seite zeigt ihr Datum selbst, deshalb lässt die Kopfzeile das Standard-Datum weg (die Uhrzeit „Stand HH:MM“ bleibt). Den Text in der Mitte der Kopfzeile liefert dann der Hook `on_header` (siehe Abschnitt 4).
  Die Namen der Liste (`de`/`en`) sind auch die Seitennamen in Studio und Apps (Anzeige am Gerät: Reihenfolge und Auswahl der Seiten, Detailseite): ab Firmware Build 625 liefert das Gerät sie als `pageNames` (`[{"de":..,"en":..}]`) in `GET /api/pkg-list` und `GET /api/pkg-settings`, `tools/store_build.py` schreibt sie für nicht installierte Apps in `index.json`. Mit einer reinen Zahl statt Liste zeigen die Clients "Seite 1", "Seite 2" ... Neue Pakete mit mehreren Seiten sollten deshalb eine Namensliste angeben.
- `needsStorage` (optional, `true`/`false`, Standard `false`; Firmware ab Build 627): die App braucht den externen Speicher (NAS). Ohne eingerichteten Speicher (Einstellungen -> Speicher) gilt sie wie die eingebauten Speicher-Apps als nicht vorhanden: nicht im Zyklus, kein Abruf, im Store nicht installierbar (Karte gedimmt, Hinweis „Benötigt externen Speicher (NAS)“, Klick führt zur Speicher-Einrichtung), installiert gesperrt (nicht angezeigt, kein „Auf dem Display zeigen“, Widget ohne Daten). Danach ist sie ohne Neuinstallation wieder da. Setzen bei Apps, die `storage.*` oder `inbox.send()` zwingend brauchen (Flight Radar, Pinnwand); NICHT bei Apps mit lokalem Speicher (Wetter) oder ohne Speicherbezug. Reine Zusatzangabe, kein neues `apiLevel`: ältere Firmware prüft nur bekannte Felder und ignoriert dieses (die App läuft dort ohne Sperre). `GET /api/pkg-list` liefert `needsStorage` je Paket und `storageReady` (bool) im Gesamtobjekt, `index.json` das Feld `needsStorage` je App (nur wenn `true`).
- `refreshMinutes`: wie oft `on_fetch` läuft (1 bis 1440; Apps mit Netzabruf sollten nicht unter 5 gehen, 1 ist für reine Anzeige-Apps wie die Uhr gedacht).
- `widget`: Standardgröße des Widgets in Pixeln. Fehlt die Angabe, ist es 320 × 130. Ab API-Stufe 20 (CHANGELOG 637) kann es `"relevantWhen": {"key": "lastEnd", "mode": "future"}` tragen (**bedingtes Widget**): `key` ist ein Schlüssel aus `ctx.data` (den `on_fetch` mit `ctx.data.set` setzt, 1 bis 24 Zeichen `a-z A-Z 0-9 _`), `mode` ist `future` (der Wert ist eine Unix-Zeit in der Zukunft) oder `nonzero` (der Wert ist nicht leer, 0 oder false). Dann bietet Studio (und die Mac-/iOS-App) im Dashboard-Editor für dieses Widget den Schalter „Nur zeigen, wenn relevant“ an (`/api/pkg-list` meldet `widgetCond`); ist er an und die Bedingung nicht erfüllt, wird das Widget wie die eingebauten bedingten Widgets übersprungen (in einer Wechselgruppe kommt das nächste). Ohne gültige Uhrzeit gilt das Widget als relevant. Beispiel: `calendar-app` (`lastEnd` = Ende des spätesten Termins).
- `permissions.net`: Liste der Hosts, die `http.get` und `http.request` erreichen dürfen (nur https, Port 443). Ein Eintrag `*.example.com` gilt für alle Unterdomains (nicht für `example.com` selbst, das trägst du zusätzlich ein; nötig z. B. für iCloud, das auf `pNN-caldav.icloud.com` weiterleitet). Ohne Eintrag kein Netz.
- `permissions.netFrom` (API-Stufe 6): Liste von Schlüsseln von `url`-Feldern (höchstens 4). Der Server, den der Nutzer dort einträgt, darf `http.request` ansprechen, **auch per `http` und mit eigenem Port** (für ein NAS/Nextcloud im Heimnetz). Nur genau dieser Ursprung (Schema, Host, Port) ist freigegeben.
- `permissions.spotify` (API-Stufe 21, `true`): erlaubt `spotify.now()` (siehe Abschnitt „Spotify“ unter 7). Ohne diese Angabe ist `spotify.now()` ein Skriptfehler; das Cover zeichnen darf jede App.
- `permissions.tlsVerify` (API-Stufe 22, `true`, Firmware ab Build 659): `http.get`, `http.request`, `http.image` und `ics.fetch` prüfen dann das Zertifikat des Servers gegen das CA-Bündel des ESP-IDF (Mozilla-Wurzeln). Ohne die Angabe bleibt es wie bisher ungeprüft, weil Heimnetz-Server (NAS, Nextcloud) oft ein selbstsigniertes Zertifikat haben – setze es also bei Paketen, die **öffentliche** Dienste mit normalem Zertifikat abrufen (Wetter-, Nachrichten-, Kurs-APIs), und NICHT bei Paketen mit `permissions.netFrom` (eigener Server des Nutzers). Mit Prüfung gibt es keinen Rückfall auf „ungeprüft“: ein ungültiges, abgelaufenes oder unbekanntes Zertifikat und eine falsche Uhrzeit (ohne NTP) lassen den Abruf mit einem Fehler scheitern. Gilt nicht für `recipe.fetch` und `storage.*` (eigene Prüfpfade). Ältere Firmware lehnt das Paket wegen des höheren `apiLevel` ab, statt unbemerkt ungeprüft zu laufen.

### Einstellungen (`settings`, höchstens 24; ab API-Stufe 16 / Firmware Build 614 höchstens 40)

Aus dem Schema baut Studio/Mac/iOS das Formular, du schreibst kein HTML. Jedes Feld hat `key` (Buchstaben, Ziffern, `_`, bis 24 Zeichen), `type`, `label` und optional `default`.

| type | Zusätze | Wert in `ctx.cfg` |
|---|---|---|
| `text` | `maxLen` (bis 200) | Text |
| `password` | `maxLen` | Text (im Studio verdeckt) |
| `number` | `min`, `max` | Zahl |
| `toggle` | | `true`/`false` |
| `select` | `options` (Liste), `optionLabels` (Anzeigenamen je Sprache); ab API-Stufe 20 optional `swatches` (`{"blue": "#2f5aa8", ...}`: Farbpunkte statt Liste) und `previewPage` (Seite ab 0: unter dem Feld erscheinen die Stil-Vorschauen dieser Seite, siehe `style`/`page` bei den Vorschauen) | gewählte Option als Text |
| `list` | bis 20 Einträge à 100 Zeichen | Liste von Texten |
| `color` | | Farbtext `#RRGGBB` |
| `url` | `default` (optional) | Serveradresse des Nutzers (API-Stufe 6), z. B. `https://nas.local:8443/remote.php/dav`. Beginnt mit `http://` oder `https://` (ab API-Stufe 20 auch `webcal://`, das als `https://` gespeichert wird), keine Zugangsdaten (ein `@` ist nur im Serverteil verboten, im Pfad und in der Abfrage erlaubt, z. B. in Google-Kalender-Links), keine Leerzeichen, bis 400 Zeichen (vorher 200); leer = nicht eingerichtet. Zusammen mit `permissions.netFrom` gibt sie den Server für `http.request` frei. Zugangsdaten gehören in eigene `text`-/`password`-Felder. |
| `storagePath` | `default` (Ordner, sonst `/inkboard/<id>`) | Zielordner auf dem externen Speicher des Geräts (API-Stufe 5), z. B. `/inkboard/meine-app`. Nur Buchstaben, Ziffern, `_ - . /` und Leerzeichen, kein `..`, höchstens 100 Zeichen. Leer = Standardordner. Der Wert liegt nicht im Paket, sondern zentral auf dem Gerät in `/storage_paths.json` (überlebt Paket-Updates, wird beim Entfernen des Pakets gelöscht). Das Skript bekommt den Ordner nicht als Text, sondern nutzt `storage.*` mit dem Feldnamen. |
| `info` | `text` (Text, `{1}` und `{2:time}` als Platzhalter), `empty` (Text ohne Wert), optional `device` | Reine Anzeige im Formular, ohne Wert (API-Stufe 19). Der Text kann Platzhalter aus einer Liste tragen, die das Gerät liefert: `{1}` = erster Eintrag, `{2:time}` = zweiter Eintrag (Unix-Sekunden) als Datum und Uhrzeit nach Ortseinstellung des Browsers bzw. der App. Liefert das Gerät keinen Wert, steht `empty`. Über `device` (siehe unten) füllt die Firmware die Liste; nach jeder erfolgreichen Aktion liest das Formular die Anzeige neu. Ein `info`-Feld kann eine `action` tragen (Knopf unter dem Text). |
| `connect` | `device` (derzeit nur `"spotify"`) | Verbindungskarte für einen Dienst der Firmware (API-Stufe 21, Firmware ab Build 658): Studio und Mac-/iOS-App zeigen dort Client-ID, Client-Secret, Abfrage-Takt, „Verbinden“/„Trennen“ und die Einrichtungsanleitung. Das Feld hat keinen Wert, keinen `default` und keine `action`, steht höchstens einmal im Paket und wird nicht mit den Einstellungen gespeichert (die Karte speichert selbst am Gerät). Ältere Studio-/App-Stände zeigen das Feld nicht. |

**Geräte-Bindung und Raumliste (API-Stufe 19):** Ein Feld kann mit `"device"` an einen Wert der Firmware gebunden sein, der nicht im Paket liegt: `storagePath` + `"device": "pinnwandFtpPath"` ist der Ordner der Pinnwand-Zustellung auf dem externen Speicher (derselbe Wert wie „Pinnwand: Ordner für die FTP-Zustellung“ in den allgemeinen Einstellungen; leer gespeichert = `default`), `info` + `"device": "pinnwandStatus"` zeigt die letzte Pinnwand-Nachricht (Liste `[Absender, Sendezeit]`, Absender leer = `-`; ohne Nachricht der `empty`-Text). Jede Bindung darf höchstens einmal vorkommen; andere Namen lehnt `store_build.py` und die Firmware ab. Ein `select` mit `"optionsFrom": "networkRooms"` zeigt von seinen `options` nur `all`/leer, den gewählten Wert und Räume, in denen im InkBoard Netzwerk ein Gerät steht (wie das Dropdown „Anzeigen auf“ der Pinnwand; ohne Netzwerk-Scan die volle Liste). `info`, `device` und `optionsFrom` brauchen `apiLevel` 19; ältere Studio-/App-Stände zeigen das `info`-Feld als Textfeld.

**Felder nur bei Bedarf zeigen (`showIf`, CHANGELOG 519):** Ein Feld mit `"showIf": {"key": "dienst", "in": ["todoist", "icloud"]}` erscheint im Formular nur, wenn das Auswahlfeld (`select`) `dienst` einen dieser Werte hat (1 bis 8 Werte, das Bezugsfeld muss ein `select` sein). Ausgeblendete Felder behalten ihren Wert und stehen weiter in `ctx.cfg`; das Skript sollte sie je nach Auswahl ignorieren.

**Knopf unter einem Feld (`action`, CHANGELOG 519):** `"action": {"name": "connect_a", "label": {"de": "Verbinden", "en": "Connect"}, "fills": "liste"}` zeigt unter dem Feld einen Knopf (Name `a-z0-9_`, höchstens 24 Zeichen; `fills` ist optional und nennt ein `text`-Feld). Beim Klick speichert das Formular zuerst, dann ruft die Firmware `on_action(ctx, name)` auf (Netz erlaubt wie in `on_fetch`, 6 Abrufe, bis zu 30 Sekunden). Das Skript antwortet mit `{ok = true/false, message = "Text", options = {{value = "...", label = "..."}, ...}}`. Die Nachricht steht unter dem Knopf (grün/rot); `options` machen aus dem Feld `fills` eine Auswahlliste (höchstens 40 Einträge). So lassen sich Zugangsdaten prüfen und Listen/Projekte zur Auswahl laden (Beispiel: `todo-list`).

**Datei-Knöpfe (API-Stufe 18):** Eine `action` kann zusätzlich `"upload": "<datei>"` oder `"download": "<datei>"` tragen (nicht beides; `<datei>` ist ein `file.*`-Name des Pakets: `a-z 0-9 _ -`, bis 24 Zeichen, die Datei höchstens 24 KB und nur Text). Mit `upload` öffnet der Knopf zuerst die Dateiauswahl (Studio und Apps; `"accept": ".json"` filtert), schickt den Text an `POST /api/pkg-file?id=<paket>&name=<datei>` und ruft dann die Aktion auf, die ihn mit `file.read("<datei>")` liest (und nach dem Übernehmen mit `file.write("<datei>", "")` leert). Mit `download` läuft zuerst die Aktion, die die Datei mit `file.write("<datei>", text)` schreibt, danach lädt der Browser bzw. die App sie über `GET /api/pkg-file` herunter (`"filename": "airlines.json"` ist der vorgeschlagene Name). Die Firmware erlaubt nur Dateinamen, die das Manifest so deklariert (Paket-Id, Namensregel, Größe und Dateisystem-Sperre werden geprüft; beide Routen verlangen wie alle Studio-Zugriffe die Anmeldung). Ältere Studio-/App-Stände zeigen nur den normalen Knopf. Beispiel: `flight-radar` (`airlines.json` importieren/exportieren, Änderungsliste der letzten Übernahme und die Abdeckungs-CSV als Download; seit CHANGELOG 635 auch ohne NAS lieferbar, `.csv`-Downloads speichern die Apps als CSV). Als Feld für den Knopf dient ein `select` mit einer einzigen Option, weil jede `action` an einem Feld hängt.

**Abschnitte (`sections`, CHANGELOG 615):** Apps mit vielen Einstellungen gliedern ihr Formular in einklappbare Gruppen. Auf oberster Ebene des Manifests steht eine Liste `"sections"` (höchstens 8), jedes Feld nennt seinen Abschnitt mit `"section": "<id>"`:

```json
"sections": [
  {"id": "departures", "title": {"de": "Abfahrten", "en": "Departures"},
   "help": {"de": "Haltestelle eintippen und „Haltestelle suchen“ drücken ...", "en": "Type a stop and press “Search stop” ..."},
   "helpTitle": {"de": "So geht's", "en": "How it works"}, "helpUrl": "https://example.org/hilfe"},
  {"id": "routes", "title": {"de": "Routen", "en": "Routes"}, "collapsed": true}
],
"settings": [
  {"key": "stop", "type": "text", "label": {"de": "Haltestelle", "en": "Stop"}, "section": "departures"},
  ...
]
```

- `id`: Kleinbuchstaben, Ziffern, `-`, `_`, bis 24 Zeichen, eindeutig. `title` Pflicht (bis 60 Bytes je Sprache).
- `help` (bis 1000 Bytes je Sprache, je Zeile ein Absatz), `helpTitle` (bis 80) und `helpUrl` (nur `https://`, bis 160) bilden **die eine Anleitung der Gruppe**; Studio und Apps zeigen sie aufklappbar oben in der Gruppe. Lange Anleitungen gehören hierher, nicht in die einzelnen Felder.
- `collapsed: true`: Gruppe ist anfangs zugeklappt (sonst offen). Ob eine Gruppe offen ist, merken sich Studio (Browser) und Apps je App und Abschnitt.
- Felder ohne `section` stehen wie bisher ohne Überschrift über den Gruppen. Ein `help` an einem Feld innerhalb einer Gruppe erscheint nur noch als kurzer Hinweis unter dem Feld (kein eigener Aufklapp-Block) - also kurz halten.
- Das Feld `style` (Bereich „Stil“ mit Vorschau) und Felder mit `group: "widget"` (Bereich „Widget“ bzw. je Widget im Dashboard) behalten ihren festen Platz und bekommen keine `section`. Eine Gruppe, deren Felder alle ausgeblendet sind (`showIf`), verschwindet.
- Innerhalb einer Gruppe funktionieren Zwischenüberschriften (`group` als `{"de","en"}`) weiter, z. B. „Route 1“ … „Route 6“ in `oepnv`.
- Rückwärtskompatibel, kein neues `apiLevel`: Ältere Firmware installiert solche Pakete und ignoriert `sections`/`section` (ältere Studio-/App-Stände zeigen die flache Liste). Ab Firmware Build 615 prüft das Gerät die Angaben (unbekannte Abschnitts-id, doppelte id, fehlender Titel werden abgelehnt) und liefert die Liste in `GET /api/pkg-settings` als `"sections"` mit. `python3 tools/store_build.py` prüft dasselbe und meldet zusätzlich Abschnitte ohne Feld.

Beispiel `select` mit Anzeigenamen:

```json
{"key": "accent", "type": "select", "options": ["blue", "red"], "default": "blue",
 "optionLabels": {"de": {"blue": "Blau", "red": "Rot"}, "en": {"blue": "Blue", "red": "Red"}},
 "label": {"de": "Akzentfarbe", "en": "Accent color"}}
```

## 4. Einstiegspunkte (Hooks) in main.lua

```lua
function on_fetch(ctx)        -- holt Daten (Netz). Läuft im Hintergrund, nie beim Zeichnen.
function on_draw(ctx, page)   -- zeichnet die Vollbild-Seite `page` (ab 1)
function on_widget(ctx, box)  -- zeichnet das Dashboard-Widget
```

Alle drei sind optional. **`on_header(ctx, seite)` (API-Stufe 20):** liefert den Text, den die Kopfzeile in der Mitte zeigt (z. B. „August 2026 - KW 34“, höchstens 60 Byte, UTF-8-sicher gekürzt), oder `nil` für keinen Text. Läuft vor dem Zeichnen jeder Seite mit `"ownDate": true`, ist nur zum Lesen gedacht (`ctx`, `time.*`, `file.read`, `ctx.data.get`), (nichts zeichnen, kein Netz); ein Fehler im Hook wird ins Geräte-Log geschrieben und die Kopfzeile bleibt ohne Text. Sinnvoll zusammen mit `"ownDate": true` an der Seite. Beispiel: `calendar-app` (Woche und Monat).

Dazu kommt `on_input(ctx, art, n)` (API-Stufe 10, nur mit `"input": true` im Manifest): Die Firmware gibt dann Drehen und Tasterklick an das Skript, statt Seiten umzuschalten. `art` ist `"turn"` (`n` = Rasten, positiv = rechts) oder `"click"`. Rückgabe: `true` = behandelt, neu zeichnen; `"blip"` = behandelt, nur LED-Rückmeldung (z. B. „Klick scharf geschaltet“); `"fetch"` = behandelt, Daten sofort neu holen (`on_fetch`) und danach neu zeichnen; `false`/nichts = nicht behandelt (ein Klick führt dann wie bei jeder App eine Ebene hoch zur App-Übersicht, die Drehung bleibt ohne Wirkung). Kein Netz, kein Zeichnen: der Hook ändert nur `ctx.data` (wird danach gespeichert), gezeichnet wird anschließend mit `on_draw`. Eine solche App verwaltet ihre Ansichten selbst (z. B. Index in `ctx.data`) und hat im Manifest nur eine Seite. Beispiel: `gericht-des-tages` (Drehen blättert, zweiter Klick innerhalb 3 s mit `ctx.data.set("rq", 1)` und `"fetch"` löst neu).

Dazu kommt `on_action(ctx, name)` für Knöpfe im Einstellungsformular (siehe `action` bei den Einstellungen). Eine App ohne `on_draw` hat keine Vollbild-Seite, eine ohne `on_widget` kein Widget.

**`on_close(ctx)` (API-Stufe 18, nur mit `"onClose": true` im Manifest):** Die Firmware ruft den Hook, sobald die App nicht mehr die angezeigte App ist (andere App, Übersicht oder Dashboard; Erkennung im Netz-Durchlauf, also mit einigen Sekunden Verzögerung) und kurz vor dem Tiefschlaf im Akkubetrieb. `ctx.reason` ist `"leave"` oder `"sleep"`. Wie `on_action`: `storage.*` und `file.write` sind erlaubt (Auswertungen abschließen, Zustand sichern), Netz und Zeichnen nicht; Rückgabe und Fehler werden ignoriert (nur im Geräte-Log). Nach einem Neustart oder Stromausfall gibt es kein Ereignis; dafür bleibt `ctx.opened` (Manifest `fetchOnOpen`) als Rückfall.

**Ablauf:** Die Firmware ruft `on_fetch` im Takt von `refreshMinutes` auf. Du speicherst die Ergebnisse mit `ctx.data.set(...)`. `on_draw` und `on_widget` lesen sie mit `ctx.data.get(...)`. Zeichnen und Abruf sind getrennt, damit das Display nie auf das Netz wartet. Gib in `on_fetch` `false` zurück, wenn der Abruf nichts geliefert hat; dann werden die alten Daten nicht überschrieben.

**Wichtig fürs Widget:** Die Daten des Widgets müssen beim ersten Anzeigen da sein. Die Firmware hält das Dashboard bis zu 8 Sekunden zurück, bis `on_fetch` einmal Daten geliefert hat. Zeige in `on_widget` trotzdem eine ruhige Fallback-Anzeige („Noch keine Daten“), falls der Abruf scheitert.

### Externer Speicher (`storage.*`, API-Stufe 5)

Ein Paket mit einem Einstellungsfeld vom Typ `storagePath` kann Dateien auf dem externen Speicher des Geräts (FTP, WebDAV oder Google Drive, in den allgemeinen Einstellungen eingerichtet) ablegen und lesen. Den Ordner stellt der Nutzer im Store beim Feld ein; das Skript nennt nur den **Feldnamen** und einen **Dateinamen**, es kann also nie außerhalb seines Ordners zugreifen.

- `storage.ready()` → `true`, wenn ein externer Speicher eingerichtet ist.
- `storage.write(feld, name, text [, anhaengen])` → `true` oder `nil, Fehlertext`. `anhaengen = true` hängt an die Datei an, sonst wird sie überschrieben.
- `storage.read(feld, name)` → Text oder `nil, Fehlertext` (`"nicht gefunden"`, wenn es die Datei nicht gibt).

Grenzen: nur in `on_fetch` (nicht beim Zeichnen), höchstens 6 Zugriffe je Abruf, Dateien bis 32 KB, Dateinamen aus `a-z A-Z 0-9 _ - .` (nicht mit Punkt am Anfang, höchstens 40 Zeichen). Ohne Speicher liefert jeder Aufruf `nil, "kein externer Speicher eingerichtet"`; das Paket sollte das ruhig behandeln.

```lua
function on_fetch(ctx)
  if storage.ready() then
    local t = time.localtime()
    storage.write("dir", "verlauf.csv", string.format("%02d:%02d;%s\n", t.hour, t.min, tostring(ctx.cfg.wert)), true)
  end
  return true
end
```

### ctx

- `ctx.cfg.<key>`: Einstellungswerte (mit Standardwerten aus dem Manifest).
- `ctx.lang`: Anzeigesprache des Geräts, `"de"` oder `"en"`. Texte danach wählen.
- `ctx.clock24`: `true`, wenn das Gerät das 24-Stunden-Format nutzt (API-Stufe 2).
- `ctx.view` und `ctx.widgets` (API-Stufe 14, nur in `on_fetch`): Die Firmware lässt eine App nur abrufen, wenn sie angezeigt wird oder (bei aktivem Dashboard) ein Widget von ihr platziert ist. `ctx.view` ist dann `"app"` (die App ist angezeigt) oder `"dashboard"`; `ctx.widgets` ist die Liste der Optionsbits (`ctx.cfg.opt`, siehe Widget-Optionen) der platzierten Widgets dieser App. Hat eine App mehrere Quellen (Beispiel `sport-tabellen`: vier Sportarten), soll sie nur laden, was gerade sichtbar ist: bei `"app"` die angezeigte Quelle, bei `"dashboard"` die der Widgets; Bilder (`http.image`) nur bei `"app"`. Fehlt `ctx.view` (ältere Firmware), gilt der alte Ablauf.
- Manifest `"fetchOnOpen": true` (Firmware ab Build 603): Beim Öffnen der App (erste Anzeige nach dem Wegschalten) läuft `on_fetch` einmal auch dann, wenn die Daten noch frisch sind, mit `ctx.opened = true`. Das Skript soll dann nur Fehlendes nachladen (z. B. Wappen) und keine Daten neu abrufen; der Abruf-Takt der Daten verschiebt sich dadurch nicht.
- Manifest `"ownRedraw": true` (CHANGELOG 638): Die App zeichnet ihr Bild nach einem Abruf selbst (Diashow). Die Firmware startet dann den allgemeinen Bildwechsel-Timer der App nicht zusätzlich und zeichnet nach einem Abruf mit Fehler nur einmal die Fehleransicht, nicht bei jedem Wiederholversuch.
- Manifest `"queueTurns": true`: Drehknopf-Schritte (`on_input`-Rückgabe `"fetch"`) werden nicht blockierend an die VM gereicht, sondern gesammelt (Vorzeichen zählt) und beim nächsten Durchlauf zugestellt, auch wenn die VM gerade lädt. Klicks bleiben unmittelbar.
- Manifest `"cycleFetch": true`: Im Akku-Zeitgeberzyklus (jeder Aufwachvorgang ist ein neuer Start) läuft `on_fetch` genau einmal je Zyklus, wenn die Intervallzeit (mit Toleranz von `BAT_DUE_SLACK_SEC`) abgelaufen ist; das Öffnen-Fetch (`fetchOnOpen`) entfällt dann. Das Zeitbudget des Netzfensters (`BAT_CYCLE_NET_BUDGET_MS`) bricht lange `storage.*`-Aufrufe ab.
- Manifest `"fetchAnywhere": true` (CHANGELOG 644): ein per `on_http` angeforderter Abruf (`fetch = true`) läuft auch, wenn die App gerade NICHT auf dem Display steht (z. B. Rezept-Link aus Studio/Mac/iOS). Der normale Takt-Abruf bleibt an die Anzeige gebunden.
- Paket `rezepte`, `on_http` Op `"recipe"`: liefert das geladene Rezept vollständig (Titel, Zutaten mit skalierten Mengen, Schritte, Nährwerte) für die Anzeige in Handy-Seite/Studio; Op `"manual"` nimmt `title`, `yield`, `ingredients`, `steps` (eine Zeile je Eintrag).
- Manifest `"retrySeconds": N` (15..3600): Nach einem fehlgeschlagenen Abruf ohne Daten wird nach N Sekunden statt nach dem vollen Intervall erneut versucht.
- `http.request{url=..., keep={...}, skip={...}, maxBytes=...}` (API-Stufe 12): verschlankt eine **JSON-Antwort schon beim Empfang**. Die Firmware liest bis zu 512 KB Zeichen für Zeichen und gibt dem Skript nur das Wesentliche zurück: alle Objekte und Listen als Hülle, aber von den Objekt-Einträgen nur die Zeichenketten/Zahlen/Wahrheitswerte, deren Schlüssel in `keep` stehen; Unterbäume unter Schlüsseln aus `skip` entfallen ganz. So passt auch eine Antwort von über 200 KB (etwa ein Golf-Leaderboard mit dem ganzen Feld) in die 64-KB-Grenze, ohne dass dir Einträge hinten in der Liste fehlen. Schlüsselnamen: `a-z A-Z 0-9 _`, bis 32 Zeichen, höchstens 40 je Liste; `skip` braucht `keep`. Werte in Listen (z. B. `[1,2,3]`) bleiben erhalten. Beispiel: `golf-tour`.
- `asset.read(name)` (API-Stufe 11): liest eine **mitgelieferte Textdatei** des Pakets, z. B. Streckenlayouts, Tabellen oder Wappenlisten, die nicht dauernd im Lua-Speicher liegen sollen. Du legst die Datei als `store/apps/<id>/assets/<name>.txt` ab (`name`: `a-z 0-9 _ -`, bis 24 Zeichen; Datei bis 24 KB, das ganze Paket bleibt bei 96 KB); `tools/store_build.py` nimmt sie automatisch ins Paket. Im Skript liefert `asset.read("name")` den Text oder `nil`; lesbar in jedem Hook, zählt zu den 8 Dateizugriffen je Aufruf, nicht beschreibbar. Lies nur, was du brauchst: eine Zeile mit `string.find` herausholen statt die ganze Datei in Tabellen zu zerlegen. Beispiel: `formel-1` (`assets/tracks.txt`, eine Zeile je Rennstrecke).
- `file.write(name, text)` / `file.read(name)` (API-Stufe 10): eigene Dateien der App für größere Daten, die nicht in `ctx.data` passen (z. B. ein langes Rezept). `name`: `a-z 0-9 _ -`, bis 24 Zeichen; Datei bis 24 KB; höchstens 8 Zugriffe je Aufruf. `file.write` gibt `true` oder `nil, Fehlertext` zurück und geht nur in `on_fetch` (leerer Text löscht die Datei); `file.read` liefert den Text oder `nil` und geht in jedem Hook. Die Dateien liegen im Paketordner und verschwinden mit dem Paket (auch bei einem Paket-Update; nach dem Update holt `on_fetch` die Daten neu).
- `ctx.data.get(key)` / `ctx.data.set(key, wert)`: kleiner dauerhafter Speicher je App (bleibt über Neustarts). Werte: Text, Zahl, Wahrheitswert oder `nil` (löscht). Höchstens 16 Schlüssel, Text höchstens 1024 Bytes (längere werden abgeschnitten). Große Datenmengen gehören nicht hierher: speichere das Ergebnis, nicht die Rohantwort.

### Widget-Box

`on_widget(ctx, box)` bekommt den Innenbereich unter Rahmen und Titel (beides zeichnet die Firmware, ebenso die Markierung im Studio):

- `box.x`, `box.y`, `box.w`, `box.h`: Innenfläche. `y` ist die Oberkante unter der Titelzeile.
- `box.fh`: volle Widget-Höhe, daraus leitest du Größenstufen ab (z. B. ab 90 Pixeln auch Zusatzzeilen zeigen).
- `box.font`: Schriftstufe aus den Widget-Einstellungen: `-1` klein, `0` normal, `1` groß.

Zeichne nur innerhalb der Box. Wähle Inhalte nach Platz: klein = nur das Wichtigste, groß = mehr Details.

## 5. Zeichnen: `draw.*`

Das Display ist 800 × 480 Pixel, Nullpunkt oben links. Die obersten `draw.top` (48) Pixel gehören dem Standard-Kopf der Firmware, deine Fläche beginnt darunter.

| Aufruf | Wirkung |
|---|---|
| `draw.clear(farbe)` | füllt die Fläche unter dem Kopf |
| `draw.rect(x, y, w, h, farbe[, fuellen[, radius]])` | Rechteck, optional gefüllt und mit abgerundeten Ecken (Radius bis 40) |
| `draw.line(x1, y1, x2, y2, farbe)` | Linie |
| `draw.circle(cx, cy, r, farbe[, fuellen])` | Kreis |
| `draw.triangle(x1, y1, x2, y2, x3, y3, farbe[, fuellen])` | Dreieck |
| `draw.polygon({x1,y1, x2,y2, ...}, farbe[, fuellen])` | Vieleck, 3 bis 32 Punkte, standardmäßig gefüllt |
| `draw.text(x, y, text, schrift, farbe[, ausrichtung[, skalierung]])` | Text, `y` = Grundlinie |
| `draw.wrap(x, y, breite, text, schrift, farbe[, skalierung])` | umbrechender Text, gibt die Zeilenzahl zurück |
| `draw.measure(text, schrift[, skalierung])` | Textbreite in Pixeln |
| `draw.icon(name, x, y, groesse, farbe)` | Symbol (Abschnitt 7), `false` bei unbekanntem Namen |
| `draw.image(name, x, y[, w, h])` | Bild aus dem Paket (Abschnitt 8), `false` wenn nicht lesbar |
| `draw.qr(text, x, y, maxGroesse)` | QR-Code (API-Stufe 10): schwarze Module auf weißem Grund, Ecke oben links `x, y`, so groß wie in `maxGroesse` Pixel passt (ganze Pixel je Modul, höchstens 6). Gibt die Seitenlänge zurück, `nil` bei leerem/zu langem Text (über 190 Bytes) oder zu wenig Platz (unter 2 Pixel je Modul). Für Links zu Web-Seiten (Beispiel: `gericht-des-tages`). |
| `draw.image_size(name)` | Breite, Höhe des Bildes oder `nil` |
| `draw.width`, `draw.height`, `draw.top` | Maße (800, 480, 48) |

- Schriften: `"small"`, `"normal"`, `"medium"`, `"large"`, `"huge"`.
- Ausrichtung: `"left"`, `"center"`, `"right"`; das `x` ist dann linker, mittlerer oder rechter Punkt des Textes.
- Skalierung: ganze Zahl 1 bis 4 (vergrößert die Schrift).
- Gefüllt/leer: `true` füllt, `false`/weglassen zeichnet nur den Rand (außer bei `polygon`, dort ist gefüllt der Standard).
- Text kennt Latin-1 (Umlaute, ß, é ...) und Latin Extended-A (Polnisch, Tschechisch, Ungarisch, Kroatisch, Rumänisch, Türkisch ...: ł ć ń č ř ő ű ş ğ ...). Typografische Anführungszeichen und Striche werden automatisch zu ASCII, andere Zeichen (Kyrillisch, Griechisch, CJK) zu `?`. Kein Emoji.

### Farben

`color.BLACK`, `WHITE`, `GREEN`, `BLUE`, `RED`, `YELLOW` sind die sechs echten Display-Farben. Dazu die globale Akzentfarbe des Geräts, die der Nutzer einstellt:

- `color.ACCENT`: als Fläche.
- `color.ACCENT_TEXT`: als Schrift auf Weiß (immer gut lesbar).
- `color.ACCENT_INK`: Schrift auf einer `ACCENT`-Fläche.

**Nimm für Hervorhebungen die Akzentfarben statt fester Farben.** Dann passt deine App zu allen anderen Apps und zum gewählten Thema des Nutzers. Feste Farben nur dort, wo sie etwas bedeuten (rot = Warnung, grün = ok).

Das Display ist E-Paper mit 6 Farben: keine Verläufe, keine Transparenz, keine Graustufen. Flächen und klare Kanten wirken am besten.

## 6. Daten holen

Nur in `on_fetch`.

- `http.get(url[, maxBytes])` gibt Text zurück, oder `nil, fehlertext`. Nur https, nur Hosts aus `permissions.net`, höchstens 6 Abrufe je `on_fetch`, Antwort höchstens 24 KB (mehr wird abgeschnitten). Mit `maxBytes` (API-Stufe 8, 1024 bis 65536) erlaubst du längere Antworten; `json.decode` und `rss.parse` nehmen weiter höchstens 24 KB, die längere Antwort liest du dann mit Textmustern (`string.find`/`match`), z. B. wenn die interessanten Felder erst nach viel Zusatzdaten kommen (Beispiel: `wikipedia-today`).
- `http.request{url=, method=, body=, headers=, user=, pass=, bearer=}` (API-Stufe 6; `headers` erlaubt `Content-Type`, `Accept`, `Depth`, seit API-Stufe 13 `X-Auth-Token` bis 120 Zeichen, z. B. für football-data.org, und seit API-Stufe 15 `geofox-auth-type`/`-user`/`-signature`, siehe unten) gibt `{status=, body=}` zurück, oder `nil, fehlertext`. `method` ist `GET` (Standard), `POST`, `PUT`, `DELETE`, `PROPFIND` oder `REPORT`. `body` höchstens 8 KB. `headers` darf nur die genannten Header enthalten (`Depth`: `0`, `1`, `infinity`), andere lehnt die Firmware ab. Anmeldung entweder mit `user` und `pass` (Basic) oder mit `bearer` (Token); sie wird nie in der URL übergeben. Jede Antwort des Servers kommt als Tabelle zurück, auch `401` oder `500` (das Skript prüft `status`; bei `PROPFIND`/`REPORT` ist `207` der Erfolg); `nil` gibt es nur, wenn keine Antwort kommt oder die Anfrage nicht erlaubt ist. Die Adresse muss unter `permissions.net` (https, Port 443) oder über `permissions.netFrom` (Server aus einer `url`-Einstellung, auch http) freigegeben sein. Weiterleitungen (301/302/307/308, bis 3) folgt die Firmware selbst, sendet den Body erneut und prüft jedes Ziel gegen dieselbe Freigabe. Zählt wie `http.get` gegen die 6 Abrufe, Antwort höchstens 24 KB; mit `maxBytes=` (API-Stufe 9, 1024 bis 65536) erlaubst du längere Antworten, z. B. für einen ICS-Kalender, den du mit Textmustern liest (Beispiel: `waste-calendar`).
- **API-Stufe 15 (Firmware ab Build 613): signierte Anfragen.** `crypto.hmac_sha1(schluessel, text)` liefert die 20 Byte HMAC-SHA1 (roh), `crypto.sha1(text)` den SHA-1-Hash (roh), `crypto.base64(bytes)` die Base64-Form (Standard-Alphabet mit `=`); Eingabe je Aufruf bis 16 KB. Dazu erlaubt `http.request` die Header `geofox-auth-type`, `geofox-auth-user` und `geofox-auth-signature` (HVV Geofox GTI, je bis 120 Zeichen, nicht leer). So meldet sich ein Paket bei einem Dienst an, der statt eines Tokens eine Signatur über den Anfrage-Body verlangt; das Passwort selbst verlässt das Gerät nicht. Beispiel (`oepnv`):

```lua
local body = '{"language":"de","theName":{"name":"Berne","type":"STATION"}}'
local r = http.request{url = "https://gti.geofox.de/gti/public/checkName", method = "POST", body = body,
  headers = {["Content-Type"] = "application/json;charset=UTF-8", ["geofox-auth-type"] = "HmacSHA1",
    ["geofox-auth-user"] = ctx.cfg.hvvUser, ["geofox-auth-signature"] = crypto.base64(crypto.hmac_sha1(ctx.cfg.hvvPass, body))}}
```

Signiert wird genau der Text, der als `body` gesendet wird; das Paket baut ihn deshalb selbst als Zeichenkette (es gibt kein `json.encode`).
- `http.image(url, name[, maxW, maxH])` lädt ein JPEG oder PNG, rastert es auf die 6 Display-Farben und legt es unter `name` ab; danach zeichnest du es mit `draw.image(name, x, y)`. Gibt `true` zurück, oder `nil, fehlertext`. Standardgröße 200 × 200 (höchstens 40000 Pixel, das Seitenverhältnis bleibt, kleinere Bilder werden nicht vergrößert). Es zählt wie `http.get` gegen die 6 Abrufe, der Host muss in `permissions.net` stehen, **Weiterleitungen werden nicht verfolgt** (nimm die direkte Bildadresse), die Datei darf höchstens 300 KB groß sein, und jede App kann höchstens 12 Netz-Bilder gleichzeitig halten (Firmware ab Build 606, vorher 4) (ein vorhandener Name wird überschrieben, so aktualisierst du ein Cover). Nur in `on_fetch` erlaubt. Transparente PNG-Bereiche werden weiß.
- `recipe.fetch(url[, portionen])` (API-Stufe 10) lädt eine Rezeptseite und liest das maschinenlesbare schema.org/Recipe, das praktisch alle Rezeptseiten für Suchmaschinen einbetten. Das macht die Firmware selbst (sie liest bis zu 512 KB HTML zeichenweise, das ginge mit `http.get` nicht) und folgt Weiterleitungen, z. B. der Chefkoch-Zufallsadresse. Gibt eine Tabelle `{title, source, url, yield, time, keywords, base_servings, servings, ingredients = {Text, ...}, steps = {Text, ...}, nutrition = {{Name, Wert}, ...}}` zurück, oder `nil, fehlertext`. Mit `portionen` rechnet die Firmware die Mengen der Zutaten auf diese Zahl um (nur wenn die Seite ihre Original-Portionen nennt: `base_servings > 0`); `url` ist die tatsächlich geladene Seite (Permalink). Host muss in `permissions.net` stehen und zählt wie `http.get` gegen die 6 Abrufe; bis zu 40 Zutaten und 24 Schritte. Beispiel: `gericht-des-tages`.
- `json.decode(text)` gibt eine Lua-Tabelle zurück, oder `nil, fehlertext`.
- `rss.parse(text)` gibt eine Liste von Einträgen `{title=, link=, description=, pubDate=, ...}` (bis 20; auch Atom `<entry>`; Tags mit `:` bekommen `_`, also `merriam:shortdef` → `merriam_shortdef`).
- `text.strip_html(s)`, `text.url_encode(s)`.
- `time.sleep(ms)`: Pause, höchstens 1000 ms je Aufruf und 3000 ms je Lauf. Nötig, wenn du kurz hintereinander mehrere Server fragst (der ESP32 braucht Zeit für die nächste TLS-Verbindung).

Lokalzeit (API-Stufe 2): `time.localtime()` gibt eine Tabelle `{year, month, day, hour, min, sec, wday, week}` (wday 0=Sonntag … 6=Samstag, week = ISO-Kalenderwoche) oder `nil`, solange die Uhr nicht synchron ist. (Nicht `time.local` - das ist in Lua ein Schlüsselwort.)

Wetter (API-Stufe 3, nur Außenwetter des Geräts): `weather.get()` liefert die Wetterdaten, die das Gerät ohnehin für seine Wetter-Anzeige holt (Anbieter, Ort und Einheiten stellt der Nutzer in den Geräteeinstellungen ein; das Skript braucht keinen eigenen Abruf). Ergebnis: eine Tabelle `{location, temp, feels, humidity, cond, sunrise, sunset, wind, pressure, uv, visibility, aqi, aqi_label, hourly, daily, rain}` oder `nil, grund` mit `grund` = `"nolocation"` (kein Standort eingerichtet), `"loading"` (Daten noch nicht da) oder `"unavailable"`. Felder, die der Anbieter nicht liefert (z. B. `uv` bei OpenWeatherMap), fehlen (`nil`). `cond` ist `"clear"`, `"partly"`, `"cloudy"`, `"fog"`, `"drizzle"`, `"rain"`, `"snow"`, `"thunder"` oder `"unknown"`. `sunrise`/`sunset` sind Minuten seit Mitternacht, `wind` in km/h, `pressure` in hPa, `visibility` in km, `aqi` 1 (gut) bis 5 (sehr schlecht). `hourly` ist eine Liste `{hour, temp, cond}`, `daily` eine Liste `{wday (0=So), cond, min, max}`, `rain` eine Liste `{t, mm}` (Beginn des 15-Minuten-Blocks als Unix-Zeit, Niederschlag in mm). `draw.weather_icon(cond, cx, cy, größe)` zeichnet das Wettersymbol der Firmware um den Mittelpunkt (feste Farben, gedacht für weißen Grund). Lies die Daten in `on_draw`/`on_widget` (sie ändern sich ohne Skriptlauf); ein eigenes `on_fetch` ist nicht nötig.

Standort (API-Stufe 7): `weather.location()` gibt `{lat, lon, name}` des Gerätestandorts zurück (der Ort, den der Nutzer für die Wetter-App einstellt), oder `nil, "nolocation"`. Für Apps mit Umkreissuche (Tankstellen, Haltestellen); ein eigenes Ortsfeld braucht das Paket dann nicht.

Gemeinsame Bausteine: Pakete des Katalogs können eine `main.src.lua` mit Zeilen `--#include name` anlegen; `python3 tools/store_build.py` fügt dort `store/lib/name.lua` ein und schreibt daraus die `main.lua` (Bausteine: `text` Textfunktionen, `ui` Leerzustand/Zeilen/Kacheln/Tabelle).

Anleitung zu einem Einstellungsfeld (z. B. „Wie bekomme ich einen API-Key?“): Jedes Feld in `settings` darf `help` (die Schritte, je Zeile ein Absatz, bis 600 Zeichen je Sprache), `helpTitle` (Überschrift, bis 80 Zeichen) und `helpUrl` (Link, nur `https://`, bis 160 Zeichen) haben. Studio und die Apps zeigen das als aufklappbaren Block unter dem Feld (bei Feldern in einem Abschnitt nur als kurzen Hinweis; die Anleitung steht dann einmal im Abschnitt, siehe `sections`). Apps, die einen eigenen Schlüssel brauchen, sollten die Anleitung immer mitliefern; Beispiel: `"help": {"de": "1. Konto anlegen\n2. Key kopieren", "en": "1. Sign up\n2. Copy the key"}`.

Innen-Sensoren (API-Stufe 4): `sensor.get()` liefert `{temp, humidity, co2, battery?, room, seen, co2_warn_ppm, co2_warn, hum_low, hum_high, hum_warn}` des eingebauten Raumsensors oder `nil, "nodata"` (keine Messung). `sensor.peers()` ist eine Liste `{room, valid, temp, humidity, co2, battery?, seen}` der anderen InkBoards im Netzwerk mit frischer Meldung. `sensor.history([peer [, tage]])` liefert `{n, hours, temp={}, humidity={}, co2={}, time={}}` (bis 120 Punkte, `time` = Unix-Zeit) für dieses Gerät (`peer` 0/nil) oder das n-te Gerät aus `sensor.peers()`; ohne Verlauf `nil`. `battery` fehlt, wenn kein Akkustand bekannt ist. Die Warnschwellen und -Schalter sind Einstellungen des Pakets (Beispiel `weather-station`: `co2Warn`, `co2WarnPpm`, `humWarn`, `humLow`, `humHigh`); die Firmware übernimmt sie für `sensor.get()` und für den CO₂-Alarm im Netz-Task. Ein Paket mit mehreren Seiten bekommt die Seite als zweites Argument von `on_draw` (Beispiel: `weather-station`, Seite 1 Innen, 2 Außen, 3 Netzwerk; `ctx.cfg.page` überschreibt sie nur in Tests).

Pinnwand-Nachricht (API-Stufe 17, Firmware ab Build 621): `inbox.latest()` liefert die zuletzt empfangene Nachricht der Familien-Pinnwand oder `nil`, solange noch keine eingegangen ist. Ergebnis: `{sender, text, ts, room, at}`. `sender` und `text` sind die Zeichenketten (Absender bis 23, Text bis 159 Byte; das Gerät liefert eine Kopie), `ts` die Sendezeit als Unix-Sekunden (ganze Zahl), `room` der Ziel-Raum der Nachricht (`""` = alle Geräte) und `at = {year, month, day, hour, min, wday}` die **Ortszeit von `ts`** (wday 0=Sonntag; fehlt, wenn `ts` unbekannt ist). Die Ortszeit rechnet die Firmware mit der Zeitzone des Geräts aus, denn ein Skript kennt sonst nur die aktuelle Ortszeit aus `time.localtime()`; mit `at` lässt sich also auch eine Nachricht aus der Winterzeit richtig anzeigen. **Ablauf (API-Stufe 23, Firmware ab Build 663):** `inbox.latest(maxAlter)` mit `maxAlter` in Sekunden liefert `nil`, wenn die Nachricht älter ist (Beispiel Pinnwand: `inbox.latest(3 * 3600)`). Ist die Sendezeit oder die Uhr des Geräts unbekannt, bleibt die Nachricht erhalten; ohne Argument gilt wie bisher keine Frist. Die Firmware löscht nichts - die Nachricht bleibt gespeichert, jede App legt ihre eigene Frist fest. Die Funktion ist in allen Einstiegspunkten erlaubt, macht keinen Netzabruf und braucht keine Berechtigung.

**`inbox.send(sender, text, room)` (API-Stufe 19, Firmware ab Build 623):** sendet eine Nachricht wie der Studio-Knopf „Nachricht anpinnen“ und gibt `true` oder `nil, fehler` zurück. Nur in `on_action` erlaubt (der Nutzer hat den Knopf gedrückt), höchstens einmal je Aktion; in `on_draw`/`on_fetch` ein Skriptfehler. `sender` darf leer sein, `text` nicht (leer = `nil, "Die Nachricht ist leer."`); beide werden getrimmt und auf 23 bzw. 159 Byte gekürzt (UTF-8-sicher). `room` ist `""`/`"all"` (alle Geräte) oder eine Raum-Kennung (`wohnzimmer`, `flur`, `kueche`, `bad`, `schlafzimmer`); alles andere gilt als „alle Geräte“. Die Firmware speichert die Nachricht, zeigt sie auf diesem Gerät sofort als Unterbrechung (wenn es zum Ziel gehört), sendet sie per ESP-NOW an das InkBoard Netzwerk und legt sie für schlafende Geräte im Pinnwand-Ordner auf dem NAS ab; Text über 400 Byte weist die Funktion schon vorher ab. Beispiel: `store/apps/pinnwand-app` (Felder `sender`, `message`, `room`, Knopf am `info`-Feld `status`, Ordner-Feld `dir` mit `"device": "pinnwandFtpPath"`).

Der **Nachrichtendienst bleibt in der Firmware**: Senden (Studio-Knopf oder `inbox.send`), Empfang von anderen InkBoards (ESP-NOW, Ablage auf dem NAS), Raum-Ziel, Nachtruhe und die Unterbrechungs-Anzeige beim Eintreffen sind Systemdienste, keine App; ein Paket zeichnet nur die Anzeige. Ein Paket braucht deshalb kein `on_fetch`: `on_draw` ruft `inbox.latest()` bei jedem Zeichnen neu auf (nichts wird zwischengespeichert). Neu gezeichnet wird, wenn der Aktualisierungs-Takt des Pakets (`refreshMinutes`) abläuft und wenn die Unterbrechungs-Anzeige geschlossen wird, die bei jeder neuen Nachricht erscheint. Beispiel: `store/apps/pinnwand-app`.

Mehrere Seiten und Widgets (seit CHANGELOG 563): Es gibt keine eingebetteten Apps mehr, auch das Wetter ist ein normales Paket (`weather-station`) mit eigenem App-Platz. Ein Manifest listet seine Seiten in `pages` (Name, bei Bedarf Reihenfolge/Sichtbarkeit stellt der Nutzer wie bei jeder Skript-App ein); `on_draw(ctx, page)` bekommt die 1-basierte Seite. `draw.top` ist die erste freie Zeile unter der Kopfzeile, `ctx.cfg.style` der Seiten-Stil (`cards`, `flat`, `compact`, als Einstellung `style` des Pakets), `color.ACCENT` die Akzentfarbe. Ein Paket kann zusätzlich `on_widget` für ein Dashboard-Widget liefern; die Widget-Typen `weather_outdoor` / `weather_indoor` sind mit `"nativeWidgets"` im Manifest an dieses Paket gebunden (`ctx.cfg.widget`, dazu `ctx.cfg.opt` als Bitmaske der Widget-Optionen und `ctx.cfg.style`). Wetterdienst, API-Key, Abruf-Takt und Sensor-Verlauf sind Geräteeinstellungen (Studio und Apps: Einstellungen → Gerät & Standort → Wetter). Store-Vorschaubilder erzeugt `python3 tools/store_preview.py <id>` aus dem echten Skript.

Standard-Apps: Ein Manifest mit `"standard": true` (API-Stufe 2) lässt sich auf dem Gerät nicht entfernen (Firmware antwortet 403); Studio und Apps installieren fehlende Standard-Apps automatisch aus dem Katalog.

Zeit: `time.today()` gibt `"JJJJ-MM-TT"` oder `nil` (Uhr noch nicht synchron), `time.now()` Unix-Sekunden, `time.days_until("2027-01-01")` Tage bis zu einem Datum (negativ = vorbei) oder `nil`.

Zum Suchen von Fehlern: `log("text")` oder `print(...)` schreibt ins Geräte-Log (Geräte-Log, das auch das Studio anzeigt).

Beispiel:

```lua
function on_fetch(ctx)
  local body, err = http.get("https://api.example.org/today")
  if body == nil then log("Abruf: " .. tostring(err)); return false end
  local doc = json.decode(body)
  if type(doc) ~= "table" then return false end
  ctx.data.set("title", doc.title)
  ctx.data.set("value", doc.value)
end
```

## 7. Icons

`draw.icon(name, x, y, groesse, farbe)` zeichnet ein Vektor-Symbol in die Box `groesse × groesse` ab `x, y`, einfarbig, scharf in jeder Größe (ab 4 Pixeln; ab etwa 16 gut erkennbar). Namen:

`arrow_down arrow_left arrow_right arrow_up battery bell bus calendar chart check clock cloud cross drop flag fog fuel gear heart home image info list lock mail menu minus moon music news pause pin plane play plus rain search snow soccer star stop storm sun thermometer trend_up user warning wifi`

Mehrfarbige Symbole baust du aus zwei Aufrufen übereinander (z. B. Wolke in Schwarz, Tropfen in Blau) oder aus Formen.

### Bilder vom externen Speicher und im Arbeitsspeicher (API-Stufe 18, Firmware ab Build 622)

Für Apps mit eigenen Bildern auf dem NAS (Beispiel: `flight-radar`, Renderbilder und Logos):

- `storage.exists(feld, name)` → `true`, `false` oder `nil, Fehlertext`. Fragt nur die Größe ab, überträgt keine Datei. `name` darf einen Unterordner enthalten (`"logos/DLH.bmp"`, höchstens eine Ebene).
- `storage.image(feld, name, bildname [, opts])` → `breite, hoehe` oder `nil, Fehlertext` (`"nicht gefunden"`, wenn es die Datei nicht gibt). Lädt ein JPEG, PNG oder BMP aus dem Ordner, rastert es auf die sechs Farben und legt es unter `bildname` im Arbeitsspeicher ab; gezeichnet wird mit `draw.image(bildname, x, y [, w, h])`, die Größe liefert `draw.image_size(bildname)`.
- `http.image(url, name, w, h, {ram = true})` legt ein Netzbild ebenfalls im Arbeitsspeicher ab (bis 800 × 480 statt 40000 Pixel).
- `opts` (für beide): `w`, `h` (Zielbox, höchstens 800 × 480, das Seitenverhältnis bleibt), `up` (größte Vergrößerung in Prozent, 100 bis 400, Standard 100 = nie vergrößern), `style` (`"photo"` = Foto mit Bayer-Raster, `"cutout"` = Freisteller: PNG mit Transparenz, Grautöne als feste Muster, Farben als Vollton), `outline` (`color.BLACK`/`color.WHITE`: 2 Pixel Kontur um das Motiv, nur bei `cutout`).

Arbeitsspeicher-Bilder belegen 4 Bit je Pixel, sind flüchtig (nach einem Neustart weg: `draw.image_size` prüft, ob sie noch da sind, dann im nächsten `on_fetch` neu laden) und teilen sich ein festes Budget: höchstens 12 Bilder, 768 KB insgesamt, 800 × 480 je Bild.

Grenzen: `storage.exists` und `storage.image` zusammen höchstens 16 Aufrufe je Lauf und höchstens 30 Sekunden Gesamtzeit aller Speicherzugriffe; `storage.read`/`storage.write` zählen weiter extra (6 je Lauf). Plane Proben deshalb vorab (erst `exists` für alle Kandidaten, dann nur die gebrauchten Bilder laden) und merke dir „fehlt“ in `ctx.data`/`file.*`, damit ein fehlendes Bild nicht bei jedem Lauf neu abgefragt wird.

Weitere Erweiterungen der Stufe 18: `storage.*` und `file.write` sind auch in `on_action` erlaubt (Aktionsknöpfe, die etwas auf das NAS schreiben oder Zustand speichern). Ein `storagePath`-Feld kann mit `"fallback": "<anderes storagePath-Feld>"` auf den Ordner eines anderen Felds zurückfallen, solange es selbst leer ist (z. B. Auswertungen im selben Ordner wie die Bilder).

### Kalender: ICS-Dateien und Zeitrechnung (API-Stufe 20, Firmware ab Build 634)

- **`ics.fetch{sources={{url=..., tag=...}, ...}, from=, to=, max=160, maxBytes=1048576, limits={title=39, location=31, notes=55}, notesUntil=}`** holt einen oder mehrere ICS-Kalender und gibt `liste, info` zurück (statt `sources` geht auch `url=` für eine einzelne Quelle). Das Lesen macht die Firmware im Strom (die Datei liegt nie ganz im Speicher): Zeilenfaltung, `VEVENT` mit Wiederholungen (`RRULE` mit `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY` auch mit Zahl wie `1TH`/`-1FR`, `BYMONTHDAY`, `BYMONTH`, `BYSETPOS`), `EXDATE`, `RDATE`, geänderte Einzeltermine (`RECURRENCE-ID`), abgesagte Termine (`STATUS:CANCELLED`) und Zeitzonen (`TZID` mit IANA-Namen wie `Europe/Berlin` und den Windows-Namen von Outlook, `Z` = UTC, ohne Angabe = Ortszeit des Geräts; Sommerzeit wird beachtet, auch mitten in einer Serie). Serien bleiben bei ihrer Wanduhrzeit. `BYWEEKNO` und `BYYEARDAY` werden nicht unterstützt (die Serie zählt dann als Einzeltermin).
  - Jeder Eintrag der Liste ist `{start, end, allDay, title, location, notes, src, recur}`: Unix-Sekunden (ganztägig: Beginn/Ende des Tages in Ortszeit, `end` exklusiv), Texte nach `limits` gekürzt (Bytes, UTF-8-sicher), `src` = der `tag` der Quelle (Standard: ihre Nummer als Text), `recur` = gehört zu einer Serie. Die Liste ist nach `start` sortiert und enthält höchstens `max` (Standard 160, höchstens 200) Termine, die im Fenster `from`..`to` beginnen oder hineinreichen (Standard: ab jetzt, 45 Tage); bei Überlauf bleiben die frühesten. `notesUntil`: Notizen nur für Termine, die vor diesem Zeitpunkt beginnen (spart Platz). Damit bleibt das Ergebnis klein (höchstens 200 Termine mit je höchstens 39/31/55 Byte Text, zusammen unter 64 KB).
  - `info = {ok = {[tag] = bool}, err = {[tag] = Text}, truncated = {[tag] = bool}}`: eine Quelle, die nicht erreichbar oder nicht erlaubt ist, liefert **keine** (halben) Termine und `ok[tag] = false`; die anderen Quellen sind davon unberührt. `truncated[tag]` zeigt, dass Termine wegen `max` oder `maxBytes` fehlen. Die Fehlertexte nennen nie die Adresse.
  - Regeln: nur in `on_fetch`; höchstens 4 Quellen je Aufruf; **jede Quelle zählt als einer der 6 Netzabrufe** je `on_fetch`; die Adresse und jedes Weiterleitungsziel müssen in `permissions.net` oder über `permissions.netFrom` (Feld vom Typ `url`) erlaubt sein; eine Datei wird nach `maxBytes` (4 KB bis 2 MB) abgeschnitten; die Zeit je Aufruf ist auf etwa 20 Sekunden und die Netz-Frist des Akku-Zyklus begrenzt. Bei falschen Angaben gibt die Funktion `nil, Meldung` zurück.
  - Verhalten gegenüber dem Lesen mit Textmustern (`waste-calendar`) und der eingebauten Kalender-App: `EXDATE` und `RECURRENCE-ID` werden berücksichtigt, `TZID` wird gelesen (die eingebaute App behandelte die Zeit als Ortszeit), wöchentliche und tägliche Serien springen über den Zeitwechsel nicht mehr um eine Stunde.
- **`time.date(epoch)`** gibt `{year, month, day, hour, min, sec, wday, yday, week, isdst}` für einen Zeitpunkt in der **Zeitzone des Geräts** zurück (`wday` 0 = Sonntag, `yday` ab 1, `week` = ISO-Kalenderwoche, `isdst` = Sommerzeit). **`time.mktime{year, month, day, hour, min, sec}`** macht daraus wieder Unix-Sekunden (`hour`, `min`, `sec` fehlen = 0). Überlaufende Felder werden umgerechnet (`day = 0` = letzter Tag des Vormonats, `month = 13` = Januar des Folgejahres, `min = 90` = 1:30 später, negative Werte gehen rückwärts); so rechnest du „Tag + 1“, „Monatsanfang“ oder „Montag dieser Woche“ ohne eigene Kalenderformeln und ohne Fehler beim Zeitwechsel (ein Tag kann 23 oder 25 Stunden haben). `nil`, wenn ein Feld keine ganze Zahl ist, `year` außerhalb 1970..2200 liegt oder `month`/`day` fehlen. Unix-Zeiten sind in Lua 32-Bit-Zahlen: die Werte reichen bis 2038.
- **Erweiterungen mit Build 637:** `recurTo=` (Standard: `to`) begrenzt, bis wohin Wiederholungen ausgeklappt werden (Einzeltermine gelten weiter bis `to`; `calendar-app` nutzt jetzt + 45 Tage wie die alte App und `to` = unbegrenzt). `ics.fetch` ist jetzt auch in `on_action` erlaubt (Knopf „Quelle prüfen“: Abruf ohne zu speichern); der Text, den `on_action` zurückgibt, darf bis 400 Byte lang sein. **Seiten-Vorschau:** `POST /api/pkg-preview {"id", "page", "sample", "values"}` zeichnet eine Seite eines installierten Pakets mit der echten Zeichenfunktion und liefert das ganze Panel roh (4 Bit je Pixel wie `/api/widget-preview`, Header `X-Pv-*`); `values` sind die (auch ungespeicherten) Formularwerte, `sample: true` setzt `ctx.sample` (Beispieldaten). Studio zeigt sie als „Live-Vorschau vom Gerät“, sobald ein Feld `previewPage` hat. Nichts wird gespeichert oder abgerufen. **Sicherung:** seit Build 639 generisch für alle Pakete, siehe „Geräte-Sicherung der Skript-Apps“ unten (die Einstellungen von `calendar-app` als `calendarPackage` aus 637 liest der Import weiter).
- Beispiel: `store/apps/calendar-app` (Ablage der Termine in zwei Dateien, `on_header` für Woche und Monat, `ownDate` an den Seiten, Widget). Die ICS-Adressen stehen in vier `url`-Feldern (`netFrom`), `webcal://` wird automatisch zu `https://`.

### Spotify: Wiedergabestand und Cover (API-Stufe 21, Firmware ab Build 658)

Die Verbindung zu Spotify (Anmeldung per OAuth über den eingebauten HTTPS-Server des Geräts auf Port 8443, Token, Abfrage-Takt, Cover-Download) bleibt ein **Dienst der Firmware**: Zugangsdaten und Token gehören nie in ein Skript. Ein Paket bekommt nur die Anzeigewerte.

- **`spotify.now()`** (nur mit `"permissions": {"spotify": true}` im Manifest, sonst Skriptfehler) gibt `{connected, fetched, fetch_ok, track, playing, title, artist, album, progress_ms, duration_ms, cover, cover_rev}` zurück oder `nil, "unavailable"`. `fetched` ist `false`, bis der erste Abruf versucht wurde („Wird geladen“), `fetch_ok` `false` nach einem fehlgeschlagenen Abruf, `track` `false`, wenn nichts geladen ist. Texte sind auf 160 Byte begrenzt. Läuft in `on_draw` (nichts ins Netz, nur eine Kopie des Zustands).
- **`draw.image("spotify-cover", x, y[, w, h])`** und **`draw.image_size("spotify-cover")`** zeichnen das Cover des aktuellen Titels (Arbeitsspeicher-Bild). Das darf **jede App** ohne Berechtigung: das Cover ist nur zum Anzeigen da und nie lesbar. Gibt `false` zurück, solange kein Cover vorliegt; `cover_rev` zählt bei jedem neuen Cover hoch.
- **Verbindungskarte:** Das Einstellungsfeld `{"key":"verbindung","type":"connect","device":"spotify","label":{...}}` zeigt im Formular die Verbindung (siehe Tabelle der Feldtypen). Der Dienst ist über `GET/POST /api/spotify` und `POST /api/spotify-auth-start` erreichbar (Studio-Anmeldung wie sonst; das Secret kommt nur maskiert zurück).
- **Sicherheit:** Alle Verbindungen zu Spotify prüfen das Zertifikat gegen das CA-Bündel des ESP-IDF (ohne Rückfall auf „unsicher“; braucht die richtige Uhrzeit) und gehen nur zu `accounts.spotify.com`, `api.spotify.com` und den Cover-Servern (`*.scdn.co`), der OAuth-Ablauf trägt einen zufälligen `state` (10 Minuten gültig), Client-ID und -Secret werden vor dem Speichern geprüft.
- Beispiel: `store/apps/spotify` (Seite mit Cover, Stile Cards/Flat/Compact, Widget mit den Schaltern Fortschritt/Album/Kompakt).

### Dateilisten und große Fotos vom externen Speicher (API-Stufe 20, Firmware ab Build 632)

Für Apps, die die Bilder eines Ordners selbst durchlaufen (Beispiel: `bilder`, die Diashow vom NAS):

- `storage.list(feld [, opts])` → `{name, ...}, anzahl` oder `nil, Fehlertext`. Liefert die Dateinamen im Ordner des Felds (nur eine Ebene, keine Unterordner, keine Rekursion). `opts.ext`: Liste von Endungen ohne Punkt (1 bis 8 Einträge, je 1 bis 5 Zeichen `a-z 0-9`, Groß-/Kleinschreibung egal; Standard `{"jpg","jpeg","png","bmp"}`), `opts.max`: 1 bis 60 (Standard 60: die ersten so vielen passenden Dateien in der Reihenfolge der Antwort), `opts.sort`: nur `"name"` (aufsteigend nach Bytes, also Großbuchstaben vor Kleinbuchstaben und Umlaute hinten; ist auch der Standard). `anzahl` zählt alle passenden Dateien und kann über `#liste` liegen. Ordner, versteckte Dateien (Punkt am Anfang, z. B. macOS `._IMG.jpg`) und Namen über 159 Zeichen fehlen. Nur in `on_fetch`, `on_action` und `on_close`.
- **Dateinamen (R3):** Echte Foto-Namen wie `IMG 2024 (1).jpg` oder `Urlaub Müller.JPG` enthalten Leerzeichen, Umlaute und Klammern; die strenge Namensregel von `storage.exists`/`storage.read` (`a-z A-Z 0-9 _ - .`, 40 Zeichen) würde sie ablehnen. Darum gelten Namen, die `storage.list` im SELBEN Lauf geliefert hat, für `storage.image` und `storage.exists` unverändert (Merkliste je Lauf und Feld, genaue Übereinstimmung). Ein vom Skript selbst gebauter Name mit Sonderzeichen wird weiter abgelehnt. Sicher ist das, weil die Firmware nur Namen aufnimmt, die sie selbst aus dem Ordner gelesen hat und die ein einziger Pfadteil sind: kein `/` oder `\`, keine Steuerzeichen (auch kein Zeilenumbruch, der einen FTP-Befehl aufbrechen würde), kein Punkt am Anfang (`.`, `..`, versteckte Dateien), höchstens 159 Zeichen. Es gibt keinen Weg aus dem Ordner des Felds heraus.
- `storage.image` streamt JPEG und PNG im Foto-Stil (`style = "photo"`, Standard) jetzt Stück für Stück durch den Decoder, ohne die Datei im Speicher zu halten: die frühere Grenze von 200 KB entfällt. `opts.maxBytes` (1024 bis 16777216, Standard 8 MB) begrenzt die Dateigröße; größere Dateien werden mit einem Fehlertext abgelehnt. BMP und Freisteller (`style = "cutout"`) werden weiter als ganze Datei geladen (mit `maxBytes` als Obergrenze, vorher per Größenabfrage geprüft). Das Bild landet wie bisher als Arbeitsspeicher-Bild (4 Bit je Pixel, höchstens 800 × 480); das Foto-Raster ist dasselbe wie in der eingebauten Bilder-App.
- Grenzen: `storage.list` zählt zu den Proben (`exists`, `image`, `list` zusammen höchstens 16 je Lauf) und zur Gesamtzeit der Speicherzugriffe von 30 Sekunden je Lauf. Die Zeit wird vor jedem Zugriff geprüft, ein einzelnes großes Foto darf sie überschreiten (das Streaming bricht nur ab, wenn der Speicher zu lange keine Daten liefert: Lese-Timeout des Speicher-Backends, Fehlertext „Download abgebrochen“). Plane große Fotos deshalb als eigenen Lauf: ein Bild je `on_fetch`.
- Geräte-Bindung `"device": "imagesFtpPath"` an ein `storagePath`-Feld: der Ordner der Bilder (derselbe Wert wie „Bilder: Ordner“ der eingebauten Bilder-App und der Upload-/Einmal-Anzeige-Dienst im Studio). Wie bei `pinnwandFtpPath` liegt der Wert nicht im Paket, sondern in der Firmware (NVS `stg_img_path`, Standard `/inkboard/bilder`); `storage.*` mit dem Feldnamen nutzt ihn. Anders als bei normalen `storagePath`-Feldern sind hier auch Umlaute und Klammern im Ordnernamen erlaubt (höchstens 100 Zeichen, kein `..`, kein `\`, keine Steuerzeichen), weil die eingebaute App jeden Ordnernamen angenommen hat. Höchstens einmal je Paket. `store_build.py` und die Firmware prüfen die Bindung.

### Handy-Seite, Rezepte und Messwerte in Eingaben (API-Stufe 20, Firmware ab Build 633)

Für Apps, die wie die eingebaute Rezepte-App eine eigene Seite im Heimnetz anbieten (Beispiel: `rezepte`):

- **`on_http(ctx, req)` und Manifest `"http": {"page": "assets/phone.html", "api": true}`.** `GET /app/<id>` liefert die Seite aus `assets/` (nur Text, `.html`; ohne PIN, wie die Rezeptseite per QR-Code). `POST /app/<id>/api` ruft den Hook mit `req = {method, path, body}`; `body` ist höchstens 16 KB groß (sonst 413). Die Antwort ist `return {status=200, body="...", fetch=false}`; `status` 100 bis 599 (sonst 500), `body` höchstens 16 KB (sonst 413). Ohne Hook oder bei einem Skriptfehler antwortet die Firmware 404 bzw. 500. Der Aufruf braucht den Header `X-Requested-With` (wie `/api/recipe*`), aber keine PIN. Je Paket läuft höchstens ein Aufruf gleichzeitig, während eines Abrufs (`on_fetch`) oder bei besetzter Laufzeit antwortet die Firmware 503 (die Seite sollte kurz warten und es neu versuchen).
- **Was `on_http` darf:** `ctx.data` lesen und ändern, `file.read`/`file.write`, `time.*`, `json.decode`, `text.*`. **Nicht** erlaubt sind Netz (`http.*`, `recipe.fetch`, `storage.*`) und Zeichnen; die Zähler stehen auf dem Höchstwert. Wer etwas aus dem Netz braucht, merkt es sich in `ctx.data`/einer Datei und gibt `fetch=true` zurück: die Firmware stößt dann sofort `on_fetch` an (`scriptForceFetch`; läuft, sobald die App sichtbar ist). Erweiterung `redraw=true` im Ergebnis: das Display wird (nur wenn die App gerade angezeigt wird) neu gezeichnet.
- **`device.url([pfad])`** gibt die Adresse des Geräts im Heimnetz zurück, z. B. `http://192.168.1.50/app/rezepte` (ohne Pfad: die Seite des Pakets; mit Pfad `"/api"` oder `"api"`: `.../app/<id>/api`), sonst `nil` (keine IP bekannt). Geeignet für `draw.qr`.
- **`device.qrscreen(titel, hinweis)`** zeigt die einheitliche QR-Seite des Geräts (dieselbe wie „Noch keine App installiert“: InkBoard-Symbol, Titel, Hinweiszeile, QR-Code in der Karte, Netzwerk-Badge, Adresse, mDNS-Zeile) mit der Adresse der Handy-Seite des Pakets (wie `device.url()`). Liefert `true`; `nil`, wenn keine IP bekannt ist – dann zeichnet die App einen eigenen Hinweis. Die Seite überdeckt den ganzen Schirm, also einfach in `on_draw` aufrufen und mit `return` beenden. Für Leerzustände von Apps mit Handy-Seite verwenden, damit alle QR-Seiten gleich aussehen.
- **`recipe.scale(text, basis, ziel)`** rechnet die führende Menge einer Zutat um (`"200 g Mehl", 4, 2` → `"100 g Mehl"`, mit Brüchen und Dezimalkomma wie die eingebaute App). Basis und Ziel 1 bis 99; ohne erkennbare Menge, bei gleicher Basis/Ziel oder Text über 1024 Byte kommt der Text unverändert zurück.
- **`permissions.recipeAnyHost: true`** erlaubt `recipe.fetch` (nur das, nicht `http.*`) jeden https-Host, weil Rezeptseiten beliebig sind. Die Firmware prüft vor jedem Abruf und bei jedem Umleitungsziel (höchstens 3): nur https, nur Port 443, keine IP-Adressen (IPv4/IPv6), kein `localhost`, kein `.local` und keine Namen ohne Punkt; nach der Namensauflösung wird zusätzlich eine private oder lokale Zieladresse abgelehnt. Der Abruf zählt weiter zu den 6 Abrufen je `on_fetch`, ist nur ein GET ohne Zugangsdaten, und die Antwort wird ausschließlich als schema.org/Recipe gelesen. Ohne die Berechtigung gilt weiter `permissions.net`. Der Store zeigt die Berechtigung in der Beschreibung (Pflicht für Paketautoren).
- **`on_input` misst jetzt echt:** `draw.measure` (und `draw.wrap`) liefern in `on_input` (Drehrad/Klick, Kern 1) die Maße der echten Schriften, damit der Hook z. B. die Seitenzahl eines Layouts kennt. Gezeichnet wird dabei nichts. `on_action` misst weiter nicht.
- **Auch `on_http` misst echt (Firmware ab Build 636):** `draw.measure`/`draw.wrap` liefern im Webserver-Hook dieselben Maße wie beim Zeichnen (Beispiel: `rezepte` meldet der Handy-Seite die echte Seitenzahl). Gezeichnet wird weiter nichts.
- **Blätter-Modus melden: `ctx.data` „browse“ (Firmware ab Build 636).** Steht nach `on_input` (Rückgabe `true`) in `ctx.data` der Schlüssel `browse` auf `1`, führt die Firmware den Blätter-Modus der App wie bei den eingebauten Apps Rezepte/Bilder: grüne Kopfzeile, Umlauf bei laufender Aktualisierung gesammelter Rasten, Zurücksetzen beim App-Wechsel und automatisches Bestätigen nach 45 s ohne Bedienung (das Display wird dabei nicht neu gezeichnet). `browse` ist ein reservierter Schlüssel; Apps ohne ihn verhalten sich wie bisher. Die App zählt die 45 s für ihre eigene Anzeige selbst mit (Zeitpunkt der letzten Drehung in `ctx.data`, Vergleich mit `time.now()`), damit Hinweistext und Klickverhalten zur Firmware passen: ein Klick im Modus bestätigt (`true`, Schlüssel löschen), nach Ablauf der 45 s geht er eine Ebene hoch (`false`). Beispiel: `rezepte`.
- **Nutzerdaten überstehen Updates:** Beim Aktualisieren eines Pakets wird der Ordner ersetzt; nur `settings.json` bleibt immer erhalten. Zusätzlich behält die Firmware für `rezepte` die Datei `f_recipe.txt` (das geladene Rezept). Gelingt das Sichern nicht, bricht das Update ab und der alte Ordner bleibt unberührt.

## 8. Bilder (Logos, Fotos, Grafiken)

Bilder sind nur ein 6-Farben-Raster. Das Format heißt IBM (Dateiendung `.ibm`): Farben Schwarz, Weiß, Grün, Blau, Rot, Gelb plus „transparent“. Du erzeugst es einmal am Rechner aus einem normalen Bild; das Gerät muss keine PNGs entpacken.

Durchgespieltes Beispiel: Du willst das Logo `logo.png` in deiner App `meine-app` zeigen.

```
python3 tools/img2ibm.py logo.png store/apps/meine-app/assets/logo.ibm --width 120 --no-dither
python3 tools/store_build.py
```

Das Werkzeug braucht Pillow (`pip install pillow`). Optionen: `--width`/`--height` (Zielgröße, das Seitenverhältnis bleibt erhalten, wenn du nur eine angibst), `--no-dither` (harte Flächen, ideal für Logos und Zeichnungen), ohne diese Option rastert es Fotos mit Floyd-Steinberg (Punktmuster, wirkt wie Graustufen), `--preview vorschau.png` schreibt ein Bild, wie es auf dem Display aussieht. Durchsichtige Stellen im PNG bleiben transparent.

Im Skript:

```lua
function on_draw(ctx, page)
  draw.clear(color.WHITE)
  local w, h = draw.image_size("logo")
  if w then
    draw.image("logo", (draw.width - w) // 2, draw.top + 30)
  end
end
```

Der Name ist der Dateiname ohne `.ibm` (Kleinbuchstaben, Ziffern, `_`, `-`, bis 32 Zeichen). Mit `draw.image("logo", x, y, 60, 30)` wird das Bild auf diese Größe skaliert (einfach, ohne Glättung: besser gleich in Zielgröße erzeugen).

Grenzen: höchstens 40000 Pixel je Bild (z. B. 200 × 200), die fertige Datei höchstens 24 KB, das ganze Paket 96 KB. Einfarbige Flächen komprimiert das Werkzeug automatisch; Fotos mit Rastern belegen viel mehr Platz.

Für Symbole nimm besser `draw.icon`: kleiner, scharf, ohne Dateien.

**Bilder aus dem Netz** (Cover, Fotos) lädst du in `on_fetch` mit `http.image` (Abschnitt 6) und zeichnest sie wie jedes andere Bild:

```lua
function on_fetch(ctx)
  local json_text = http.get("https://api.example.org/now-playing")
  local doc = json.decode(json_text or "")
  if type(doc) ~= "table" then return false end
  ctx.data.set("title", doc.title)
  http.image(doc.cover_url, "cover", 160, 160)   -- Name "cover", höchstens 160 x 160
end

function on_draw(ctx, page)
  draw.clear(color.WHITE)
  if not draw.image("cover", 24, draw.top + 24) then
    draw.icon("music", 24, draw.top + 24, 120, color.ACCENT)  -- Platzhalter, solange noch kein Bild da ist
  end
  draw.text(200, draw.top + 80, ctx.data.get("title") or "", "large", color.BLACK, "left")
end
```

Fotos werden mit einem feinen Punktmuster gerastert (Dithering) und sehen auf dem Display dadurch wie Graustufen/Farben aus. Bilder von einem Heimnetz-NAS laden Pakete ab API-Stufe 18 mit `storage.image` (siehe oben).

## 9. Grenzen und Fehlerverhalten

- Ganzzahlen: Lua auf dem Gerät rechnet mit **32 Bit** (Host-Tests mit 64 Bit!). Ganzzahl-Literale über 2147483647 werden zu Gleitkommazahlen und scheitern bei `~`, `&`, `<<` und `%d` mit „number has no integer representation“; `tools/store_build.py` lehnt solche Literale ab. Für Hashes den Wertebereich klein halten, z. B. `h = (h * 31 + byte) % 8388593`. Unix-Zeit passt bis 2038.

- Rechenzeit: höchstens 2 Sekunden je Aufruf (Netzwartezeit zählt nicht mit). Danach bricht die Firmware das Skript ab.
- Speicher: höchstens 384 KB je Skript (Firmware ab Build 607, vorher 256 KB).
- Verfügbar sind nur die Lua-Bibliotheken `base`, `string`, `table`, `math` (kein `io`, `os`, `require`, `load`, `dofile`).
- Ein Skriptfehler (Fehlertext höchstens 200 Zeichen) betrifft nur diese App und landet im Geräte-Log; die übrigen Apps laufen weiter. Plane trotzdem immer einen Fallback ein.
- `on_fetch` ist in der Firmware mit einem Backoff geschützt: nach einem Fehler wartet die Firmware etwa 5 Minuten, bevor sie es erneut versucht.
- Es läuft immer nur ein Skript gleichzeitig. Zeichnen hat Vorrang; schreibe `on_draw` deshalb schnell (nichts rechnen, was `on_fetch` schon erledigt hat).

## 10. Gestaltung wie eine eingebaute App

- Seite: `draw.clear(color.WHITE)`, Inhalt in der Akzentfarbe des Geräts, große Zahlen mit `huge`, Erklärtexte mit `normal`/`small`.
- Ränder von mindestens 24 Pixeln, nichts in die Kopfzeile (`y < draw.top`) zeichnen.
- Texte immer in beiden Sprachen: `if ctx.lang == "en" then ... end`.
- Fehlende Daten zeigen („Wird geladen“, „Noch keine Daten“), nie leere Fläche oder Skriptfehler.
- Widgets: Titelzeile gehört der Firmware, Innenbereich kompakt, auf `box.fh` und `box.font` reagieren.
- Einstellungen sparsam halten: jede Option, die du weglässt, kann nicht falsch stehen.

## 11. Store-Eintrag (`store.json`)

```json
{
  "category": "time",
  "author": "Dein Name",
  "tagline": {"de": "Kurzzeile", "en": "One line"},
  "description": {"de": "Langer Text", "en": "Long text"},
  "features": {"de": ["Punkt 1", "Punkt 2"], "en": ["Point 1", "Point 2"]},
  "icon": "icon.svg",
  "previews": [
    {"kind": "display", "file": "preview-display.svg", "caption": {"de": "...", "en": "..."}},
    {"kind": "widget", "file": "preview-widget.svg", "caption": {"de": "...", "en": "..."}}
  ]
}
```

Kategorien stehen in `store/categories.json`. Vorschaubilder sind SVG oder PNG im Paketordner (`kind`: `display` oder `widget`). Optional `style` (`cards`, `flat`, `compact`) und `page` (0-basiert): Vorschau eines Seiten-Stils; daraus baut die Stil-Auswahl ihre Bilder. Oben im App-Detail zeigen Studio und Apps nur je eine Vorschau: die erste Bento-Vorschau (`style` `cards` oder ohne `style`), die erste Slate-Vorschau (`flat`) und die erste Widget-Vorschau (CHANGELOG 615); die Reihenfolge in `previews` entscheidet also, welche Seite oben erscheint. `python3 tools/store_build.py --check` prüft, ob alles zusammenpasst (läuft auch automatisch in den Tests).

## 12. Veröffentlichen

1. `version` im Manifest erhöhen, `python3 tools/store_build.py` ausführen.
2. Katalog in das öffentliche Repo `InkBoard-Apps` exportieren (`python3 tools/store_export.py <ordner>`, Anleitung in `store/README.md`).
3. Im Studio: Store → App aktualisieren.

Die Signatur der Pakete (Echtheitsprüfung) ist noch nicht eingebaut; dazu gehört auch, dass der Store später nur geprüfte Pakete aus dem offiziellen Repo anbietet.

## 13. Noch nicht möglich

- Bilder von einem Heimnetz-Server über `http.image` (nur https mit Host-Freigabe); Bilder vom eingerichteten externen Speicher gehen seit API-Stufe 18 mit `storage.image`. (Text-/XML-Abrufe vom Heimnetz-Server gehen seit API-Stufe 6 mit `http.request` und `permissions.netFrom`.)
- Eigene Schriften, Animationen und Antippen/Touch (das Gerät hat nur den Drehgeber).
- Zugriff auf Geräte-Sensoren und Daten der eingebauten Apps (Wetter, Abfahrten): kommen als Bausteine, sobald die eingebauten Apps migriert werden.
- (Erledigt seit API-Stufe 20: ein fertiger ICS-Parser, siehe `ics.fetch`. Kleine Kalender wie `waste-calendar` lesen ihre Datei weiter mit Textmustern.)
- Die Funktion `on_settings` (steht im Entwurf) (steht im Entwurf, ist aber noch nicht in der Firmware).

## Geräte-Sicherung der Skript-Apps (Build 639)

`GET /api/export-settings` hängt hinter die Geräte-Einstellungen den Schlüssel `packages` an, `POST /api/import-settings` spielt ihn zurück. Es gibt keine App-eigenen Sicherungs-Hooks: alles ergibt sich aus Manifest und Paketordner.

```
"packages": { "<paketId>": {
   "version":  "1.2.0",                         nur zur Information
   "settings": { "<feldKey>": wert, ... },      Werte aus settings.json (nur Schlüssel des Manifests)
   "paths":    { "<feldKey>": "/ordner", ... }, Felder vom Typ storagePath (stehen sonst zentral in /storage_paths.json)
   "slot":     { "enabled", "order", "refreshMin", "pageOrder", "pageEnabled", "pageThemeColorId", "pageLayoutStyleId" },
   "files":    { "f_recipe.txt": "<Text>" } } }  kleine Nutzerdaten (nur Dateien aus pkgKeepFileName, je Datei bis 24 KB)
```

- **Geheimnisse:** wie bei den übrigen Zugangsdaten stehen Felder vom Typ `password` in der vollständigen Sicherung im Klartext und fehlen bei `?secrets=0`; ein fehlender Wert beim Import heißt „aktuellen Wert behalten“. Adressen (`url`, z. B. ICS-Links) und Ordner zählen wie bei den Kalenderquellen der alten App nicht als Geheimnis. WLAN-Zugangsdaten und PIN-Hash sind weiterhin nie enthalten.
- **Firmware-Felder:** Felder mit Manifest-`device` (Pinnwand-Ordner `pinnwandFtpPath`, Bilder-Ordner `imagesFtpPath`) gehören der Firmware und stehen weiter unter `storagePinnwandFtpPath` bzw. `storageImagesFtpPath`; ebenso die geräteweiten Pfade (`_device` der Pfaddatei: `storageNetzwerkFtpPath`, `storageRefreshLogFtpPath`, `storagePinnwandFtpPath`). Sie sind nicht im Paketeintrag.
- **Import:** die Werte laufen durch dieselbe Prüfung wie das Formular (`pkgCoerceSetting`) gegen das Manifest des **installierten** Pakets. Ein ungültiger Einzelwert wird übersprungen (der Rest gilt), Schlüssel außerhalb des Schemas werden ignoriert, fehlende Schlüssel behalten den bisherigen Wert. Die Platz-Konfiguration wird über die Paket-Id dem Platz zugeordnet, den das Paket auf **diesem** Gerät belegt (Platznummern sind von Gerät zu Gerät verschieden; deshalb überspringt der Import die `pkgN`-Einträge von `apps`, sobald `packages` vorhanden ist).
- **Dateien:** nur Namen, die `pkgKeepFileName` für das Paket nennt (heute `f_recipe.txt` bei `rezepte`); das Rezept muss ein JSON-Objekt sein. Paketcode (`main.lua`, Manifest) wird nie zurückgespielt – Pakete selbst sind nicht Teil der Sicherung.
- **Paket fehlt:** der Eintrag wird als `/pkgpend_<id>.json` (höchstens 30 KB) auf dem Gerät vorgemerkt und beim nächsten Zuweisen eines Platzes (Installation) bzw. bei der Installation eines Pakets ohne Skript angewendet; die Datei wird dabei gelöscht. Hat das Paket zwar eine Installation, aber keinen Platz, wartet nur der Platz-Teil. Die Antwort des Imports nennt `{"success":true,"packages":{"applied":N,"pending":N,"skipped":N}}`; Studio zeigt die Zahl der vorgemerkten Pakete an.
- **Alte Sicherungen** (ohne `packages`): `storageFlightradarFtpPath`/`storageFlightradarCoveragePath` → `paths.dir`/`paths.cov` von `flight-radar` (der alte Standardordner `/inkboard/flugzeuge` und ein leerer Auswertungsordner setzen den Standard des Pakets); `calendarSources` und die Sicherung aus 637 (`calendarPackage`) → `settings` von `calendar-app`; die `apps`-Einträge `flightradar`, `pinnwand`, `calendar`, `images`, `recipe` → `slot` von `flight-radar`, `pinnwand-app`, `calendar-app`, `bilder`, `rezepte` (die Stelle in der Reihenfolge nur für die entfernten Apps). Die Umsetzung (`pkgBackupLegacyBuild`) ist rein und im Host-Test (`test_pkg_backup.cpp`) geprüft.
