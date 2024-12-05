# SAS-Skript zum Import von PsyClinica-Daten im JSON-Format

****
## jsons_to_crfs_tables.sas
Dieses Skript erstellt aus der importierten JSON für jeden durchgeführten CRF eine Tabelle. Variablen sind die Patienten ID, einzelne Fragen des CRFs und die Evaluiering (falls vorhanden).
Es wird auch die Hilfstabelle `t_missings` erstellt. Diese hilft beim Aufschlüsseln von Missing-Werten. Außerdem wird eine Tabelle `Patients` erstellt, in der sich demographische Daten zu den Patienten befinden.
## Nutzung

**`import_json_eval_2811_done.sas`**    
Definiere `jsonlib ` als Pfad der gespeicherten JSON. Definiere die Bibliotheken `out` und `e`. Dort werden die Tabellen gespeichert. Diese 3 Bibliotheken befinden sich am Anfang des Skriptes. Danach führe das gesamte Skript aus. Dies wird einige Zeit in Anspruch nehmen (der Großteil davon ist das dynamische Erstellen von Formaten für jede Variable.) **Wichtig:** Die Dateien überschreiben andere Dateien mit gleichen Namen in der Bibliothek. Neue Tabellen werden nicht an alte Tabellen angefügt.  

**`exporting_savs.sas`**    
Führe dieses Skript als zweites aus. Definiere am Anfang dieses Skripts die Makrovariable `sav_folder` als das Verzeichnis, in dem fertiggestellte .sav-Dateien abgelegt werden sollen.

`%let sav_folder = C:\Users\User\files\sav_files;`    
Beachte, dass der Pfad nicht in Anführungszeichen angegeben wird. Danach definiere die Bibliothek `e` (mit dem selben Verzeichnis wie im vorherigen Skript). Führe danach das gesamte Skript aus.

## Komponenten

### 0. Definieren von libraries
- definiert jsonlib `libname jsonlib json "file\path";`
- definiert `e` 
    - Späteres Speichern von fertigen SAS-Datasets und Formatekatalog
- definiert `out`
    - Speichern von Rohdaten nach CRF, für spätere Betrachtung nicht relevant

### 1. `%import_all_tables`

Arbeitet mit der vorher definierten library `jsonlib`

Erstellt Tabellen in `work`
- Alldata
- Crfs
- Crfs_evaluation
- Crfs_items
- Evaluation_scores
- Evaluation_t_values
- Items_codes
- Root

### 2. Vorbereitung von Tabellen
Erstellen der Tabelle t_missings, in der Missing-werte festgehalten werden.

| value | special_missing | format_comment|
| ----------- | ----------- |----------- |
| 99999 | .Z | TEST NICHT AUSGEFÜLLT |
| ... | ... | ... |


**`crfs_items`**
Diese Tabelle beeinhaltet jede gestellte Frage und den Wert der gegebenen Antwort. Bei fehlenden Aussagen stehen "N\A" oder leere Textfelder
Textwerte werden manuell in zahlenbasierte Missings geändert.
**Beispiel:** `if value = "" then value = "99999";`    
**SPÄTERE FEHLERQUELLE** wenn mehr Daten mit nicht abgefangenen Fehlern auftreten

Die Variable `value` wird numerisch.

Zusätzlich wird mit `proc sort nodupkey` eine Tabelle `var_labels` erstellt, die den Namen der Variablen und ihr Label beinhaltet.

**`crfs`**
"-" werdein in `crf_name` in "_" umgewandelt. ":" und Leerzeichen werden entfernt. SAS erkennt diese beiden Zeichen beim Erstellen neuer Tabellen nicht an.

Mit `proc sort` wird eine Tabelle erstellt, die nur die Namen der vorkommenden Tests enthält.

```
proc sort data = crfs_items (keep=variable_name field_label)
out = var_labels nodupkey;
by _all_;
run;
```
Aus dieser Tabelle wird eine Liste `:table_names` erstellt, durch die das Skript iteriert (Der Fragenbogen *DSGVO_CONSENT* wird hierbei ausgelassen).

**`items_codes`**
beinhaltet die Werte einer Frage `nvalue` und die tatsächlich gegebene Antwort `cvalue`

|ordinal_items|ordinal_codes|nvalue|cvalue|
|-------------|-------------|------|------|
|1|1|3.00|Einige Male|
|...|...|...|...|

Die Variable `nvalue` wird in einen numerischen Wert übertragen

### 3. `%create_tables`
Diese Makro erstellt für jeden CRF, der sich in `:table_names` befindet eine Tabelle. Dies wird durch `joins` zwischen den Tabellen `root`, `crfs`, `crfs_items` erreicht. Mit `proc transpose` wird die Tabelle gekippt. An dieser Stelle entstehen leere Beobachtungen, da bei nicht ausgefüllten Tests nicht jede Variable in `crf_items` betrachtet wird. Leere Beobachtungen werden an dieser Stelle durch den Missingwert `99999` ersetzt.
Die erstellten Tabellen werden in die Bibliothek `out` abgelegt.

Außerdem greift innerhalb dieses Makros das Makro `%pretty_table(table_name)`, das die Tabelle formatiert (dazu später mehr).

Die Tabelle `t_missings` wird nach `e` exportiert. Sie ist nötig, um die Missingwerte bei der Änderung des Dateiformats zu ändern.

Die in `%pretty_table` erstellten Formate werden als letzte Aktion des Makros in die `library e` exportiert.

>	`/*export formats into lib e*/`
	`proc catalog cat=work.formats;`
		`copy out=e.formats;`
	`quit;`
	`options fmtsearch=(e.formats);`

### 4. `%pretty_tables(table_name)`
Dieses Makro nimmt den Namen einer Tabelle als Parameter. `%pretty_tables` selbst beinhaltet mehrere Makros, die die eingefügte Tabelle inplace verändern.

- `%format_table(table_name)`
    - `%format_col(column, table_name)`
- `%apply_formats(lib, table_name)`
- `%add_labels_to_vars(table_name)`
- `%order_variables(table_name)`
- `%add_evaluation(table_name)`
- `%special_missings(table_name)`

Ausnahmen sind hier `%format_col` und `%format_table`, die nicht direkt an den Tabellen arbeiten.

### 4.1 `%format_col` 
`%format_col` findet mit `joins` auf `crfs_items` und `proc sort` mit der Option `nodupkey` die korrekten Beschreibungen der numerischen Werte für jede einzelne Variable. Daraus wird eine Tabelle erstellt, die mit `proc format` in ein Format gewandelt wird. Die Namenskonvention für diese Formate ist **"FMT_{tabelle}_{variable}_f"**. Diese Formate werden im Katalog `work.formats` gespeichert.

### 4.2 `%format_table` 
`%format_table` führt `%format_col` dynamisch für jede Variable in der Tabelle durch.

### 4.3 `%apply_formats` 
`%apply_formats` fügt diese Formate dann in jeder Variable der Tabelle ein. 

### 4.4 `%add_labels_to_vars` 
`%add_labels_to_vars` erstellt per `join` auf dem Variablennamen auf `var_labels` einen String, der in einem `data step` als korrekte Label zur Tabelle hinzugefügt wird.

### 4.5 `%order_variables` 
`%order_variables` betrachtet alle nichtnumerischen Charakter aus den Variablennamen und sortiert die Variablen nach dieser Betrachtung. **Das funktioniert nur bei Variablen, bei denen die letzten numerischen Werte auf die Fragenreihenfolge hinweisen.**
Variablen ohne numerischen Charakter werden nach links in der Tabelle gesetzt.

### 4.6 `%add_evaluation` 
`%add_evaluation` verwendet einen `join` über die Variable `ordinal_crfs` auf die Tabelle `crfs_evaluation`. Danach werden alle Spalten, die keine Werte enthalten gelöscht (momentan sind noch keine `special missings` in Verwendung). Manche Tests haben eine Variable `error`, wenn keine Auswertung vorliegt. Diese wird übernommen.

### 4.7 `%add_special_missings`
`%add_special_missings` erstellt ein Hash-Objekt und durchkämmt mit einem Key/Valuepair die Tabelle. Erkannte Missingwerte werden durch das vorher festgelegte `special missing` ersetzt.

****
# exporting_savs.sas
Dieses zweite Skript existiert um bei Bedarf die formatierten SAS-Datasets als .spss-Dateien zu exportieren. Zuerst werden die Formate und die Tabelle `t_missing` aus `e` eingelesen. Danach werden alle Tabellen aus `e` in einen vorher definierten Ordner exportiert.

## Komponenten

### 1. `%unspecial_missings`
Das Makro `%unspecial_missings` arbeitet hier als Gegenspieler zum `%add_special_missings` und ersetzt `special missings` wieder durch von anderen System erkannte Missings. 

### 2. `%export_sav`
Das Makro `%export_sav` nimmt die Parameter `table`, `filepath` und `lib`. Bevor es die Datei in den von `filepath` vorgesehenen Pfad exportiert, verwendet es `%unspecial_missings` auf die zu exportierende Tabelle. Dabei wird das Original nicht geändert. 

### 3. `%apply_makro_to_lib`
Das Makro `%apply_makro_to_lib` nimmt ein Makro als Parameter, um dieses auf jede Tabelle in der `library` anzuwenden. Es nimmt auch einen Dateipfad als optionalen Parameter, falls das eingefügte Makro das benötigt.


## Bestehende Probleme / unintuitives Verhalten
- Bei Tests mit nur leeren Beobachtungen wird nur die Variable `patient_id` angegeben. Das liegt daran, dass die eingelesene JSON bei nichtausgefüllten Tests die einzelnen Variablen nicht führt.
- Die Namen der Fragebögen sind teils zu lang (länger als 32 Zeichen). Die Namen der Formate sind dann noch länger, weshalb SAS Warnungen und Fehlermeldungen ausgibt. Die Formate werden richtig dargestellt und zugeordnet. Trotzdem ist das eine mögliche Fehlerquelle, auf die geachtet werden sollte.
- Label für den Test Hase-Wri-V werden nicht korrekt angezeigt. Grund dafür ist HTML-Code innerhalb der Label, insbesondere der Charakter `&nbsp`, der von SAS als nicht zugewiesene Makrovariable gelesen wird. Aus diesem Grund sind einige der Label nicht verfügbar. Obwohl dieses Problem programmatisch abgefangen werden könnte, habe ich mich dagegen entschieden; das Problem muss sowieso auf Seiten der Datenbank gelöst werden.
- Für die Tests Maia-1 und Maia-2 wird die richtige Bedeutung der ordinalen numerischen Werte teilweise nicht im Format angezeigt. Auch liegt an den eingelesenen Daten, die korrekt dargestellt werden.    

**Beispiel:**

| nvalue | cvalue |
|--------|--------|
|1|immer|
|2|2|
|3|3|
|4|4|
|5|nie|

- Bei nicht ausgefüllten Tests enthalten die Spalten für Evaluierung Werte. Beispielsweise hat der Test BDI-II bei einem nicht ausgefüllten Test die Evaluierung 0, deutend auf eine leichte/nicht vorhandene Depression.
