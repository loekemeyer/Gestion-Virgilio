# Gestión Virgilio ↔ Supabase — registro de cambios y reglas

> **Qué es esto.** El historial de todo lo que Gestión Virgilio crea, lee y escribe en
> Supabase, en orden cronológico. Existe para que no se pierda entre sesiones: si abrís
> una sesión nueva, **este archivo y no la memoria** es lo que dice en qué estado está el
> pipeline propio.
>
> Cada entrada dice **qué se hizo, por qué, qué impacto se midió y cómo se revierte**.
> Se escribe en el momento del cambio, no después.

---

## 0. El hecho que condiciona todo

**Las dos apps comparten el MISMO proyecto Supabase y la MISMA anon key.**

| | |
|---|---|
| Proyecto | `hrxfctzncixxqmpfhskv` ("Control Partes Talleristas") |
| anon key | `sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT` |
| App **en producción hoy** | repo `loekemeyer/Produccion-Virgilio` |
| App **en construcción** | repo `loekemeyer/Gestion-Virgilio` (este) |

Verificado el 2026-09-04 leyendo `supabase-config.js` de los dos repos: misma URL, misma key.

Consecuencia: **"no romper Producción" no se resuelve evitando una tabla.** Cualquier
cosa que se toque en `public.*` —una fila, una función, un trigger, un cron, un grant—
la ve la app que los operarios están usando en este momento.

---

## 1. LA REGLA (fijada por el dueño, 2026-09-04)

> *"Todo lo que hagamos tiene que ser un insert sobre lo que ya hay. Cuando no se pueda
> hacer un insert, se tiene que crear una tabla nueva, hacer todas las conexiones
> necesarias para que haga lo que Gestión Virgilio quiere hacer, y que sea la fuente
> canónica para Gestión Virgilio."*

**El criterio, en una línea: sobre una tabla compartida se AGREGA, nunca se MODIFICA lo
que ya está.** Traducido a cada caso que aparece en la práctica:

| Querés… | Se puede | Cómo |
|---|---|---|
| Agregar **filas** a una tabla compartida | ✅ | `insert … on conflict do nothing`. **Nunca `do update`** — eso modifica una fila existente y está prohibido. |
| Agregar una **columna** a una tabla compartida | ✅ con cuidado | Es "agregar cosas", así que entra. Pero: **nullable, sin `default` que reescriba filas, sin backfill**, y con prefijo `gv_` en el nombre para que se sepa de quién es. Producción no la selecciona, así que no la ve. |
| Cambiar **filas existentes** (`update`, `delete`, `truncate`) | ❌ | Tabla `GV_*` de override + una vista que la superpone. La `GV_*` es la fuente canónica **para Gestión**; Producción sigue leyendo la original, intacta. |
| Cambiar o borrar una **columna existente** | ❌ | idem: override. |
| Objeto nuevo (tabla, vista, función) | ✅ | Prefijo propio: `PPP_Web_*`, `GV_*`, `gv_*`, `ppp_web_*`. |
| Cambiar una función o vista que Producción usa | ❌ | Crear `gv_<nombre>` nueva. `create or replace` sobre una compartida está prohibido aunque el resultado parezca idéntico. |
| Trigger sobre una tabla compartida | ❌ **nunca** | Un trigger corre para Producción también. No hay forma de acotarlo. |
| Dropear algo | ❌ salvo que lo hayamos creado nosotros | Y aun así: `grep` en los **dos** repos antes. |

### Chequeo obligatorio antes de tocar cualquier objeto de `public.*`

El repo de Producción está clonado en `/home/user/loekemeyer/produccion-virgilio`
(lectura anónima, ver `add_repo`). Antes de tocar algo:

```bash
grep -rn "NOMBRE_DEL_OBJETO" --include=*.js --include=*.html --include=*.sql \
  /home/user/loekemeyer/produccion-virgilio
```

Cuesta cinco segundos y el 2026-09-04 habría evitado los tres cambios de §3 que
violaron la regla.

### Reglas que no están en la frase del dueño pero hacen falta

1. **Toda vista nueva va con `security_invoker = true`.** Sin eso corre como `postgres`
   y saltea la RLS de las tablas de abajo. El 2026-09-04 esto costó una filtración real
   (§4, `vista_pedidos_web_feed`).
2. **RLS prendida por defecto** en cada tabla `GV_*`/`PPP_Web_*` nueva, con policy
   explícita. La anon key es la misma para las dos apps.
3. **Backup antes de cualquier escritura sobre tabla compartida**, a `sql/backups/`
   con nombre `backup_<tabla>_<AAAAMMDD>.sql`. Ya está en el CLAUDE.md; acá se fija el
   destino.
4. **Crons y Edge Functions son globales al proyecto.** Un cron de Gestión lleva prefijo
   `gv_`/`ppp_web_` y no puede tocar los de Producción.
5. **Cada cambio se anota acá el mismo día**, con el impacto medido — no "no debería
   afectar", sino la consulta que lo prueba.

---

## 2. Inventario

### 2.a Objetos que Gestión Virgilio POSEE (los creamos nosotros)

| Objeto | Qué es | Archivo |
|---|---|---|
| `PPP_Web_NP` | Numeración propia `LK 1343` / `CH 7` | `sql/ppp_web_programacion.sql` |
| `PPP_Web_NP_Seed` | Desde qué número arranca cada empresa | idem |
| `PPP_Web_Programacion` | Tanda, zona y fecha de entrega de cada NP web | idem |
| `PPP_Web_Config` | Parámetros del armado de tandas | `sql/ppp_web_tandas.sql` |
| `ppp_web_np_asignar()` | Reparte números, con lock por empresa | `sql/ppp_web_programacion.sql` |
| `ppp_web_prog_touch()` | Auditoría de quién programó y cuándo | idem |
| `ppp_web_resync()` | Reacomoda la programación cuando el pedido cambia | idem §3 |
| `ppp_web_armar_tandas()` | Arma las tandas solo | `sql/ppp_web_tandas.sql` |
| `ppp_web_letra()` · `ppp_web_letra_idx()` · `ppp_web_proxima_letra()` | Código de tanda | idem |
| `vista_volumen_articulo_resuelto` | m³ con la "L" resuelta desde el artículo base | `sql/volumen_articulo_resuelto.sql` |
| `vista_facturacion_estado` | Corte "esperando confirmación" / "facturado" | `sql/facturacion_estado.sql` |

En el proyecto **LK** (`kwkclwhmoygunqmlegrg`), que Producción **no** usa para esto:
`v_pedidos_web`, `v_pedidos_web_np`, `get_pedidos_web_np_chef()`,
`virgilio_volumen_map()`, foreign table `virgilio.volumen_articulo`.
Ver `sql/pedidos_web_lk.sql`.

### 2.b Objetos de Producción que Gestión SOLO LEE

`PPP_Programacion_Diaria` (sólo para no repetir un código de tanda) ·
`PPP_Base_Pedidos` · `Volumen_Articulos` · `Zonas_Barrios` · `Articulos_Cajas` ·
`Entregas_Virgilio` · `Facturacion_NP` · `isis_export_pedidos` ·
`vista_cruce_facturacion` · `empresa_de_np()` · `_norm_barrio()`.

**Ninguna de estas se escribe.** Si Gestión necesita un valor distinto al de Producción,
va tabla `GV_*` de override (§1).

---

## 3. Changelog

### 2026-09-04 · Sesión "merge del handoff + pipeline de ventas"

Todo lo de este día está en `main`, commits `1d55e01` … `c9973e2`.

#### ✅ Aditivo o propio — cumple la regla

| # | Cambio | Impacto medido |
|---|---|---|
| 1 | `vista_volumen_articulo_resuelto` (nueva) | 0 referencias en Producción |
| 2 | `vista_facturacion_estado` (nueva) | 0 referencias en Producción |
| 3 | `ppp_web_resync()` (nueva) | escribe sólo en `PPP_Web_Programacion` |
| 4 | `ppp_web_armar_tandas()`, `PPP_Web_Config`, helpers (nuevos) | idem |
| 5 | `Zonas_Barrios` **+28 filas** (`insert … do nothing`) | 4 NP de Producción tocadas, y en las 4 la zona nueva (`Super`) **coincide con la que ya traía el Excel** → cero cambio de comportamiento |
| 6 | Revoke de `anon` sobre `vista_pedidos_web_feed`, y después su drop | 0 referencias en Producción |
| 7 | Drop de los esquemas `pipeline` y `fuentes`, servers FDW `lk_feed`/`chef_feed`, y en LK el rol `virgilio_reader` + su vista | 0 referencias en Producción (los hits de "pipeline."/"fuentes." son comentarios y la palabra española) |
| 8 | En LK: split balanceado por m³ y columnas `m3`/`m3_parcial` en `v_pedidos_web_np` y en la RPC de Chef | 0 referencias en Producción |

#### ⚠ Violan la regla — se hicieron ANTES de fijarla, hay que corregirlos

| # | Cambio | Por qué viola | Impacto medido | Rollback |
|---|---|---|---|---|
| A | `Volumen_Articulos`: **UPDATE de 54 filas** (códigos con "L" alineados a su base) | Es un update sobre tabla compartida, no un insert | **2 líneas de 9.667** en `PPP_Base_Pedidos` (NP 44600 `439EL` y 44601 `438EL`), **ambas entregadas el 03/09 y ya facturadas**. El m³ que la PPP muestra sale de la columna guardada, no de esta tabla | `sql/backups/backup_volumen_articulos_codigos_L_20260904.sql` |
| B | `Zonas_Barrios`: **UPDATE de `v.devoto`** (Zona 3 → Zona 2) | idem | **0 NP** con ese barrio en la PPP | `update … set zona='Zona 3 - CABA Oeste' where barrio_norm='v.devoto'` |
| C | `empresa_de_np()`: **create or replace** de una función compartida | Producción la usa (9 referencias) | **0 NP** de Producción cambian de empresa — verificado comparando la regla vieja contra la nueva sobre toda la tabla | `sql/empresa_de_np.sql` tiene las dos versiones |

**Corrección propuesta** (pendiente de tu OK):

- **A y B** → revertir los updates y mover el criterio de Gestión a tablas de override
  `GV_Volumen_Articulos` y `GV_Zonas_Barrios`. `vista_volumen_articulo_resuelto` pasa a
  leer `Volumen_Articulos` + override; se crea `gv_zona_de_barrio()` que hace lo mismo
  con las zonas. Producción queda exactamente como estaba.
- **C** → decidir: dejarla como excepción auditada (0 impacto, y el arreglo es
  necesario para que la exportación a ISIS no mande una NP web de Loekemeyer como Chef),
  o crear `gv_empresa_de_np()` y revertir la compartida.

#### Cambios de datos en el proyecto **LK** (padrón de clientes)

| Cambio | Detalle |
|---|---|
| `customer_delivery_addresses.zona_expreso` cargado a 5 clientes | 4114 → `Lujan` · 4274 → `Soldati` · 4275 → `Villa Soldati` · 4278 → `Soldati` · 4279 → `Belgrano`. Salieron de la PPP histórica, no inventados. Producción-Virgilio no usa esa tabla. |

---

## 4. Incidente de seguridad — 2026-09-04 (cerrado)

`public.vista_pedidos_web_feed` tenía `select` para `anon`. Los esquemas `fuentes` y
`pipeline` sí estaban revocados, **pero la vista no llevaba `security_invoker`**: al vivir
en `public` la publica PostgREST, corre como `postgres` y pasa por arriba de ese candado.

Con la anon key —que es pública y está en los dos repos— se leían los **1.358 pedidos web
de LK y Chef** enteros: razón social, código de cliente, sucursal de entrega, ítems y
condición de pago.

Verificado antes: `set role anon` + count → 1.358 filas. Después del revoke:
*permission denied*. La vista se dropeó ese mismo día junto con el resto del build parado.

**Lección, ya incorporada a §1:** una vista en `public` sobre datos con RLS o sobre
foreign tables necesita `security_invoker = true`. El revoke del esquema de abajo **no la
cubre**.

---

## 5. Pendientes

1. Corregir A, B y C de §3 (arriba).
2. Disparador de las 00:01 para `ppp_web_armar_tandas`: la función recibe las NP vivas
   por parámetro porque viven en LK y Virgilio no tiene FDW contra LK. Hace falta una
   Edge Function que lea LK y la llame, agendada por cron con prefijo `gv_`.
3. UI de las tres sublistas del módulo Facturación (el backend está: `vista_facturacion_estado`).
4. Conectar las NP web a `Facturacion_NP`. Nada lo bloquea —las columnas `np` son `text`
   y `validar_np_armada` sólo exige ítems armados— pero todavía no pasó ninguna.
5. En Chef (`nkhzocgdpwtgrmwleihr`, otra organización, sin acceso desde acá): borrar el
   rol `virgilio_reader` y su vista `v_virgilio_pedidos_feed`.
6. Padrón de LK: 20 clientes sin `zona_expreso` que no resuelven por localidad. Falta el
   dato de en qué barrio de CABA/GBA descarga el camión de cada uno.
7. Decidir si a futuro Gestión se muda a su propio proyecto Supabase. Da aislamiento real,
   pero obliga a resolver stock, planimetría y padrón, que hoy son compartidos.
