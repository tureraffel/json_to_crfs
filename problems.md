- Label in CRF hasewriv werden nicht korrekt angezeigt
    - genaues Problem: Label für diesen Test sind mit HTML-Code zugemüllt (erwartet, Problem bei originalen Daten)
    - nicht alle Label werden auf Test übertragen
    - Problem erkannt: HTMLcode enthält Befehle wie bspw. &nsbp, die von SAS als Makrovariablen gelesen werden.
    - Lösung: einfach kein HTML-code in den Variablen haben. Das programmatisch abzufangen lohnt sich nicht, weil es eh scheiße aussieht
- Formate für Tests  maia1 und maia2 werden nicht vollständig angezeigt
    -  genaues Problem: bei Werten 2,3,4 werden nicht Formate angezeigt, sondern numerischer Wert bleibt bestehen
    - GELÖST: in der Tabelle items_codes sind an diesen Stellen die numerischen Werte identisch mit den Charakterwerten
- bei nicht ausgefüllten Tests sollte auch in der Evaluierungsspalte ein Missingwert eingetragen sein (schwierig bei Textevaluierungen)
    - momentan bei numerischen Werten 0 bei Evaluierung. Beispiel: BDIII hat eine Beobachtung mit Missing: nicht ausgefüllt. Die Evaluierung hat Zahl 0, deutet auf minimale Depression. ist das vertretbar, oder unsinnig?
      offensichtlich werden missings ja schon absichtlich in datenbak so abgefangen.


- Namen von Fragebögen teilweise zu lang. Namen von Formaten entsprechend auch zu lang
