# Plan: Tasker-Addon für Godot

Stand: 2026-10-06. Noch nichts umgesetzt, dieses Dokument hält das vereinbarte Design fest.

## Ziel

Ein Editor-Addon, das Tasker in Godot integriert: Aufgaben sehen, suchen und managen, ohne den Editor zu verlassen. Kernstück ist der **Tisch**, eine verspielte Kartenansicht des laufenden Milestones. Gamification ist ausdrücklich gewünscht.

Leitlinie: Der Tisch darf Tasker frei interpretieren, muss aber im Wesentlichen kompatibel bleiben. Alles, was er anzeigt und ändert, bildet sich auf vorhandene Tasker-Felder ab. Zusätzlicher Zustand, den Tasker nicht kennt, bleibt lokal im Addon.

## Arbeitsweise

- Das Addon entsteht in diesem Projekt (`tasker-godot`), in reinem GDScript. Grund: Es läuft unabhängig vom Build-Zustand des Spiels und in jedem Godot-Projekt.
- Tasker wird von hier nur gelesen: `C:\Users\tomat\Documents\Projects\Web\tasker`.
- Änderungen an Tasker macht die Sitzung „Tasker-Godot Integration“. Anfragen gehen als abgeschlossene Nachricht dorthin, jeweils erst nach Freigabe durch den Nutzer. Freigegeben wird einzeln und nur, was konkret gebraucht wird.

### Wo was in Tasker steht

| Thema | Datei |
|---|---|
| Datentypen | `src/shared/model.ts` |
| Schemas für Anlegen und Ändern | `src/shared/api.ts` |
| Routen | `src/server/routes.ts` |
| Token-Freigaben | `src/server/index.ts` (`TOKEN_ROUTES`, `TOKEN_READ_ROUTES`) |
| Änderungs-Strom | `src/shared/events.ts` |
| Tischregeln | `src/shared/tisch.ts`, Tests in `src/shared/tisch.test.ts` |
| Sperren, Fortschritt, Checkliste, Titelbild-Vererbung | `src/shared/blocking.ts`, `progress.ts`, `checklist.ts`, `inherit.ts` |
| Aussehen der Karten | `src/client/ui/Cards.tsx` (`CardFace`), `cards.css` |
| Tisch in der Web-App | `src/client/ui/Tisch.tsx`, `tisch.css`, `tischFx.ts` |

## Schnittstelle zu Tasker

Anmeldung mit Zugangs-Token aus dem Tasker-Profil: `Authorization: Bearer tsk_…`. Schreibende Anfragen tragen den Header `x-tasker-client`, damit der eigene Hall im Änderungs-Strom übergangen werden kann.

Per Token freigegeben (laut Tasker-Sitzung gepusht mit Commit `dc5877d` und deployt; aus dem Addon heraus noch nicht geprüft):

| Route | Methoden | Zweck im Addon |
|---|---|---|
| `/api/bootstrap` | alle | Gesamtstand laden, zugleich Verbindungstest (200 gültig, 401 ungültig) |
| `/api/events` | alle | Änderungs-Strom (SSE) |
| `/api/kind/<kind>[/<id>[/archive\|restore]]` | alle | Anlegen, Ändern, Löschen, Archivieren |
| `/api/move` | alle | Verschieben und Umsortieren |
| `/api/bilder/<id>` | nur GET | Titelbilder, `?v=klein` für die Vorschau |
| `/api/settings` | nur GET | liefert per Token nur `{ "velocity": n }` (Wochenziel) |

Alles andere antwortet mit Token 401, darunter `/api/me`, `/api/steps`, `/api/bulk`, Papierkorb, Archiv-Suche und die Galerie.

Was daraus folgt:

- **Konflikte:** Jede Änderung nennt die `version`, auf der sie beruht. Bei 409 liefert der Server den aktuellen Stand mit, das Addon übernimmt ihn und zeigt einen Hinweis.
- **Kein Löschen im ersten Ausbau:** Der Papierkorb ist per Token gesperrt, ein Löschen ließe sich aus Godot nicht zurückholen. Archivieren geht.
- **Mehrere Änderungen auf einmal** (etwa Umsortieren im Spiel) laufen als einzelne Anfragen, weil `/api/steps` gesperrt ist.
- **`bootstrap` liefert alle Projekte.** Das Addon filtert auf das eingestellte Projekt.
- **Bilder** sind über ihren Inhalts-Hash adressiert und ändern sich nie. Sie werden dauerhaft nach ID auf der Platte zwischengespeichert.

## Aufbau des Addons

Vier Teile unter `addons/tasker/`:

| Schicht | Aufgabe |
|---|---|
| **Client** | HTTP, Token, Fehlercodes, Bild-Abruf mit Zwischenspeicher, später der Änderungs-Strom |
| **Datenbestand** | hält den Stand des Projekts, wendet Antworten und Ereignisse an, meldet Änderungen per Signal |
| **Regeln** | reine Funktionen: Zonen des Tischs, Sperren, Stapel, Fortschritt, Titelbild-Vererbung |
| **Oberfläche** | Dock, Such-Popup, Tisch, Kartenszene |

Grundsätze:

- Objekte bleiben Dictionaries, so wie sie als JSON kommen. Eigene Klassen je Typ müssten bei jeder Modelländerung in Tasker nachgezogen werden.
- Die Regeln werden aus Tasker nach GDScript portiert und bekommen Tests nach Vorlage von `tisch.test.ts`. Sie hängen nicht an der Darstellung, damit eine spätere 3D-Ansicht sie mitbenutzen kann.
- Dock, Suche und Tisch teilen sich einen Datenbestand und eine Kartenszene.

### Einstellungen

| Wo | Was |
|---|---|
| `EditorSettings` (gilt für alle Projekte auf dem Rechner) | Server-URL, Zugangs-Token |
| Projekt-Metadaten des Editors (unter `.godot/`, nicht versioniert) | Projekt-ID |
| Addon-Einstellungen | Handgröße (Vorgabe 7), Ton an/aus |
| Lokaler Zustand je Projekt | welche Karten auf der Hand liegen, aufgefächerte Stapel |

Ein Einrichtungsdialog fragt URL und Token ab, prüft die Verbindung und lässt das Projekt aus der Liste wählen.

## Orte im Editor

- **Dock:** die Hand, der laufende Milestone und die Suche. Bleibt beim Arbeiten an der Szene sichtbar.
- **Suche als Popup:** Eintrag in der Befehlspalette mit Tastenkürzel. Gesucht wird lokal in Titel, Beschreibung, Tags und `$`-Nummer.
- **Tisch:** eigenes Fenster des Editors, per Knopf geöffnet. Es gehört zum Editor-Prozess, belegt den Play-Modus nicht und lässt sich auf einen zweiten Monitor schieben.

## Der Tisch

Darstellung in 2,5D: flache Karten mit Kippen, Anheben und Schatten. Echtes 3D bleibt als spätere Option offen.

### Zonen

| Zone | Inhalt | Tasker-Entsprechung |
|---|---|---|
| **Hand** (unten, aufgefächert) | offene Karten, die gezogen wurden | Teil von „Offen“ |
| **Nachziehstapel** (links) | die übrigen offenen Karten des Milestones | Rest von „Offen“ |
| **Tisch** (Mitte, sieben Plätze als Richtwert) | gespielte Karten | „Im Spiel“, Status „In Progress“ |
| **Gesperrt** (links, angekettet) | Karten mit offener Voraussetzung oder Status „Blockiert“ | „Gesperrt“ |
| **Erledigt-Stapel** (rechts) | Erledigtes, das zuletzt Erledigte obenauf | „Erledigt“ |

Die Trennung von Hand und Nachziehstapel kennt Tasker nicht. Sie ist lokaler Zustand des Addons.

### Züge

| Zug | Wirkung in Tasker |
|---|---|
| Nachziehstapel anklicken | keine, eine Karte kommt auf die Hand (lokal) |
| Handkarte auf den Nachziehstapel | keine, sie wandert darunter (lokal) |
| Nachziehstapel ansehen, Karte gezielt ziehen oder tauschen | keine (lokal) |
| Handkarte auf den Tisch | Status „In Progress“ |
| Karte vom Tisch zurück auf die Hand | Status „Offen“ |
| Karte auf den Erledigt-Stapel | Status „Erledigt“ |
| Karten auf dem Tisch umsortieren | `playOrder` |
| Stapel anklicken | fächert die Unteraufgaben auf (lokal) |

### Regeln

- **Ziehen per gewichtetem Zufall:** Karten mit hoher Prio und weit vorn in der Plan-Reihenfolge kommen wahrscheinlicher.
- **Handgröße:** einstellbar, Vorgabe sieben. Ist die Hand voll, muss erst gespielt oder zurückgelegt werden.
- **Gesperrte Karten** werden nie gezogen. Wird die Voraussetzung erledigt, springt die Kette auf und die Karte kommt in den Nachziehstapel.
- **Stapel:** Eine Aufgabe mit Unteraufgaben ist eine dicke Karte. Sie wird als Ganzes gezogen, kommt aber nie auf den Tisch. Gespielt werden ihre Unteraufgaben.
- **Erledigt** ist eine Karte erst, wenn alles darunter erledigt ist (Unteraufgaben und Checkboxen der Beschreibung). Abgelehnte Züge federn zurück und sagen, warum.
- **Aktiver Milestone:** der mit Status „In Progress“, je Projekt höchstens einer. Ohne aktiven Milestone ist der Tisch leer und bietet an, den nächsten geplanten zu starten.

### Karten

Wie in Tasker: Titelbild füllt die Karte und ist oben abgedunkelt, Titel mit schwarzer Kontur, Markierungs-Emoji vor dem Titel, Fuß in der Farbe des Status, Prio, Zähler für Unteraufgaben und Checkliste, Segmentbalken, Schloss bei gesperrten Karten. Das Titelbild folgt der Kette Projekt → Markierung → Kategorie → Aufgabe → Unteraufgabe.

### Gamification

- **Wochenziel und Serie:** Anzeige am Tischrand gegen das Tempo aus den Tasker-Einstellungen, Flamme für Wochen in Folge, Funken beim Erreichen.
- **Ablage je Woche:** Der aufgedeckte Erledigt-Stapel zeigt, was wann erledigt wurde, mit bester Woche.
- **Seltenheit über Prio:** Karten mit hoher Prio bekommen einen Folien-Schimmer.
- **Milestone als Runde:** Fortschritt als Rundenanzeige, Abschluss-Moment mit der letzten Karte.
- **Bewegung und Ton:** Austeilen beim Öffnen, Ziehen, Ablegen, Kette. Ton abschaltbar.

## Reihenfolge

### Schritt 1: Fundament

Gebaut am 2026-10-06. Geprüft sind die Regeln (22 Tests), das Laden des Addons im Editor ohne Fehler und das Aussehen von Karte und Tisch mit Beispieldaten. Noch nicht gegen den echten Server gelaufen sind Verbindung, Bild-Abruf, Ändern und Konfliktbehandlung; im Editor selbst noch nicht angesehen sind Einrichtungsdialog und Tischfenster.

- [x] Addon-Gerüst, Einstellungen, Einrichtungsdialog mit Verbindungstest (`plugin.gd`, `core/config.gd`, `ui/setup_dialog.gd`)
- [x] Client und Datenbestand: Laden, Ändern, Konfliktbehandlung (`core/client.gd`, `core/store.gd`)
- [x] Bild-Abruf mit Zwischenspeicher auf der Platte (`core/images.gd`)
- [x] Regeln portieren, mit Tests (`rules/`, Tests in `tests/`)
- [x] Karte (`ui/card.gd`, im Code aufgebaut statt als `.tscn`)
- [x] Prototyp: Editor-Fenster mit animierten Karten (`ui/table_window.gd`)
- [x] Gegen den echten Server ausprobiert (Nutzer, 2026-10-06): Verbindung, Milestone und Titelbilder kommen an, das Tischfenster läuft im Editor mit 145 Bildern pro Sekunde. Ändern und Konfliktbehandlung sind weiterhin ungetestet, der Prototyp ändert noch nichts.

Tests laufen mit `godot --headless --path . -s tests/run_tests.gd`. `tests/snapshot.gd` öffnet den Tisch mit Beispieldaten und speichert ein Bild nach `.godot/tasker_snapshot.png`.

### Schritt 2: Dock und Suche

- [ ] Dock mit Hand und laufendem Milestone
- [ ] Statuswechsel und Bearbeiten der wichtigsten Felder
- [ ] Suche im Dock und als Popup über die Befehlspalette
- [ ] Neuladen bei Fokus und per Knopf

### Schritt 3: Tisch

- [ ] Fenster mit den fünf Zonen
- [ ] Ziehen zwischen den Zonen, Umsortieren auf dem Tisch
- [ ] Nachziehstapel: ziehen, zurücklegen, ansehen, tauschen
- [ ] Stapel auffächern
- [ ] Erledigt-Stapel und abgelehnte Züge
- [ ] Grundlegende Bewegung

### Schritt 4: Gamification

- [ ] Wochenziel, Serie, Ablage je Woche
- [ ] Folien-Schimmer, Effekte, Ton
- [ ] Abschluss eines Milestones

### Schritt 5: Änderungs-Strom

- [ ] `/api/events` über `HTTPClient`, damit Änderungen aus der Web-App sofort ankommen

### Später

- **Planen am Tisch** und **Abhängigkeiten als Fäden:** siehe die eigenen Abschnitte unten.
- **Aufgaben aus Godot anlegen:** offen, ob und wie. Bisher entstehen Aufgaben in der Web-App oder über MCP, das Addon arbeitet mit vorhandenen.
- **Karten in Szenen:** Aufgaben an Szenen und Nodes hängen und im 2D- und 3D-Editor einblenden, siehe den eigenen Abschnitt unten.
- **Hand auch in Tasker:** Würde ein eigenes Feld in Tasker brauchen. Die Umbenennung „Offen/Im Spiel“ in „Hand/Tisch“ dort ist eine offene Idee.
- **Echtes 3D** als zweite Darstellung.

## Ausbau: Planen am Tisch

Noch nicht eingeplant, hier als Skizze festgehalten. Derselbe Tisch, nur herausgezoomt. Ein Umschalter wechselt zwischen „Spielen“ und „Planen“.

### Aufteilung

- **Matten:** Jeder Milestone ist eine Spielmatte, in Plan-Reihenfolge von links nach rechts. Die aktive ist hervorgehoben und zeigt Fortschritt und Restzeit, geplante zeigen die Prognose aus dem Tempo.
- **Decks:** „Ready“ und „Backlog“ liegen als Stapel am Rand. Ein Klick fächert ein Deck auf, im Backlog nach Gruppen.
- **Leere Matte am Ende:** Eine Karte dort abgelegt legt einen neuen Milestone an.

### Züge

| Zug | Wirkung in Tasker |
|---|---|
| Karte auf eine Matte | Verschieben in den Milestone (`/api/move`) |
| Karte zurück aufs Deck | Verschieben ins Backlog oder nach „Ready“ |
| Karte zwischen zwei Karten | Reihenfolge |
| Matten umsortieren | Plan-Reihenfolge der Milestones |
| Karte auf die leere Matte | Milestone anlegen, dann verschieben |

Die Routen dafür sind per Token schon freigegeben, an der Datenhaltung ändert sich nichts.

### Ideen dazu

- **Milestone starten als Ritual:** Die Matte des nächsten Milestones rückt in die Mitte, die Karten werden gemischt und der Nachziehstapel gebildet.
- **Überfüllte Matte:** Liegen mehr Karten auf einer Matte, als das Tempo bis zum Enddatum hergibt, ragen die überzähligen heraus.
- **Backlog durchsehen als Spiel:** Karten einzeln aufdecken und wegwischen: bleibt im Backlog, geht nach „Ready“ oder in einen Milestone.
- **Trophäen:** Abgeschlossene Milestones bleiben als zugeklappte Decks mit ihrer besten Woche am Rand liegen.

### Vorher nachzusehen

- wie Tasker die Prognose rechnet (`src/shared/schedule.ts`)
- ob das Umsortieren von Milestones Nebenwirkungen auf Start- und Enddaten hat

## Ausbau: Abhängigkeiten als Fäden

Noch nicht eingeplant. Abhängigkeiten (`deps`) werden als Fäden zwischen Karten sichtbar und bearbeitbar, in der Spiel- wie in der Planungsansicht.

- **Einblendbar:** Ein Schalter zeigt die Fäden. Ohne ihn erscheinen nur die Fäden der Karte unter dem Zeiger.
- **Richtung:** Der Pfeil zeigt auf die wartende Karte.
- **Karte im Stapel:** Liegt die Voraussetzung im Nachziehstapel oder auf einer anderen Matte, führt der Faden dorthin.
- **Faden ziehen:** Von einer Karte zu einer anderen ziehen legt die Abhängigkeit an. Die wartende Karte wird damit gesperrt und wandert unter die Kette.
- **Faden trennen:** Klick auf den Faden entfernt die Abhängigkeit.
- **Erledigt:** Wird die Voraussetzung erledigt, löst sich der Faden und die Kette springt auf.
- **Kreise:** Ein Faden, der einen Kreis schließen würde, wird abgelehnt. Ob der Server das selbst prüft, ist noch nachzusehen.
- **Offen:** Milestones haben ein eigenes `deps`-Feld. Ob Fäden in der Planungsansicht auch Matten verbinden, ist nicht entschieden.

## Ausbau: Karten in Szenen

Noch nicht eingeplant. Vorhandene Aufgaben bekommen Referenzen auf Szenen und Nodes. Der 2D- und 3D-Editor blendet die Karten an diesen Stellen ein, im Spiel ist davon nichts zu sehen.

### Festgelegt

- **Szenendateien bleiben unberührt.** Die Referenz steht an der Aufgabe, nicht in der Szene. Keine Marker-Nodes, keine Metadaten.
- **Nur Szenen und Nodes** als Ziel. Skripte, andere Dateien und freie Positionen ohne Node sind nicht vorgesehen.
- **Nur vorhandene Aufgaben verknüpfen.** Ob und wie Aufgaben aus Godot heraus angelegt werden, ist offen.
- **Erst lokal, dann Tasker:** Die Referenzen liegen zunächst im lokalen Zustand des Addons. Wenn sich die Form bewährt hat, bekommt Tasker Tabelle, Routen und Token-Freigabe, und die lokalen Referenzen wandern hinüber. Ziel ist, dass die Referenz in der Tasker-Datenbank steht, auch wenn die Web-App sie nicht anzeigt.

### Aufbau einer Referenz

Stabile Kennung für Godot und lesbare Form nebeneinander, damit die Referenz auch außerhalb von Godot etwas sagt (etwa für MCP).

| Feld | Beispiel | Wozu |
|---|---|---|
| Art | Szene oder Node | |
| UID der Szene | `uid://b4x…` | übersteht Umbenennen und Verschieben der Datei |
| Pfad der Szene | `res://levels/level2.tscn` | lesbar, vom Addon aktuell gehalten |
| Node-Pfad | `Enemies/Boss` | lesbar |
| Node-Nummer | falls verfügbar | stabil gegen Umbenennen des Nodes |
| Node-Typ | `CharacterBody3D` | für Infos und Selbstheilung |
| Versatz der Karte | Vektor | wohin die Karte vom Node weggeschoben wurde |

### Einen Node wiederfinden

Der Node-Pfad bricht beim Umbenennen und Umhängen. Dagegen:

- **Feste Node-Nummern:** Neuere Godot-Versionen schreiben eine eindeutige Nummer je Node in die Szenendatei. Ob 4.7 das tut und das Addon daran kommt, ist zu prüfen.
- **Mitführen:** Solange das Addon läuft, zieht es Umbenennen und Umhängen im Editor in der Referenz nach.
- **Selbstheilung:** Fehlt ein Pfad, sucht das Addon nach Name und Typ und schlägt die neue Stelle vor.

### Darstellung

- **Projizierte Karten:** dieselbe Kartenszene wie im Dock und am Tisch, als Bild gerendert und eingeblendet. In 2D und bei UI-Elementen als Überlagerung am Node, in 3D als Fläche im Raum, die sich zur Kamera dreht. Reine Editor-Hilfsobjekte, keine Nodes.
- **Wegschieben:** Karten lassen sich vom Node wegziehen, damit sie nichts verdecken. Ein Faden verbindet Karte und Node, der Versatz wird an der Referenz gemerkt.
- **Lesbarkeit:** Weit herausgezoomt schrumpft die Karte zu einem Pin in Statusfarbe, mehrere nah beieinander werden zu einem Stapel.
- **Filter in der Viewport-Leiste:** alle, nur der laufende Milestone, nur die Hand, oder aus.
- **Erledigtes:** Karten erledigter Aufgaben verblassen.

### Bedienen

- **Verknüpfen:** Kontextmenü am Node oder Karte aus dem Dock auf den Node ziehen.
- **An der Karte:** Klick wählt aus, Doppelklick öffnet, Rechtsklick wechselt den Status.
- **„Zeig mir, wo“:** Von der Karte in Dock oder Tisch zur Szene springen und den Node auswählen.
- **Dock-Abschnitt „In dieser Szene“:** die Aufgaben der offenen Szene.

### Vorher zu prüfen

- Node-Nummern in Godot 4.7 und der Zugriff darauf
- Einblenden in 3D (Gizmos oder ein anderer Weg) und Ziehen der Karten im Viewport
- wie weit das Kontextmenü des Szenenbaums für Addons offen ist und ob sich Karten auf Viewport und Szenenbaum ziehen lassen

## Risiken und offene Punkte

- **Animationen im Editor-Fenster:** Der Editor zeichnet sparsam neu. Ob Karten dort flüssig laufen, klärt der Prototyp in Schritt 1. Ausweichweg wäre ein eigener Prozess, mit den Nachteilen, dass das Token durchgereicht werden muss und die Autoloads des Spiels mitstarten.
- **Regeln doppelt:** Die Tischregeln gibt es dann in Tasker und im Addon. Ändert Tasker sie, muss das Addon nachziehen. Die Tests sollen das auffangen.
- **Markdown in Beschreibungen:** Godot rendert keines. Zunächst Rohtext, Bilder in Beschreibungen werden nicht angezeigt.
- **Größe von `bootstrap`:** Bei sehr großem Bestand wäre ein Projektfilter am Server sinnvoll. Das wäre eine Anfrage an die Tasker-Sitzung.
- **Inhalt des Docks:** Für den ersten Wurf bleibt es bei Hand, laufendem Milestone und Suche. Weitere Wünsche fürs Dock kommen später.

## Mockups

Grobe Skizzen der Aufteilung, nicht des Aussehens. Die Titel auf den Karten sind erfundene Beispiele. Der Ordner `docs/` ist per `.gdignore` vom Godot-Import ausgenommen.

| Ansicht | Datei |
|---|---|
| Spielen: Hand, Tisch, Nachziehstapel, Erledigt-Stapel | [docs/mockups/tisch-spielen.svg](docs/mockups/tisch-spielen.svg) |
| Planen: Milestones als Matten, Ready und Backlog als Decks | [docs/mockups/tisch-planen.svg](docs/mockups/tisch-planen.svg) |
| Abhängigkeiten als Fäden | [docs/mockups/tisch-faeden.svg](docs/mockups/tisch-faeden.svg) |
