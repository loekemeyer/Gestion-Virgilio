# Migración PPP: de Google Sheets a Supabase

> Estado: **diseño listo para aplicar** (v2.80). El código de la app ya está
> preparado detrás de un flag; falta crear las tablas, que la macro las cargue y
> activar el flag. Ver al final por qué no se aplicó desde la sesión de Claude.

## 1. Qué resuelve

Hoy los datos de **programación, pedidos y m³** viven solo en Google Sheets
(documento `1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0`) y la app los lee por
gviz CSV. Eso trae dos costos:

- **Los m³ NO se pueden calcular por SQL** (la limitación #1 de la guía): hay que
  abrir el monitor o exportar la hoja.
- La app **depende de Google** (hoja compartida, parseo frágil de gviz: headers
  duplicados, sub-tablas apiladas, posiciones fijas de columna).

Llevando estas tres hojas a Supabase, el monitor / picking / m³ pasan a leerse de
la misma base que el resto, y el m³ queda **consultable por SQL**.

## 2. Alcance (definido por el dueño)

| Hoja Google | Tabla Supabase | Alimenta |
|---|---|---|
| PPP Excel Programacion Diaria (`gid 1947169223`) | `PPP_Programacion_Diaria` | Monitor de tandas, m³, PDF facturación |
| PPP Excel Pedidos Entregados 2026 (`gid 2146771217`) | `PPP_Pedidos_Entregados` | m³ histórico (fallback) |
| PPP Excel Base Datos Pedidos (~20k filas) | `PPP_Base_Pedidos` | Lista de picking (artículos × pedido) |

Quedan **fuera** por ahora (siguen en Sheets): `VolumenArticulos` (m³ por
artículo, armado guiado apagado) y la planimetría (`planimetria.js`).

## 3. Esquema

DDL completo en [`sql/ppp_supabase.sql`](sql/ppp_supabase.sql). Ejecutarlo una vez
en el **SQL Editor** de Supabase (proyecto `hrxfctzncixxqmpfhskv`). Crea las tres
tablas, índices y las policies de **solo lectura** para `anon`/`authenticated`.

Claves de diseño:
- **m³ es `numeric`** (no texto). La hoja trae coma decimal (`"0,289"`) → la macro
  convierte a punto antes de enviar.
- Grano = una fila por **N° NP** (programación y entregados) y por **(pedido,
  artículo)** (base). Las PK son la clave de upsert.
- **Base de pedidos: pre-agregar** `(pedido, artículo) → sum(cajas)` antes de
  enviar. El picking suma por código igual, así el resultado es idéntico al de
  la hoja y la PK compuesta no choca con filas repetidas.

## 4. Seguridad / RLS

- La **app** lee con la key *publishable* (`sb_publishable_…`, rol `anon`; la TV
  kiosko no tiene sesión). Solo `SELECT`.
- La **macro** escribe con la **`service_role` key** (la del proyecto, en
  *Project Settings → API*). El `service_role` **bypassa RLS**, así que no hace
  falta —ni conviene— ninguna policy de escritura para `anon`.
- ⚠ La `service_role` key es **secreta**: guardala en las propiedades del script
  / variables de la macro, **nunca** en el repo ni en el cliente.

## 5. Contrato de ingesta (lo que tiene que hacer la macro)

Patrón **upsert + borrado de lo viejo** (sirve para cualquier tamaño, sin payloads
gigantes y casi sin ventana vacía). Por cada tabla, en cada corrida:

1. Tomar un sello de corrida: `batch = ` timestamp ISO de **ahora** (uno solo para
   toda la corrida).
2. **Upsert** de las filas en lotes (p. ej. 500), cada fila con `synced_at = batch`:
   ```
   POST {SUPABASE_URL}/rest/v1/{TABLA}?on_conflict={PK}
   Headers:
     apikey: {SERVICE_ROLE_KEY}
     Authorization: Bearer {SERVICE_ROLE_KEY}
     Content-Type: application/json
     Prefer: resolution=merge-duplicates,return=minimal
   Body: [ {fila}, {fila}, … ]      // ≤ 500 por request
   ```
   - `PPP_Programacion_Diaria` → `on_conflict=np`
   - `PPP_Pedidos_Entregados`  → `on_conflict=np`
   - `PPP_Base_Pedidos`        → `on_conflict=pedido,articulo`
3. **Borrar lo que no se reescribió** en esta corrida:
   ```
   DELETE {SUPABASE_URL}/rest/v1/{TABLA}?synced_at=lt.{batch}
   Headers: apikey + Authorization: Bearer {SERVICE_ROLE_KEY}
   ```
   Como las filas de esta corrida tienen `synced_at = batch` (no `< batch`), no se
   tocan; las de corridas anteriores sí se borran.

> Para **Programación** esto equivale a "reemplazar el snapshot del día".
> Para **Entregados** y **Base** mantiene el acumulado y limpia bajas.

### Mapeo de columnas (hoja → JSON)

`PPP_Programacion_Diaria` (solo filas con N° NP; saltear títulos/totales):
```
{ np, tanda, tipo, fecha_recep, cod, razon_social,
  m3,           // número con punto decimal
  v, direccion, barrio, op, fecha_entrega, fecha_fc, zona, observaciones,
  synced_at }
```
`PPP_Pedidos_Entregados` (col **Mt3**, NO "Mt3 FC"):
```
{ np, tanda, fecha, cod, razon_social, mt3, synced_at }
```
`PPP_Base_Pedidos` (pre-agregado por pedido+artículo):
```
{ pedido, articulo, cajas, synced_at }
```

### Ejemplo (Google Apps Script — `UrlFetchApp`)

> Si la macro es VBA, el equivalente es `WinHttp.WinHttpRequest` con los mismos
> método/URL/headers/body. El contrato HTTP es el mismo.

```javascript
const SUPABASE_URL = 'https://hrxfctzncixxqmpfhskv.supabase.co';
const SERVICE_ROLE = PropertiesService.getScriptProperties().getProperty('SB_SERVICE_ROLE');

function pushTabla_(tabla, onConflict, filas) {
  const batch = new Date().toISOString();
  filas.forEach(f => f.synced_at = batch);
  const base = { apikey: SERVICE_ROLE, Authorization: 'Bearer ' + SERVICE_ROLE };

  // 1) upsert en lotes de 500
  for (let i = 0; i < filas.length; i += 500) {
    const lote = filas.slice(i, i + 500);
    UrlFetchApp.fetch(
      SUPABASE_URL + '/rest/v1/' + tabla + '?on_conflict=' + onConflict,
      { method: 'post', contentType: 'application/json',
        headers: Object.assign({ Prefer: 'resolution=merge-duplicates,return=minimal' }, base),
        payload: JSON.stringify(lote), muteHttpExceptions: true });
  }
  // 2) borrar lo viejo
  UrlFetchApp.fetch(
    SUPABASE_URL + '/rest/v1/' + tabla + '?synced_at=lt.' + encodeURIComponent(batch),
    { method: 'delete', headers: base, muteHttpExceptions: true });
}

function num_(s) {                         // "0,289" -> 0.289 ; "" -> null
  if (s === '' || s == null) return null;
  const n = parseFloat(String(s).replace(/\./g, '').replace(',', '.'));
  return isNaN(n) ? null : n;
}
```
Después, por hoja: armar el array de filas con el mapeo de arriba (usando `num_()`
para `m3`/`mt3`/`cajas`, y para la base sumando cajas por `pedido|articulo`) y
llamar `pushTabla_('PPP_Programacion_Diaria', 'np', filasProg)`, etc.

## 6. Lado app (ya en el código, v2.80)

`index.html` lee de la fuente que indique el flag **`PPP_SOURCE`** (cerca de los
`SUPABASE_*_ENDPOINT`):

| valor | qué hace |
|---|---|
| `"sheets"` | Google Sheets, como siempre. **Default** → mergear v2.80 no cambia nada. |
| `"auto"` | intenta Supabase y **cae a Sheets** si la tabla está vacía o falla. |
| `"supabase"` | solo Supabase (sin Google). |

Funciones tocadas (cada una quedó como *dispatcher* + `…FromSheets` +
`…FromSupabase`, mismo Map de salida): `fetchMonitorSheet`, `fetchHistoricSheet`,
`fetchPickingBase`. Helper nuevo `supaFetchAll` (pagina con `Range` + `count=exact`,
necesario porque PostgREST corta a ~1000 filas y la base tiene ~20k).

## 7. Rollout sugerido

1. Ejecutar `sql/ppp_supabase.sql` en Supabase.
2. Cargar la `service_role` key en la macro y agregarle el `pushTabla_` (sección 5).
   Correr la macro una vez; verificar con el SQL de la sección 8.
3. Poner `PPP_SOURCE = "auto"` en `index.html`, subir a `main`. La app usa Supabase
   y si algo falta cae a Sheets sola (sin downtime). Mirar el monitor unos días.
4. Cuando esté validado, `PPP_SOURCE = "supabase"` → corta la dependencia de Google.
   (Se puede dejar la macro escribiendo el Sheet también, como respaldo.)

## 8. Verificación (m³ por SQL — antes imposible)

```sql
-- m³ por tanda (programación del día)
select upper(tanda) tanda, round(sum(m3)::numeric, 3) m3
from "PPP_Programacion_Diaria" where coalesce(tanda,'') <> ''
group by upper(tanda) order by 1;

-- m³ histórico por tanda (pedidos entregados)
select upper(tanda) tanda, round(sum(mt3)::numeric, 3) m3
from "PPP_Pedidos_Entregados" group by upper(tanda) order by 1;

-- artículos de un pedido (picking)
select articulo, cajas from "PPP_Base_Pedidos" where pedido = '97754' order by 1;
```

## 9. Por qué no se aplicó desde la sesión de Claude

Desde el entorno remoto de Claude Code:
- El egress de red **no** tiene en allowlist `hrxfctzncixxqmpfhskv.supabase.co` ni
  `docs.google.com` (ambos dan *"Host not in allowlist"*) → no se puede leer ni la
  Supabase real ni los Sheets.
- El MCP de Supabase de esa sesión apunta a **otra cuenta** (org "Pagina Web LK",
  proyecto `kwkclwhmoygunqmlegrg`), no al de la app → `execute_sql`/`list_tables`
  dan *permission denied* contra `hrxfctzncixxqmpfhskv`.

Por eso esto se entrega como **SQL + código listos para aplicar**, no ejecutado.
Para que Claude lo haga end-to-end haría falta agregar esos hosts al allowlist de
egress y conectar el MCP a la cuenta correcta.
