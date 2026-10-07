# Lista de Precios (A Costos VIGENTES) → Supabase + aviso a Telegram

Idea 7358 (Thomas 02/10, retomada por Luis 07/10). Al **guardar** «A Costos VIGENTES», si se tocó la hoja
`Lista de Precios ` (termina en espacio), la macro la sube a `"GP2".lista_precios_subir`. La base la compara
contra la subida anterior y manda al **grupo de gerencia** (`-1004379879565`, el mismo de los avisos de
pedidos anómalos y del agente de cobranzas) lo que cambió.

| regla del aviso | |
|---|---|
| clave del artículo | col **A** (nunca el número de fila) |
| precio que se compara | col **G** (H y L son fórmulas que se mueven con el dólar / IPC) |
| E y K cambian juntas | «corrimiento» de filas, no aumento |
| dólar | celda **H3**, va en una línea aparte |
| proveedor | col B → `public."Proveedores"` |
| más de 60 cambios | va el resumen, no el detalle |

## 1. Base (una vez, lo corre quien tenga el SQL Editor)

1. Supabase → proyecto `hrxfctzncixxqmpfhskv` → **SQL Editor** → pegar `sql/gp2_lista_precios_macro_token_v2762.sql` → Run.
2. `select token from "GP2".planilla_token;` → copiar el token. **Es secreto**: no va al repo ni a un chat abierto.

## 2. Macro en el Excel (en la PC del server donde vive el archivo)

1. Abrir «A Costos VIGENTES» → **Alt+F11**.
2. Archivo → **Importar archivo…** → `ListaPreciosSupabase.bas`.
3. En el módulo, reemplazar `__TOKEN__` por el token del paso 1.2.
4. Doble clic en **ThisWorkbook** y pegar (si ya existen estos eventos, agregar sólo la línea del medio):

```vb
Private Sub Workbook_SheetChange(ByVal Sh As Object, ByVal Target As Range)
    LPMarcarHoja Sh
End Sub

Private Sub Workbook_AfterSave(ByVal Success As Boolean)
    LPDespuesDeGuardar Success
End Sub
```

5. **Guardar como** `.xlsm` (Libro habilitado para macros). Con `.xlsx` la macro se borra.
6. Excel → Archivo → Opciones → Centro de confianza → Configuración → **Ubicaciones de confianza** →
   agregar la carpeta del server (tildar «subcarpetas» y, si es de red, «Permitir ubicaciones de red»).
   Sin esto, Excel abre el archivo con las macros apagadas y no sube nada.

## 3. Primera subida (sin aviso)

**Alt+F8 → `SubirListaPreciosSinAviso` → Ejecutar.** Tiene que decir `OK {...}`.
La foto que hay hoy en la base (07/09) se armó distinto; comparar contra ella mandaría cambios falsos.

## 4. Prueba

1. Cambiar el precio (col G) de un artículo → Guardar.
2. Tiene que llegar al grupo el aviso con ese artículo, el antes y el después.
3. Volver el precio como estaba → Guardar (llega el aviso inverso).

## Si algo falla

- El Excel **se guarda igual**; sale un cartel con el error y se reintenta en el próximo guardado.
- `HTTP 401/403` o «no autorizado» → el token está mal copiado.
- `HTTP 404` → la función no está en la base (falta el paso 1).
- Sin internet → reintenta al próximo guardado. A mano: **Alt+F8 → `SubirListaPrecios`**.

Rollback: al pie de `sql/gp2_lista_precios_macro_token_v2762.sql`.
