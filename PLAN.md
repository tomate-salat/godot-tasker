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
| `/api/zeichnungsbild` | nur GET | eine Zeichnung als PNG, beim Abruf gerendert (`taskId` oder `milestoneId`, `name`, optional `kante`, `thema=dunkel`). Lokal in Tasker gebaut, Stand 2026-10-06 noch nicht deployt |

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
- Die Regeln werden aus Tasker nach GDScript portiert und bekommen Tests nach Vorlage von `tisch.test.ts`. Sie hängen nicht an der Darstellung.
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

Darstellung in 2,5D: flache Karten mit Kippen, Anheben und Schatten. Dabei bleibt es; eine echte 3D-Darstellung des Tischs ist nicht geplant (Nutzer, 2026-10-07).

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

- **Sofort, nicht erst nach der Antwort:** Ein Zug steht mit dem Loslassen im Stand (`Store.patch` wendet die Änderung gleich an) und wird zurückgenommen, wenn Tasker ablehnt – wie beim Verteilen in der Planung (Nutzer, 2026-10-07). Bis die Antwort da ist, lässt sich die Karte nicht erneut greifen. Das gilt für jede Änderung über `patch`, auch Status im Dock und im Aufgabenfenster.

### Regeln

- **Ziehen per gewichtetem Zufall:** Karten mit hoher Prio und weit vorn in der Plan-Reihenfolge kommen wahrscheinlicher.
- **Handgröße:** einstellbar, Vorgabe sieben. Ist die Hand voll, muss erst gespielt oder zurückgelegt werden.
- **Gesperrte Karten** werden nie gezogen. Wird die Voraussetzung erledigt, springt die Kette auf und die Karte kommt in den Nachziehstapel. Erscheint eine gesperrte Karte neu auf dem Tisch – etwa als Unteraufgabe eines aufgefächerten Stapels –, gleitet sie von den gesperrten Karten her ein, nicht vom Nachziehstapel: sonst sieht sie aus, als wäre sie zu haben. Beim Ziehen zeigt die Zone unter der Karte, ob sie dort hin darf: grün wie bisher, oder rot mit dem Grund am unteren Rand – dieselben Regeln, nach denen das Ablegen ablehnt. Auch die Hand rückt beim Ziehen auseinander und zeigt die Lücke, in der die Karte landet; eine Karte aus dem Spiel bekommt ihren Platz am Ende.
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

Gebaut am 2026-10-06. Geprüft sind die Suche (Test), das fehlerfreie Laden der Skripte und das Aussehen des Dock-Inhalts mit Beispieldaten. Im Editor selbst noch nicht ausprobiert: das Andocken, das Ändern gegen den Server, Such-Popup, Tastenkürzel und das Neuladen bei Fokus.

- [x] Dock mit laufendem Milestone als Karten in den Abschnitten „Im Spiel“, „Offen“, „Gesperrt“ (`ui/dock.gd`), Vorgabe als Tab neben dem Inspektor. Die Hand kommt mit Schritt 3, bis dahin zeigt „Offen“ alle offenen Karten.
- [x] Aufgabenfenster (`ui/task_window.gd`): Ein Doppelklick auf eine Karte oder einen Suchtreffer, ein Klick auf einen Verweis oder eine Unteraufgabe öffnet die Aufgabe in einem eigenen Fenster. Je Aufgabe gibt es eines; ist es schon offen, kommt es nach vorn. Titel und Beschreibung sind Anzeige, Status und Prio änderbar. Im Dock selbst gibt es keine Einzelheiten mehr, Statuswechsel dort per Rechtsklick auf die Karte. Titel und Beschreibung zu bearbeiten kommt später. Escape schließt das Fenster.
- [x] „In Tasker öffnen“: öffnet die Aufgabe in der Web-App im Browser, im Kontextmenü der Karte und im Aufgabenfenster.
- [x] Zeichnungen in Beschreibungen: Tasker rendert sie auf Anfrage als PNG (`GET /api/zeichnungsbild`, nach Besitzer und Name, dunkles Thema) und speichert nichts dazu. Das Addon merkt sich das Bild je Version der Zeichnung; die Versionen kommen mit `drawings` aus `bootstrap`. Eingebaut, aber ungetestet: die Route ist auf Tasker-Seite noch nicht deployt.
- [x] Beschreibung als gerendertes Markdown (`ui/markdown.gd`, eigener kleiner Übersetzer nach BBCode): Überschriften, Listen, Checklisten, Zitate, Code, Hervorhebungen, Links, Galerie-Bilder und Verweise wie `$142`, die anklickbar sind. Tabellen bleiben als Text stehen.
- [x] Suche im Dock und als Popup (`ui/search_popup.gd`, `rules/search.gd`): Befehlspalette „Tasker: Aufgabe suchen“ oder Strg+Alt+T, änderbar in den Editor-Einstellungen unter Tastenkürzel.
- [x] Neuladen per Knopf und beim Zurückkehren in den Editor, höchstens alle 15 Sekunden
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

### Schritt 3: Tisch

Gebaut am 2026-10-07. Geprüft sind die Regeln für Hand und Nachziehstapel (Tests) und der Tisch mit Beispieldaten: Ziehen, Auffächern, Ausspielen, Ablegen, ein abgelehnter Zug und der aufgedeckte Stapel, jeweils über die Zug-Funktionen und per Bildprobe. Nicht geprüft: das Ziehen mit der Maus selbst und alles gegen den echten Server.

- [x] Fenster mit den fünf Zonen und der Schublade für aufgefächerte Stapel (`ui/table_window.gd`)
- [x] Ziehen zwischen den Zonen setzt den Status, Umsortieren auf dem Tisch setzt `playOrder`, Umsortieren in der Hand ist lokal
- [x] Nachziehstapel: Klick zieht per gewichtetem Zufall (`rules/hand.gd`), Handkarte auf den Stapel legt sie darunter, „Ansehen“ deckt ihn auf zum gezielten Ziehen und Tauschen. Die Handgröße kommt aus den Editor-Einstellungen (`tasker/hand_size`).
- [x] Stapel auffächern: Klick auf einen Stapel in der Hand öffnet die Schublade, Unteraufgaben werden von dort ausgespielt
- [x] Erledigt-Stapel und abgelehnte Züge mit Hinweis; die oberste Karte des Stapels lässt sich zurückholen
- [x] Grundlegende Bewegung: Gleiten, Anheben in der Hand, Kippen beim Ziehen
- [x] Lokaler Zustand je Milestone in den Projekt-Metadaten (`core/memory.gd`); das Dock zeigt Hand und Nachziehstapel daraus
- [x] Doppelklick auf eine Karte öffnet ihr Aufgabenfenster
- [x] Milestone-Fenster (`ui/milestone_window.gd`, 2026-10-07): Ein Klick auf den Milestone-Titel in Dock oder Tisch öffnet es. Status, Fortschritt in Segmenten, Zeitraum, Beschreibung mit Zeichnungen, Burnup-Diagramm (`rules/burnup.gd`, `ui/burnup_chart.gd`, aus `milestoneLog` im Stand) und die Aufgaben. Alles Anzeige, der Status wird hier bewusst nicht geändert. Geprüft per Test und Bildprobe mit Beispieldaten, nicht gegen den Server.
- [x] Bildfenster (`ui/image_window.gd`, 2026-10-07): Ein Klick auf ein Bild oder eine Zeichnung in einer Beschreibung zeigt es groß, mit Zoom per Mausrad und Verschieben per Ziehen. Es nutzt das schon geladene Bild (Zeichnungen mit 1600 Pixeln Kantenlänge); größer nachladen ginge über den Parameter `kante` der Route bis 4000. Lädt fehlerfrei, im Editor noch nicht ausprobiert.
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07). Was an der Bewegung störte, wurde mit Schritt 4 behoben (Kippen, Schimmer, Landeplatz, Ablage).

Die Kette über den gesperrten Karten und das Austeilen beim Öffnen kamen mit Schritt 4.

### Schritt 4: Gamification

Gebaut am 2026-10-07. Geprüft per Bildprobe mit Beispieldaten: Wochenziel und Serie im Kopf, die Ablage, die Kette, der Schimmer und der Hinweis beim Lösen einer Kette. Nicht geprüft, weil sie sich in einem Standbild nicht zeigen: Töne, Funken, aufsteigender Text und das Austeilen. Im Editor noch nicht ausprobiert.

- [x] Wochenziel und Serie im Kopf des Tischs, das Ziel ist das Tempo aus den Tasker-Einstellungen
- [x] Ablage je Woche (`ui/shelf.gd`): Ein Klick auf den Erledigt-Stapel deckt ihn als Feld über dem ganzen Tisch auf, mit Wochenziel, bester Woche, Serie und der Uhrzeit je Karte. Alle Wochen, scrollbar. Hier wird nur angesehen: Karten lassen sich nicht ziehen, ein Doppelklick öffnet die Aufgabe. Auch vom Stapel selbst lässt sich nichts mehr herausziehen (Nutzer, 2026-10-07: Karten gerieten aus Versehen zurück ins Spiel); den Status ändert man im Aufgabenfenster.
- [x] Kippen beim Ziehen wie `cardTilt.ts` in Tasker: Die Karte neigt sich in die Bewegungsrichtung (höchstens 11 Grad, die Hälfte von Tasker, träge nachgeführt) und richtet sich auf, wenn der Zeiger steht. Ohne echte Tiefe: sie wird in der Kipprichtung schmaler, und Licht und Schatten auf der Karte zeigen, welche Seite zurückweicht.
- [x] Folien-Schimmer für Karten mit hoher Prio: nur beim Ziehen, der Lichtstreifen wandert mit der Neigung (`ui/card.gd`). Der regelmäßige Streifen in Ruhe war zu viel.
- [x] Landeplatz im Spiel: Beim Ziehen über den Tisch rückt die Reihe auseinander und der Platz leuchtet, an dem die Karte landet. Maßgeblich ist die Mitte der gezogenen Karte, nicht der Zeiger. Der Nutzer will das auch in Tasker; beschrieben an die Tasker-Sitzung am 2026-10-07.
- [x] Nachziehstapel mit eigener Kartenrückseite (blau, Rautenmuster); ein leerer Stapel zeigt „leer“.
- [x] Effekte: „+1“ und Funken am Erledigt-Stapel, Funken und Hinweis beim Erreichen des Wochenziels und beim Lösen einer Kette. Ausgelöst wird durch den Vergleich mit dem letzten Stand, also auch bei Änderungen aus Dock oder Web-App.
- [x] Abschluss eines Milestones: Schriftzug, Funken und Ton, sobald nichts mehr offen, im Spiel oder gesperrt ist
- [x] Kette über den gesperrten Karten: zwei gekreuzte Stahlketten mit Messingschloss
- [x] Karten werfen einen Schatten, der beim Anheben in der Hand und beim Ziehen wächst (`lift` an der Karte)
- [x] Austeilen beim Öffnen: die Karten fliegen nacheinander an ihren Platz. Gezogen wird weiterhin von Hand.
- [x] Töne (`ui/sounds.gd`): Ziehen, Ausspielen, Erledigt, Ablehnung, Kette, Wochenziel, Abschluss. Sie werden errechnet, das Addon bringt keine Tondateien mit. Abschaltbar über `tasker/sound` in den Editor-Einstellungen.
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

### Schritt 5: Änderungs-Strom

Gebaut am 2026-10-07. Geprüft per Test (Zerlegen der Ereignisse, Anwenden auf den Stand) und gegen einen Probe-Server auf dem Rechner: Verbinden, Empfangen, ein über zwei Stücke verteiltes Ereignis, Erkennen des eigenen Halls, Abriss und Neuverbindung nach drei Sekunden. Nicht geprüft: die verschlüsselte Verbindung zu Railway und der Lauf im Editor.

- [x] `/api/events` über `HTTPClient` (`core/events.gd`): Der Strom bleibt offen und verbindet sich nach einem Abriss neu, mit wachsendem Abstand von 3 bis 30 Sekunden. Bleibt das Lebenszeichen 70 Sekunden aus, gilt die Verbindung als tot. Bei 401 wird nicht neu versucht.
- [x] Anwenden im Datenbestand (`Store.apply_event`): geänderte und gelöschte Objekte werden eingesetzt, „neu laden“ und geänderte Zeichnungen holen den ganzen Stand, das Tempo folgt den Einstellungen. Der eigene Hall wird übergangen.
- [x] Nach einer Neuverbindung wird der ganze Stand geholt, weil in der Lücke etwas passiert sein kann.
- [x] Solange der Strom steht, entfällt das Neuladen beim Zurückkehren in den Editor. Der Neuladen-Knopf im Dock zeigt grün, dass er steht.
- [x] Im Editor gegen Railway ausprobiert (Nutzer, 2026-10-07)

### Später

- **Planen am Tisch:** eingeplant, siehe den eigenen Abschnitt unten.
- **Abhängigkeiten als Fäden:** am Spieltisch fraglich, siehe unten.
- **Aufgaben bearbeiten:** eingeplant, siehe den eigenen Abschnitt unten. Den Anfang macht die Beschreibung.
- **Aufgaben aus Godot anlegen:** offen, ob und wie. Bisher entstehen Aufgaben in der Web-App oder über MCP, das Addon arbeitet mit vorhandenen.
- **Karten in Szenen:** Aufgaben an Szenen und Nodes hängen und im 2D- und 3D-Editor einblenden, siehe den eigenen Abschnitt unten.

## Ausbau: Planen am Tisch

Derselbe Tisch, nur zum Planen statt zum Spielen. Ein Umschalter wechselt zwischen „Spielen“ und „Planen“. Das Bild dahinter: Planen ist Decks bauen, Spielen ist das Deck ausspielen. Skizze: `docs/mockups/planen-vorrat-unten.svg`.

### Festgelegt

- **Nichts anlegen.** Aus Godot heraus entstehen weder Aufgaben noch Milestones. Verteilt wird, was es gibt.
- **Zwei Sammelordner nebeneinander,** einer für den Vorrat, einer für die Decks, jeder nach hinten umgeschlagen: zu sehen ist eine Seite mit drei Spalten Fächern, in jedem Fach eine Karte in voller Größe. Die Ringe greifen um die linke Kante, dahinter schauen Deckel und umgeblätterte Seiten hervor, rechts stehen die Registerblätter. Eine umgeblätterte Seite schwenkt um die Ringe nach hinten, ohne Ton. Verworfen: ein gemeinsamer Ordner für beides (eine umgeblätterte linke Seite wäre rechts gelandet, wo etwas anderes liegt). Ausprobiert und verworfen: zwei aufgeschlagene Ordner mit Doppelseiten. In einem schmalen Fenster werden beide Ordner im Ganzen kleiner.
- **Rechts die Decks.** Jeder eingeplante Milestone hat sein Registerblatt und seine eigenen Seiten: auf einer Seite stecken nur Karten eines Milestones, der nächste beginnt auf einer neuen. Über der Seite stehen Titel, Fortschritt und Prognose. Aufgeschlagen wird zuerst der laufende Milestone.
- **Abgeschlossenes** behält sein Registerblatt und eine Seite mit Kopfzeile, ohne Karten, und verschwindet, sobald der Milestone in Tasker archiviert ist.
- **Links der Vorrat.** Zwei Reiter über dem Ordner wählen „Ready“ oder „Backlog“. Jede Gruppe hat ihr Registerblatt und ihre eigenen Seiten mit Kopfzeile, genau wie ein Milestone bei den Decks. Ein Klick auf ein Registerblatt blättert nur. Eine Hand gibt es hier nicht: die gehört zum Spieltisch, Planen ist Deckbauen (Nutzer, 2026-10-07).
- **Unteraufgaben** zeigt nur das Auffächern der Karte darüber, im Vorrat wie in den Decks.
- **Abhängigkeiten ohne Linien in der Hauptansicht.** Gesperrte Karten tragen ein Schloss. Es ist gelb, wenn die Karte wartet, und rot, wenn sie auf etwas wartet, das in einem späteren Deck oder noch im Vorrat liegt.
- **Der Graph einer Karte auf Wunsch:** Ein Klick aufs Schloss (oder der Rechtsklick, auch bei Karten ohne Sperre) zeigt über den Decks, worauf die Karte wartet und was auf sie wartet, über alle Stufen, aufgebaut wie der Graph in Tasker. Jede Karte nennt, wo sie liegt. Gezogen wird aus dem Graphen nicht: er liegt über den Ordnern, es gäbe kein Ziel.
- **Abhängigkeiten nur ansehen.** Anlegen und Trennen bleibt vorerst in Tasker.
- **Karten verteilen:** in ein Deck (auch in das laufende), zwischen zwei Karten, zurück in den Vorrat.
- **Decks umsortieren:** entfällt, siehe unten.

### Schritte

#### Schritt 1: Ansehen

- [x] Prognose aus Tasker (`schedule.ts`) als Regel mit Tests
- [x] Umschalter „Spielen / Planen“ im Tisch-Fenster
- [x] Decks als Ordnerseiten rechts, je Milestone ein Registerblatt und eigene Seiten
- [x] Vorrat als Ordnerseite links, mit den Reitern „Ready“ und „Backlog“ und Registerblättern für die Gruppen
- [x] Unteraufgaben auffächern
- [x] Schloss an der Karte, gelb und rot
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

#### Schritt 2: Der Graph einer Karte

- [x] Graph über alle Stufen mit Ortsangabe je Karte: Klick aufs Schloss, oder Rechtsklick auf eine Karte und „Abhängigkeiten zeigen“
- [x] Doppelklick im Graphen öffnet die Karte. Der einfache Klick, der zur Karte blätterte, ist wieder raus (Nutzer, 2026-10-07: erst hinspringen und dann ansehen ergibt keinen Sinn)
- [x] Stufen nach dem längsten Weg, Pfeile als Bögen mit eigenen Anschlüssen und um Knoten herum; Aufbau animiert, über die Pfeile des Knotens unter dem Zeiger wandern Punkte
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

#### Schritt 3: Karten verteilen

- [x] Karte ziehen: in ein Fach (sie nimmt diesen Platz ein), auf ein Registerblatt (ans Ende), auch in den anderen Ordner – in ein Deck, in eine Gruppe von „Ready“ oder „Backlog“, oder an eine andere Stelle im selben (`/api/move`)
- [x] Leere Gruppen, Kategorien und „Unsortiert“ haben im Vorrat weder Seite noch Registerblatt. Ihr Registerblatt erscheint, solange eine Karte gezogen wird, damit man etwas hineinlegen kann
- [x] Beim Ziehen lässt sich mit dem Mausrad weiterblättern und auf einer anderen Seite ablegen
- [x] Im Editor gegen Tasker ausprobiert (Nutzer, 2026-10-07)
- [x] Gezogen wird wie am Spieltisch: die Karte selbst hängt am Zeiger und kippt in die Bewegungsrichtung, im Fach bleibt ein blasses Abbild, am Ziel rücken die Karten zur Seite
- [x] Die Karte liegt sofort am neuen Platz, Tasker erfährt es gleichzeitig; geht der Zug nicht, gleitet sie zurück

#### Stapel auffächern

Stand 2026-10-09. Zuerst reihten sich die Unteraufgaben einer aufgefächerten Karte in die Fächer dahinter ein. Stand die Karte im letzten Fach, lagen sie auf der nächsten Seite, und alles dahinter verschob sich (Nutzer: unintuitiv und unübersichtlich). Jetzt bleibt der Ordner, wie er ist:

- [x] Ein Klick auf einen Stapel zieht ihn aus seinem Fach (`ui/fan_view.gd`). Erst langsam und ganz gerade nach oben, als holte man die Karte vorsichtig aus der Tasche eines Sammelordners; sobald er ganz draußen ist, nimmt er ohne anzuhalten Fahrt auf und gleitet im Bogen in die Mitte. Erst wenn der Stapel dort liegt, gleiten die Unteraufgaben nacheinander unter ihm hervor an ihre Plätze. Zurück läuft alles rückwärts: die Unteraufgaben verschwinden nacheinander unter dem Stapel, die zuletzt erschienene zuerst, dann gleitet er über sein Fach und langsam hinein (Nutzer, 2026-10-09). Im Fach bleibt solange ihr blasses Abbild.
- [x] Der Stapel leert sich: mit jeder Unteraufgabe, die unter ihm hervorkommt, rücken seine hinteren Kanten unter die Karte, bis nur die oberste bleibt. Gleiten sie zurück, füllt er sich wieder (`Card.pile`). In der Tasche des Ordners liegt ein Stapel knapp und gerade (`Card.tight`) und hat rundum Luft zum Rand.
- [x] Beliebig tief: ein Klick auf einen Stapel im Fächer rückt ihn nach oben neben seine Eltern-Karte, und seine Unteraufgaben fächern sich auf. Oben liegt der Weg als Karten, darunter steht er als Text.
- [x] Zurück: Escape oder ein Klick auf die Karte, deren Unteraufgaben aufgefächert sind, geht eine Ebene hinauf; ein Klick auf eine frühere Karte des Wegs springt dorthin. Ein Klick daneben schließt: alles sammelt sich ein, und die Karte gleitet zurück in ihr Fach.
- [x] Doppelklick öffnet die Aufgabe, Rechtsklick zeigt das Menü mit den Abhängigkeiten. Gezogen wird im Fächer nicht – Unteraufgaben wandern mit ihrer Karte.
- [x] Klick oder Doppelklick: ein Klick auf einen Stapel fächert erst auf, wenn nach 0,3 s kein zweiter folgt – ein Doppelklick öffnet nur die Aufgabe, die Karte bleibt im Fach. Dasselbe gilt für die Karten im Fächer. Kommt der zweite Klick später, geht der schon geöffnete Fächer wieder zu

#### Nicht gebaut: Decks umsortieren

Entschieden am 2026-10-07: wird nicht gebraucht. Die Plan-Reihenfolge der Milestones ändert man weiter in Tasker; eine neue Route dort entfällt damit.

### Ideen für später

- **Milestone starten als Ritual:** Das nächste Deck rückt in die Mitte, die Karten werden gemischt und der Nachziehstapel gebildet.
- **Überfülltes Deck:** Liegen mehr Karten in einem Deck, als das Tempo bis zum Enddatum hergibt, ragen die überzähligen heraus.
- **Backlog durchsehen als Spiel:** Karten einzeln aufdecken und wegwischen: bleibt im Backlog, geht nach „Ready“ oder in ein Deck.
- **Trophäen:** Abgeschlossene Decks zeigen ihre beste Woche.

### Nachgesehen in Tasker

Gelesen am 2026-10-07, nichts davon ausprobiert.

- **Prognose** (`src/shared/schedule.ts`): Die eingeplanten Milestones eines Projekts stehen in Plan-Reihenfolge (`qorder`) hintereinander. Ein Milestone beginnt an seinem Startdatum, sonst nach dem vorherigen und nach allem, worauf er wartet. Sein Ende ist das gesetzte Enddatum, sonst Start plus offene Aufgaben durch Tempo. Läuft die Rechnung über ein gesetztes Enddatum hinaus, gilt er als verspätet. Abhängigkeiten zählen von Milestone zu Milestone und über Aufgaben, die auf Aufgaben eines anderen Milestones warten.
- **Karte verschieben** (`POST /api/move`): Ziel ist ein Milestone (`milestoneId`), das Backlog oder „Ready“ (`ready` an losen Wurzeln), dazu der Platz unter den Geschwistern (`index`). Der Server nummeriert neu.
- **Milestones umsortieren:** Start- und Enddaten bleiben unberührt, es ändert sich nur `qorder`, eine ganze Zahl je Milestone. Die Web-App schreibt die Reihenfolge aller betroffenen Milestones in einem Zug über `/api/steps`; diese Route ist per Token gesperrt und kann zu viel, um sie freizugeben.
- **Backlog und Ready** (`src/shared/outline.ts`): „Ready“ sind lose Wurzeln mit `ready`, gegliedert nach Markierung, sonst nach Kategorie. Alles andere Uneingeplante ist Backlog: Gruppen, nicht eingeplante Milestones und „Unsortiert“.
- **Milestone anlegen** (`POST /api/kind/milestone`): per Token möglich, `planned` lässt sich beim Anlegen mitgeben. Was ohne Angabe gilt, ist noch nachzusehen.

## Ausbau: Abhängigkeiten als Fäden

Stand 2026-10-07: Am Spieltisch sind Fäden fraglich, sie würden ihn eher unruhig machen; die Kette dort sagt schon, was gesperrt ist. Stattdessen zeigt der Graph einer Karte die Abhängigkeiten – in der Planung (siehe „Planen am Tisch“) und auch am Spieltisch und im Dock: Rechtsklick auf eine Karte, „Abhängigkeiten zeigen“. Am Tisch legt er sich über die Karten, aus dem Dock öffnet er ein eigenes Fenster (`ui/dep_graph_window.gd`), weil das Dock dafür zu schmal ist. Die Skizze unten bleibt als Idee stehen.

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

Vorhandene Aufgaben bekommen Referenzen auf Szenen und Nodes. Der 2D- und 3D-Editor blendet die Karten an diesen Stellen ein, im Spiel ist davon nichts zu sehen.

### Festgelegt

- **Szenendateien bleiben unberührt.** Die Referenz steht an der Aufgabe, nicht in der Szene. Keine Marker-Nodes, keine Metadaten.
- **Nur Szenen und Nodes** als Ziel. Skripte, andere Dateien und freie Positionen ohne Node sind nicht vorgesehen.
- **Nur vorhandene Aufgaben verknüpfen.** Ob und wie Aufgaben aus Godot heraus angelegt werden, ist offen.
- **Lokal:** Die Referenzen liegen im lokalen Zustand des Addons (unter `.godot/`, also weg nach dem Löschen des Ordners oder einem frischen Klon). Tasker kennt sie nicht und soll sie auch nicht kennen, siehe „Referenzen teilen“ unten.

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

- **Feste Node-Nummern:** Godot 4.7 schreibt eine eindeutige Nummer je Node in die Szenendatei. Das Addon liest sie aus der gespeicherten Datei, siehe unten.
- **Mitführen:** Solange das Addon läuft, zieht es Umbenennen und Umhängen im Editor in der Referenz nach.
- **Selbstheilung:** Fehlt ein Pfad, sucht das Addon nach Name und Typ und schlägt die neue Stelle vor.

### Darstellung

- **Projizierte Karten:** dieselbe Kartenszene wie im Dock und am Tisch, als Bild gerendert und eingeblendet. In 2D und bei UI-Elementen als Überlagerung am Node. In 3D wird die Stelle des Nodes auf den Bildschirm gerechnet und die Karte dort gezeichnet, nach Abstand verkleinert; sie liegt damit immer über der Geometrie. Keine Hilfsobjekte in der Szene.
- **Wegschieben:** Karten lassen sich vom Node wegziehen, damit sie nichts verdecken. Ein Faden verbindet Karte und Node, der Versatz wird an der Referenz gemerkt.
- **Lesbarkeit:** Weit herausgezoomt schrumpft die Karte zu einem Pin in Statusfarbe, mehrere nah beieinander werden zu einem Stapel.
- **Filter in der Viewport-Leiste:** alle, nur der laufende Milestone, nur die Hand, oder aus.
- **Erledigtes:** Karten erledigter Aufgaben verblassen.

### Bedienen

- **Verknüpfen:** Kontextmenü am Node im Szenenbaum, Rechtsklick auf die Aufgabe im Dock oder die Karte aus dem Dock auf den Node ziehen (Szenenbaum oder Viewport).
- **Mehrfach:** Eine Aufgabe darf an mehreren Nodes hängen, ein Node mehrere Aufgaben tragen.
- **An der Karte:** Klick wählt aus, Doppelklick öffnet, Rechtsklick wechselt den Status.
- **„Zeig mir, wo“:** Von der Karte in Dock oder Tisch zur Szene springen und den Node auswählen.
- **Dock-Abschnitt „In dieser Szene“:** die Aufgaben der offenen Szene.

### Nachgeschlagen in Godot 4.7

Aus der Klassenbeschreibung des Editors (2026-10-07), noch nichts davon ausprobiert.

- **Node-Nummern:** Godot schreibt je Node ein `unique_id=…` in die Szenendatei. Für Skripte gibt es keinen Zugriff darauf, weder an `Node` noch an `SceneState`. Das Addon kann die Nummern aber aus der gespeicherten `.tscn` lesen (nur lesen) und so nach dem Speichern Pfad und Nummer abgleichen. Ein Node, der noch nie gespeichert wurde, hat für das Addon keine Nummer.
- **Mitführen:** `SceneTree.node_renamed`, `node_added` und `node_removed` melden Umbenennen und Umhängen, `EditorPlugin.scene_changed`, `scene_saved` und `scene_closed` den Wechsel der Szene.
- **Einblenden:** Der Editor lässt Addons über den 2D- und den 3D-Viewport zeichnen (`_forward_canvas_force_draw_over_viewport`, `_forward_3d_force_draw_over_viewport`) und reicht Maus und Tastatur immer durch (`set_input_event_forwarding_always_enabled`). Damit geht beides ohne Gizmos: In 3D wird die Stelle des Nodes über die Kamera auf den Bildschirm gerechnet und die Karte dort gezeichnet, nach Abstand verkleinert.
- **Kontextmenü:** Addons dürfen Einträge ins Kontextmenü des Szenenbaums, des 2D-Editors und der Szenen-Tabs setzen (`EditorContextMenuPlugin`). Für den 3D-Viewport gibt es keinen solchen Platz.
- **Ziehen aus dem Dock:** Szenenbaum und Viewport nehmen nur ihre eigenen Zieh-Daten an. Ob sich eine Karte trotzdem dort ablegen lässt, zeigt erst ein Versuch.


### Schritte

An Tasker ändert sich durch „Karten in Szenen“ nichts. Die Schritte lesen und schreiben dort nur, was das Addon ohnehin tut (Stand holen, Status wechseln).

#### Schritt 1: Referenzen und Verknüpfen

Noch ohne Viewport.

- [x] Referenzen im lokalen Zustand, Regeln dazu in `rules/` mit Tests
- [x] Verknüpfen über das Kontextmenü im Szenenbaum (Untermenü „Tasker“, „Aufgabe anhängen …“ öffnet die Suche) und im Dock per Rechtsklick („An ausgewählten Node hängen“); Lösen auf demselben Weg
- [x] Dock-Abschnitt „In dieser Szene“
- [x] „Zeig mir, wo“: Szene öffnen und Node auswählen
- [x] Mitführen beim Umbenennen und Umhängen, Abgleich über die Node-Nummern beim Speichern und Öffnen einer Szene
- [x] „Zeig mir, wo“ und die Liste der Verknüpfungen auch im Aufgabenfenster
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

#### Schritt 2: Karten im Viewport

2D und 3D zusammen.

- [x] Karte als Bild am Node einblenden; was keinen Ort hat (die Szene selbst, Nodes ohne Lage), liegt in der Ecke des Viewports
- [x] Klick wählt aus, Doppelklick öffnet, Rechtsklick wechselt den Status
- [x] Erledigtes verblasst
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)
- [x] Karte aus dem Dock auf einen Node im Szenenbaum oder im Viewport ziehen: der zweite Weg zum Verknüpfen. Fangfelder liegen nur während des Ziehens über Szenenbaum und Viewports. Im Editor ausprobiert (Nutzer, 2026-10-07)
- [x] Klicks im 2D-Editor über eigene Klickflächen, weil der Editor sie dort nur bei ausgewähltem Node weiterreicht

#### Schritt 3: Wegschieben und Lesbarkeit

- [x] Karten wegziehen, Faden zum Node, Versatz merken; „Karte zurück an den Node“ im Kartenmenü
- [x] Pin beim Herauszoomen (zeigt unter dem Zeiger seine Karte), Stapel bei Karten nah beieinander (ein Klick fächert auf, aus dem Fächer lässt sich eine Karte herausziehen)
- [x] Filter in der Viewport-Leiste von 2D und 3D, lokal gemerkt; der Knopf erscheint nur, wenn an der offenen Szene etwas hängt
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

#### Schritt 4: Selbstheilung

- [x] Für verlorene Nodes eine neue Stelle vorschlagen: erst nach Node-Nummer, dann nach Name, Typ und Ort; bei gleich guten Kandidaten kein Vorschlag
- [x] Liste verwaister Referenzen als eigenes Fenster (Hinweis im Dock, Werkzeug-Menü, Befehlspalette): Vorschlag übernehmen, an ausgewählten Node hängen, lösen
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

#### Erledigte und archivierte Aufgaben

- [x] Erledigt: Die Karte bleibt am Node und verblasst. Der Eintrag „Erledigtes einblenden“ im Filter-Menü blendet sie aus, die Verknüpfung bleibt.
- [x] Archiviert oder gelöscht: Die Verknüpfung löst sich von selbst, sobald die Aufgabe nicht mehr im Stand ist. Wer eine Aufgabe aus dem Archiv zurückholt, muss neu verknüpfen.
- [x] Aufgeräumt wird nur bei dem Tasker (Server und Projekt), mit dem die Referenzen entstanden sind. Ein anderer Server oder ein anderes Projekt lässt sie stehen; sie erscheinen dann als verwaist.
- [x] Im Editor ausprobiert (Nutzer, 2026-10-07)

#### Später, falls gewünscht: Referenzen teilen

Entschieden am 2026-10-07: Die Referenzen bleiben lokal. Nach Tasker ziehen sie nicht um, dort wären sie unnötig. Sollen sie einmal über Rechner hinweg gleich sein, gehören sie eher als Datei ins Godot-Projekt, die mit ins Repo des Spiels kann.

## Ausbau: Aufgaben bearbeiten

Stand 2026-10-07: Es beginnt mit der Beschreibung. Sie soll sich bedienen lassen wie in Tasker: im Ansichtsmodus Kästchen abhaken, im Editiermodus Listen mit klugen Einrückungen und Befehlen. An Tasker ändert sich dafür nichts – gespeichert wird über `/api/kind/<kind>/<id>`, die Route ist per Token frei und schränkt keine Felder ein.

### Festgelegt

- **Vorbild ist Taskers Editor** (`client/ui/editor.tsx`, `shared/listEdit.ts`, `client/ui/caretMenu.tsx`). Die Listenlogik dort sind reine Textfunktionen (Text und Auswahl hinein, Änderung heraus); sie kommt samt ihrer Tests nach `rules/`.
- **Bilder einfügen** bleibt vorerst draußen. Vorhandene Bilder und Zeichnungen bleiben im Text stehen.
- **Angelegt wird weiterhin nichts.** Bearbeitet werden vorhandene Aufgaben.

### Schritte

#### Schritt 1: Kästchen abhaken

- [x] Kästchen in der gerenderten Beschreibung sind anklickbar, in Aufgaben- und Milestone-Fenster. Der Haken steht sofort da; mehrere Klicks kurz nacheinander gehen nacheinander hinaus, weil jede Änderung die Version der vorigen nennen muss.
- [x] Welche Zeile ein Kästchen umschaltet, entscheidet `rules/checklist.gd` wie in Tasker: Zeilen in Code-Blöcken zählen nicht.
- [x] Lehnt Tasker ab, steht wieder da, was im Stand steht, und das Fenster nennt den Grund. Ohne Verbindung sind die Kästchen nicht anklickbar.

#### Schritt 2: Editiermodus

- [x] Nachgesehen in Tasker (`client/ui/Inspector.tsx`, `Content`): Titel und Beschreibung sind ein Feld, die erste Zeile ist der Titel. Ein Klick in den Inhalt öffnet es – außer er trifft einen Verweis oder ein Kästchen oder es ist Text markiert. Die Schreibmarke steht am Ende. „Fertig“, Escape oder Strg+Enter übernehmen, „Abbrechen“ verwirft.
- [x] Genauso im Aufgaben- und im Milestone-Fenster (`ui/content_editor.gd`). Damit ist auch der Titel bearbeitbar. Escape schließt beim Bearbeiten nicht das Fenster, sondern übernimmt; wer das Fenster schließt, übernimmt vorher ebenfalls.
- [x] Konfliktfall, anders als in Tasker: Hat sich der Stand geändert, während getippt wurde (über den Änderungs-Strom oder als 409 beim Speichern), bleibt das Feld mit dem eigenen Text offen und sagt es. Erst ein zweites „Fertig“ überschreibt den neuen Stand. Auch bei einem Serverfehler bleibt der Text stehen.

#### Schritt 3: Listen

- [x] `rules/list_edit.gd` aus `shared/listEdit.ts`, mit den 22 Tests von dort.
- [x] Enter setzt die Liste fort (auch nummeriert und mit leerem Kästchen); in einem leeren Punkt beendet es sie oder geht eine Ebene hinauf.
- [x] Umschalt+Enter bricht im Punkt um, eingerückt unter seinen Inhalt; im Fließtext ist es ein gewöhnlicher Umbruch.
- [x] Tab und Umschalt+Tab rücken Listenpunkte ein und aus, auch mehrere markierte, mit passender Nummer. Ein Tabulatorzeichen schreibt Tab nie: außerhalb von Listen geht es zum nächsten Bedienelement, wie im Browser.
- [x] Alt und Pfeil hoch/runter verschieben Zeilen, eine Markierung als Block.
- [x] Jede dieser Änderungen ist ein Schritt zum Rückgängigmachen.

#### Schritt 4: Befehle und Verweise

- [x] `/`-Menü unter der Schreibmarke mit den Befehlen aus Tasker: „TodoListe“ und „Liste“. Am Zeilenanfang oder in einem leeren Listenpunkt beginnt der Befehl diese Zeile, hinter Text eine neue darunter.
- [x] `$`-Suche nach Aufgaben und Milestones für einen Verweis, mit derselben Mechanik: das eigene Projekt zuerst, Erledigtes zuletzt, Ziffern suchen nach der Nummer. Eingefügt wird `$142 `.
- [x] ↑/↓ wählen, Enter oder Tab übernehmen, ein Klick auch. Escape schließt nur die Liste; an derselben Stelle öffnet sie sich dann nicht wieder. Regeln in `rules/caret_menu.gd`, die Liste in `ui/content_editor.gd`.

#### Später

- Bilder ins Feld legen.

## Ausbau: Das Feld

Der Weg zum Milestone soll ein Ziel haben. Statt Hand und Nachziehstapel liegen alle Karten des laufenden Milestones offen auf einem Feld, und was sie voneinander brauchen, wird zum Kampf: Marienkäfer gegen Schädlinge. Das Feld ist die erste Ansicht am Tisch; der Spieltisch („Spielen“) bleibt daneben, bis das Feld ihn ersetzt.

### Festgelegt

- **Schädlinge:** Auf einer Karte sitzt für alles, was sie noch braucht, ein Schädling: je offener Voraussetzung einer und, bei einem Stapel, je offener Unteraufgabe einer. Steht die Karte selbst auf „Blockiert“, liegt eine Mauer darauf – daran ändert keine andere Karte etwas.
- **Tappen:** Ein Klick nimmt eine Karte in Arbeit („In Progress“) oder gibt sie wieder frei. Die getappte Karte liegt quer, um 90° gedreht. Wird eine Karte gezogen, bleibt an ihrem Platz ihr Umriss liegen, damit die Figuren an ihr nicht im Nichts stehen. Tappen geht nur bei freien Karten ohne Unteraufgaben – dieselbe Regel wie beim Ausspielen. Ein Stapel wird nicht von Hand getappt: Tasker stellt ihn selbst auf „In Progress“, sobald darunter etwas läuft oder erledigt ist, und zurück auf „Offen“, wenn alles darunter wieder offen ist (`rules/parent_status.gd`, aus Taskers `shared/parentStatus.ts`). Solange darunter etwas läuft oder erledigt ist, lässt er sich deshalb auch nicht zurücknehmen.
- **Marienkäfer:** Eine getappte Karte schickt einen Marienkäfer zu jedem Schädling, den sie stellt – eine Unteraufgabe also zu ihrem Schädling auf dem Stapel. Im innersten Ring greift er den großen Käfer an. So hat jedes Tappen ein Ziel.
- **Figuren:** Zum Ausprobieren gibt es zwei Arten, umzuschalten in den Editor-Einstellungen (`tasker/field_style`): **Soldaten** (Vorgabe) – eigene in Blau, gegnerische in Rot, der Milestone ein Panzer; die Gegner stehen am rechten Kartenrand, die eigenen ihnen gegenüber am linken, und sie schießen über die Karte aufeinander, unter einem Gegner steht, wie viel er noch aushält – und **Käfer** – Marienkäfer gegen Schädlinge, der Milestone ein Hirschkäfer. Die Regeln sind dieselben, nur die Zeichnung wechselt.
- **Angriffe:** Von jeder getappten Karte laufen rote Striche zu dem, was sie angreift – zur Karte mit ihrem Schädling oder zum großen Käfer.
- **Bisse:** Jedes abgehakte Kästchen der getappten Karte ist ein Biss; dem Schädling fehlt mit jedem Sechstel ein Bein. Bei einem Stapel zählen die erledigten Unteraufgaben.
- **Erledigen:** Die Karte auf den großen Käfer ziehen (oder das Menü) erledigt sie – einen Knopf gibt es auf dem Feld nicht: ihre Schädlinge kippen auf den Rücken und verblassen, der große Käfer verliert ein Leben.
- **Form:** Der große Käfer sitzt in der Mitte, die Karten liegen in Ringen um ihn. Im innersten Ring liegt, woran nichts mehr hängt. Was eine Karte braucht, liegt einen Ring weiter außen: ihre Voraussetzungen und, bei einem Stapel, ihre Unteraufgaben – auch die müssen erledigt sein, bevor er es ist. So führt von jeder Karte ein Weg zur Mitte; Umwege werden nicht eigens gezeichnet. Jede Karte bekommt einen Winkelbereich so breit wie das, was hinter ihr nach außen hängt, und die längste Kette zeigt zur Seite, wo das Fenster am meisten Platz hat. Für die Form zählen auch erledigte Karten, sonst rutschte das Feld beim Spielen um. Verworfen: der Weg von links nach rechts mit offenem Gelände darunter – er sah nach einem Ablauf aus, den es nicht gibt, und manche Karten hingen in der Luft.
- **Karten:** Sie liegen verkleinert auf dem Feld und werden unter dem Zeiger groß. Verkleinert gezeichnete Schrift ist doppelt fein gerastert (`Palette.sharp_*_font`), die Käfer sind ohne weiche Kantenglättung gezeichnet und das Fenster glättet die Kanten (`msaa_2d`) – beides, weil Verkleinern sonst alles weich macht.
- **Nichts davon wird gespeichert:** alles ergibt sich aus Status, Unteraufgaben, Abhängigkeiten und Kästchen. Tasker selbst kennt das Feld nicht.
- **Keine Obergrenze** für getappte Karten (die Marken aus den Skizzen sind verworfen), keine Figuren, kein Alter der Arbeit.

### Schritte

- [x] Schritt 1: Regeln (`rules/field.gd`, Tests in `tests/test_field.gd`), die Ansicht (`ui/field_view.gd`, Käfer gezeichnet in `ui/field_bug.gd`) und der Umschalter Feld / Spielen / Planen. Tappen, zurücknehmen und erledigen gehen über dieselben Änderungen wie am Spieltisch.

Geprüft mit Beispieldaten im Skript und als Bildprobe: Aufbau, Tappen, abgelehntes Tappen einer gesperrten Karte, Unteraufgabe tappen, Erledigen mit fallendem Schädling. Nicht geprüft: echte Maus, echte Daten, viele Karten, die Bewegungen in Bewegung.

### Offen

- Der Schatten als Rivale (Skizze `tisch-schatten.svg`) – als Leiste über dem Feld.
- Viele Karten und lange Ketten: das Feld wird kleiner gezeichnet, bis es passt. Mit dem Mausrad lässt es sich vergrößern (um den Zeiger herum), am freien Filz verschieben; ein Doppelklick auf den Filz zeigt wieder alles. Das Fenster selbst verschiebt man dafür nur noch an der Kopfzeile.
- Ein Milestone fast ohne Abhängigkeiten ist ein einziger voller innerer Ring.
- Wohin die besiegten Schädlinge gehen (Beute), und ob „Unklar“ einen eigenen Gegner bekommt.
- Der Spieltisch fliegt raus, wenn das Feld trägt: Hand, Nachziehstapel und ihr lokaler Zustand werden dann nicht mehr gebraucht.


## Ausbau: Fenster als Karten

Was sich zu einer Karte öffnet – Aufgabe, Milestone, Abhängigkeiten –, sieht selbst wie eine Karte aus: ohne Titelleiste, mit runden Ecken. Weitere Ideen dazu kommen einzeln nacheinander.

- [x] Gemeinsame Hülle `ui/card_window.gd`: rahmenloses Fenster, Kartenfarbe und Rand; verschieben durch Greifen der Karte, Größe über den Griff unten rechts, Kreuz und Escape schließen
- [x] Aufgaben-, Milestone- und Abhängigkeiten-Fenster erben davon
- [x] Der Tisch ist ebenfalls eine Karte: ohne Schattenrand, weil er mit der ganzen Fensterfläche rechnet; Maximieren und Schließen liegen oben rechts, am freien Filz verschiebt man ihn
- [x] Öffnen und Schließen sind animiert: die Karte blendet ein und wächst dabei um wenige Prozent auf ihre Größe (`canvas_transform` des Fensters), beim Schließen blendet sie aus. Durchsichtig kann ein Fenster im Editor nicht sein: die Karte fotografiert beim Öffnen – solange das Fenster noch auf einen Punkt zugeschnitten und damit unsichtbar ist –, was an ihrer Stelle auf dem Bildschirm liegt (`DisplayServer.screen_get_image_rect`). Das Foto liegt über ihr und blendet aus, und hinter ihr, wo es den Rand füllt, solange sie noch kleiner ist. Beim Schließen blendet dasselbe Foto wieder ein, ohne Schrumpfen; wurde die Karte seither verschoben oder in der Größe geändert, schrumpft sie stattdessen kurz
- [x] Im Milestone bleibt der Kopf stehen, wenn der Rest rollt – an ihm greift man die Karte
- [x] Karten bleiben vor dem Editor, auch wenn man in ihn klickt; die Stecknadel in der Kopfzeile schaltet das je Fenster ab und wieder an
- [x] Im Aufgabenfenster liegt das Titelbild blass hinter dem Inhalt, wie im Inspektor von Tasker (`.d-cover`): in voller Breite oben an der Karte, 8 % deckend, ab 55 % der Bildhöhe nach unten auslaufend. Es ist das Bild der Karte – das eigene oder das geerbte –, in voller Größe geladen. Die Beschreibung hat dafür keinen eigenen Grund mehr
- [x] Der Griff zum Größerziehen sitzt weiter von der Ecke weg
- Kein Schatten im Editor: ein weicher bräuchte Durchsichtigkeit. Ausprobiert und verworfen: eine deckende dunkle Kante, versetzt unter der Karte, und ein gerasterter Schatten aus Pixelspalten, in die das Fenster unter der Karte geschnitten ist (wirkt wie ein Fransensaum)

### Nachgeschlagen in Godot 4.7

- Durchsichtige Fenster erlaubt der Editor seinen Fenstern nicht, auch nicht mit `display/window/per_pixel_transparency/allowed` im Projekt (`DisplayServer.is_window_transparency_available()` ist dort falsch, die Ecken wären schwarz). Ein Schatten um die Karte geht im Editor deshalb nicht.
- Runde Ecken gehen trotzdem: `Window.mouse_passthrough_polygon` schneidet unter Windows das Fenster auf den Umriss zu. Die Karte nimmt dafür ein gerundetes Rechteck und zieht es bei jeder Größenänderung nach.
- Wo Durchsichtigkeit geht (eingebettete Fenster, Spiel mit der Projekteinstellung), bekommt die Karte Rand und Schatten; das Polygon lässt dann nur Klicks im Schattenrand durch.
- `DisplayServer.window_start_drag()` und `window_start_resize()` übergeben Verschieben und Größe ans Betriebssystem; eingebettete Fenster rechnen selbst.
- Maximieren von Hand auf die nutzbare Bildschirmfläche, einen Pixel kleiner: deckt ein rahmenloses Fenster die Fläche genau (auch über `MODE_MAXIMIZED`), wirft Godot Fehler aus `screen_get_position/size/usable_rect` (`screen_count = 0`).
- Vor dem Editor hält ein Fenster nur `always_on_top` – und das gilt dann vor allen Anwendungen. `transient` bindet es zwar an das Editor-Fenster, hält es unter Windows aber nicht vorn. `always_on_top` wirkt nur sauber, wenn es beim Erzeugen des Fensters gesetzt ist. Bei einem offenen Fenster greift es sonst erst nach einem Umschalten des Rahmens (`borderless` aus und an) oder der Größe – beides flackert. Die Stecknadel tauscht das Fenster deshalb unsichtbar aus: ein Hilfsfenster mit einem Bild der Karte (`get_texture().get_image()`) legt sich an ihre Stelle, dahinter wird die Karte versteckt, umgestellt und neu gezeigt, dann geht das Hilfsfenster wieder. Verworfen: Aus- und Einblenden beim Umschalten – das Foto des Hintergrunds stimmt nach dem Verschieben nicht mehr. Beides zugleich geht nicht (`popup_centered()` macht ein Fenster `transient` und wirft dann Fehler), darum öffnen Karten über `open_centered()`. Auswahllisten und Menüs einer solchen Karte erscheinen weiterhin vor ihr.


## Risiken und offene Punkte

- **Animationen im Editor-Fenster:** Der Editor zeichnet sparsam neu. Ob Karten dort flüssig laufen, klärt der Prototyp in Schritt 1. Ausweichweg wäre ein eigener Prozess, mit den Nachteilen, dass das Token durchgereicht werden muss und die Autoloads des Spiels mitstarten.
- **Regeln doppelt:** Die Tischregeln gibt es dann in Tasker und im Addon. Ändert Tasker sie, muss das Addon nachziehen. Die Tests sollen das auffangen.
- **Markdown in Beschreibungen:** Der Übersetzer deckt das Übliche ab, ist aber kein vollständiges Markdown. Tabellen und verschachtelte Sonderfälle bleiben als Text stehen, Zeichnungen werden nur genannt.
- **Größe von `bootstrap`:** Bei sehr großem Bestand wäre ein Projektfilter am Server sinnvoll. Das wäre eine Anfrage an die Tasker-Sitzung.
- **Inhalt des Docks:** Für den ersten Wurf bleibt es bei Hand, laufendem Milestone und Suche. Weitere Wünsche fürs Dock kommen später.

## Mockups

Grobe Skizzen der Aufteilung, nicht des Aussehens. Die Titel auf den Karten sind erfundene Beispiele. Der Ordner `docs/` ist per `.gdignore` vom Godot-Import ausgenommen.

| Ansicht | Datei |
|---|---|
| Spielen: Hand, Tisch, Nachziehstapel, Erledigt-Stapel | [docs/mockups/tisch-spielen.svg](docs/mockups/tisch-spielen.svg) |
| Planen, verworfener erster Entwurf: Milestones als Matten | [docs/mockups/tisch-planen.svg](docs/mockups/tisch-planen.svg) |
| Planen, überholte Aufteilung; der Graph einer Karte gilt weiter | [docs/mockups/planen-vorrat-unten.svg](docs/mockups/planen-vorrat-unten.svg) |
| Planen: Ordner-Varianten, gewählt ist die obere | [docs/mockups/planen-ordner-varianten.svg](docs/mockups/planen-ordner-varianten.svg) |
| Abhängigkeiten als Fäden | [docs/mockups/tisch-faeden.svg](docs/mockups/tisch-faeden.svg) |
| Idee: der Schatten als Gegner auf dem Weg zum Milestone | [docs/mockups/tisch-schatten.svg](docs/mockups/tisch-schatten.svg) |
| Idee: Wächter auf gesperrten Karten | [docs/mockups/tisch-waechter.svg](docs/mockups/tisch-waechter.svg) |
| Idee: alle Karten auf einem Feld statt Hand und Nachziehstapel – Weg, Wächter, Bosse, Spielfiguren | [docs/mockups/tisch-feld.svg](docs/mockups/tisch-feld.svg) |
| Idee: was die Spielfigur erzählt – Müdigkeit über die Tage, Kampf über die Kästchen | [docs/mockups/tisch-figuren.svg](docs/mockups/tisch-figuren.svg) |
| Idee ohne Figuren: Gegner als Karten, Karten in Arbeit liegen quer, drei Marken als Obergrenze | [docs/mockups/tisch-gegnerkarten.svg](docs/mockups/tisch-gegnerkarten.svg) |
| Idee: der ganze Tisch als Feld mit Gegnerkarten, quer liegenden Karten und Marken | [docs/mockups/tisch-feld-karten.svg](docs/mockups/tisch-feld-karten.svg) |
| Idee: Marienkäfer gegen Schädlinge – Tappen schickt einen Marienkäfer zum Schädling der Voraussetzung, Erledigen besiegt ihn | [docs/mockups/tisch-kaefer.svg](docs/mockups/tisch-kaefer.svg) |
| Idee: der Milestone in der Mitte, die Karten in Ringen darum – von jeder führt ein Weg nach innen | [docs/mockups/tisch-ring.svg](docs/mockups/tisch-ring.svg) |
| Fünf Vorschläge, wie die Soldaten des Feldes gezeichnet sein können | [docs/mockups/soldaten-vorschlaege.png](docs/mockups/soldaten-vorschlaege.png) |
| Vier Vorschläge für Soldaten als Pixelart | [docs/mockups/soldaten-pixel.png](docs/mockups/soldaten-pixel.png) |
| Soldaten mit rundem Helm, glatt gezeichnet, passend zum Panzer | [docs/mockups/soldaten-rund.png](docs/mockups/soldaten-rund.png) |
