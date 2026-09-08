# Rollback — todo lo que Gestión hizo que afecta a Producción Virgilio

> **Decisión del dueño (2026-09-08):** Producción Virgilio **ya no se usa** (todo migró a
> Gestión). De acá en adelante **no** se condiciona ningún cambio de Gestión por "no romper
> Producción". A cambio, **todo cambio que toque un objeto compartido / de Producción se anota
> ACÁ**, con el impacto y el **rollback exacto**, para poder volver atrás en bloque si hiciera
> falta. Este archivo es la fuente única de "cómo desarmar lo que rompe Producción".
>
> Regla operativa nueva: cuando toques `public.*` compartido, **primero** dejás la entrada acá.

---

## 0. Kill-switch maestro — apagar la toma de control de Gestión (vuelve todo a Producción)

Esto NO es de esta sesión; es el interruptor de fondo. Si hay que devolverle el pipeline a
Producción, se corre esto en **Virgilio** (`hrxfctzncixxqmpfhskv`):

```sql
-- 1) apagar la numeración propia y el armado automático de Gestión
update public."PPP_Web_Config" set valor = 0      where clave = 'numeracion_activa';
select cron.alter_job(71, active := false);   -- tandas diarias 00:01
select cron.alter_job(73, active := false);   -- armado intradía

-- 2) reabrir la canilla del espejo de ISIS (que Gestión vuelva a leer lo de ISIS)
--    (o al revés: ponerle un corte). Ver §3.m/§3.ap de SUPABASE-GESTION-VIRGILIO.md
update public."PPP_Web_Config" set valor = null where clave in ('espejo_np_corte_lk','espejo_np_corte_chef');
```

Y del lado del dueño, en los otros proyectos: reactivar los crons de LK (7/10) y Chef (1/2)
que hoy están apagados (`active := true`). Detalle completo en `CLAUDE.md` (sección de la
numeración) y en `docs/SUPABASE-GESTION-VIRGILIO.md`.

---

## 1. Registro de cambios que tocan objetos compartidos / de Producción

### v14.44 (2026-09-08) — `precios_venta` pasó a ser SÓLO LK

**Qué se cambió.** La Edge Function `sync-precios-venta` **dejó de mergear** LK+Chef en
`precios_venta` (antes: "si el código coincide, Chef gana"). Ahora `precios_venta` = **sólo LK**
y `precios_venta_chef` = **sólo Chef**.

**Qué de Producción se ve afectado.** Producción tiene vistas **sin** `gv_` que leen
`precios_venta` **sin enrutar por empresa**:
- `vista_facturacion_neto_items` / `vista_facturacion_neto`
- `vista_cruce_facturacion`
- `vista_facturable_anticipado`
- `vista_plata_perdida`

Estas ahora **valúan las NP de Chef contra la lista de LK** (y pierden los códigos
Chef-exclusivos que quedaron viejos en `precios_venta`). Para **Gestión** no hay problema: su
cadena `gv_` sí enruta por empresa (v14.44). El impacto es **sólo** en esas vistas de Producción.

**Rollback exacto** (volver a la lista mezclada con "Chef gana"):
1. En `supabase/functions/sync-precios-venta/index.ts`, volver el bloque 3 a un solo `Map`
   que cargue LK y después Chef (Chef pisa), y hacer `upsert('precios_venta', …)` con eso;
   quitar el `upsert('precios_venta_chef', …)`. (El commit v14.44 tiene el diff exacto.)
2. Redeploy: `mcp Supabase deploy_edge_function` (o Dashboard), `verify_jwt = false`.
3. Re-correr: `select net.http_post(url:='https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/sync-precios-venta', headers:='{"Content-Type":"application/json"}'::jsonb, body:='{}'::jsonb);`
4. (Opcional) restaurar el snapshot previo: `public.gv_bkp_precios_venta_20260908` (337 filas) /
   `gv_bkp_precios_venta_chef_20260908` (101).

**Nota:** el enrutado por empresa que sí conviene (para que Producción tampoco se rompa) sería
agregarles a esas 4 vistas de Producción la misma rama que `gv_vista_facturacion_neto_items`
(LK→`precios_venta`, Chef→`precios_venta_chef`). No se hizo porque Producción no se usa; queda
como opción si algún día se la quiere dejar consistente en vez de revertir.

### v14.51 (2026-09-08) — columna `gv_app` en `Registros_Produccion_Virgilio`

**Qué se cambió.** `alter table public."Registros_Produccion_Virgilio" add column gv_app text;` —
nullable, sin default, sin backfill. Gestión manda `gv_app = 'gestion@' + APP_VERSION` en sus dos
caminos de escritura (`trySendOneReport` y `bulkSendDayReplay`); Producción **no la manda**, así que
**NULL = Producción**. Sirve para saber desde qué app trabajó cada operario, que hasta ahora no se
podía: la tabla es la misma para las dos y no guardaba ni URL, ni user_agent, ni versión.

**Qué de Producción se ve afectado.** Nada. Verificado antes de correrlo, no después:
- Producción **no hace `select *`** sobre la tabla — sus referencias en `index.html`,
  `productividad.html`, `recepcion.js` y `sw.js` nombran columnas. El único `SELECT *` del repo está
  **comentado**, en un SQL de rollback del 2026-08-13.
- Los **grants son a nivel tabla** (`anon`/`authenticated` con INSERT, sin ACL por columna) → la
  columna nueva queda cubierta sola, no hizo falta ningún grant.
- La policy de INSERT es `insert_all` con **`with_check = true`** — no enumera columnas, así que no
  rechaza el payload nuevo.
- Sin trigger (habría corrido también para Producción) y sin tocar ninguna fila existente.

Si Producción volviera a usarse, sigue insertando igual: sus filas quedan con `gv_app` NULL, que es
justamente lo que las identifica.

**Rollback:** `alter table public."Registros_Produccion_Virgilio" drop column gv_app;` + sacar
`gv_app` de los dos payloads de `index.html`. Sin pérdida de datos operativos (la columna es sólo
procedencia). `sql/gv_app_sello_eventos_v1451.sql`, §3.bl de `SUPABASE-GESTION-VIRGILIO.md`,
regresión `tests/gv-app-tag.cjs`.

### v14.48 (2026-09-08) — columna `gv_empresa` generada en `Entregas_Virgilio`

**Qué se cambió.** `alter table public."Entregas_Virgilio" add column gv_empresa text generated
always as (public.gv_empresa_de_np_texto(np)) stored;` — columna GENERADA STORED, read-only.

**Qué de Producción se ve afectado.** Nada: es una columna nueva que ningún writer escribe y que
Producción no selecciona. Se computa sola para las filas existentes y futuras. (El `alter` de una
columna generada reescribe la tabla una vez — 9.8k filas, instantáneo.)

**Rollback:** `alter table public."Entregas_Virgilio" drop column gv_empresa;` (sin pérdida de datos:
la columna es derivada). `sql/entregas_virgilio_gv_empresa.sql`.

### v14.47 (2026-09-08) — `sync-precios-venta` RECONCILIA (borra lo que no está en el catálogo)

**Qué se cambió.** La Edge Function ahora, después del upsert, borra de `precios_venta` y
`precios_venta_chef` las filas cuyo `actualizado < nowIso` (las que no están en el catálogo de
origen). Sacó las 115 filas viejas de Chef que quedaban en `precios_venta` (337 → 222).

**Qué de Producción se ve afectado.** Las vistas de Producción que leen `precios_venta` sin
enrutar (ver v14.44) ahora, para un código que **no** es de LK (p.ej. 613, propio de Chef), lo
ven como **sin precio** en vez de con el valor viejo de Chef. Es lo correcto (ese código no es de
LK), pero cambia el número para esas vistas. Gestión no se ve afectada (usa `precios_venta_chef`
para Chef).

**Rollback:** restaurar las filas viejas desde el backup
`public.gv_bkp_precios_venta_20260908_pre_reconcile` (337 filas):
`insert into precios_venta select * from public.gv_bkp_precios_venta_20260908_pre_reconcile on conflict (cod) do update set precio_unit=excluded.precio_unit, actualizado=excluded.actualizado;`
y volver la función a la versión sin `reconcileStale` (commit anterior). Pero ojo: la próxima
corrida del cron volvería a reconciliar salvo que también se revierta la función.

### v14.45 (2026-09-08) — `sync-precios-venta` cada 15 min (cron 66)

**Qué se cambió.** Cron 66 pasó de diario (06:00 ART, guarda de 24 h) a `*/15 * * * *`, sin guarda.
**Impacto en Producción:** ninguno funcional (sólo refresca más seguido las mismas tablas).
**Rollback:** `select cron.alter_job(66, schedule := '0 9 * * *', command := <bloque do/begin con la guarda de 24 h>);` (el bloque está en `sql/sync_precios_venta.sql`).

---

## 2. Backups vigentes (para restore puntual)

| backup | qué guarda | fecha |
|---|---|---|
| `public.gv_bkp_precios_venta_20260908` | `precios_venta` antes del split (337 filas, lista mezclada) | 2026-09-08 |
| `public.gv_bkp_precios_venta_chef_20260908` | `precios_venta_chef` antes del re-sync (101 filas) | 2026-09-08 |
| `public.gv_bkp_precios_venta_20260908_pre_reconcile` | `precios_venta` antes de reconciliar (337, con las 115 viejas) | 2026-09-08 |
| `public.gv_bkp_precios_venta_chef_20260908_pre_reconcile` | `precios_venta_chef` antes de reconciliar (101) | 2026-09-08 |

> Estos backups son tablas en `public`. Borrarlos cuando el cambio esté consolidado y ya no se
> quiera el rollback (`drop table public.gv_bkp_precios_venta_20260908;` …).
