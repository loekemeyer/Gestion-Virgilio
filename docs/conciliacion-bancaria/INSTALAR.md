# Macro de conciliación bancaria → Supabase

Al **guardar** cualquiera de los 4 Excel, la macro sube a Supabase las hojas de año
(`CONCILIACION 2026`, `AÑO 2026`, …) que se tocaron. Cada subida **reemplaza ese año de ese
banco** en la base, así que corregir el Excel corrige la base. Las copias `… (2)` no se suben.

| archivo | banco en la base | formato |
|---|---|---|
| `1_CONCILIACION_CREDICOOP_LOEKE.xls` | `credicoop_lk` → `GV_Conc_Credicoop_LK` | `.xls` sirve tal cual |
| `2_CONCILIACION_SANTANDER_RIO_LOEKE.xls` | `santander_lk` → `GV_Conc_Santander_LK` | `.xls` sirve tal cual |
| `2_BANCO_CREDICOOP_CHEF.xlsx` | `credicoop_ch` → `GV_Conc_Credicoop_CH` | guardar como **`.xlsm`** |
| `1_Bco_Santander_Rio_Chef.xlsx` | `santander_ch` → `GV_Conc_Santander_CH` | guardar como **`.xlsm`** |

El banco se reconoce por el nombre del archivo (CREDICOOP / SANTANDER o RIO, y CHEF). Si se
renombra el archivo y deja de reconocerse, completar `CONC_BANCO` arriba de la macro.

## Pasos (una vez por archivo, en la PC donde se concilia)

1. Abrir el Excel. `Alt+F11` abre el editor de VBA.
2. **Archivo → Importar archivo…** → `ConciliacionSupabase.bas` (la versión CON el token, que
   se entrega aparte; la del repositorio tiene `__TOKEN__` y no carga nada).
3. En el panel izquierdo, doble clic en **ThisWorkbook** y pegar:

   ```vb
   Private Sub Workbook_SheetChange(ByVal Sh As Object, ByVal Target As Range)
       ConcMarcarHoja Sh
   End Sub

   Private Sub Workbook_AfterSave(ByVal Success As Boolean)
       ConcDespuesDeGuardar Success
   End Sub
   ```
4. Los dos de Chef: **Guardar como → Libro de Excel habilitado para macros (.xlsm)**.
5. Al abrir, si Excel muestra "Habilitar contenido", aceptarlo. Para no verlo cada día: agregar
   la carpeta en *Opciones → Centro de confianza → Ubicaciones de confianza*.
6. Probar: `Alt+F8` → **SubirHojaActiva** sobre la hoja del año. Tiene que decir
   `OK CONCILIACION 2026: N movimientos`.

## Qué pasa si…

- **No hay internet:** el Excel se guarda igual; sale un aviso y se reintenta al próximo guardado.
- **Se quiere re-subir todo:** `Alt+F8` → **SubirTodasLasHojas**.
- **Se cambia de lugar una columna:** no se toca la macro; se corrige en la tabla
  `GV_Conc_Columnas` de Supabase.
- **Se filtra el token:** se genera otro con
  `update public."GV_Conc_Token" set token = gen_random_uuid()::text;` y se actualiza en la macro.
