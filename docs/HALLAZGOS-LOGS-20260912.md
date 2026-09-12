# Tres fallas de producción encontradas en los logs de Postgres — 2026-09-12

> **ESTADO: las tres arregladas y verificadas el mismo día (v16.33).** Lo de abajo es el
> diagnóstico tal como se escribió, con el canal SQL caído. Lo que cambió al poder consultar la
> base está al final, en **"Lo que apareció al abrir el SQL"** — y ahí está el hallazgo grande,
> que NO era ninguna de las dos primeras.

Encontradas mirando `postgres_logs` mientras el canal SQL del MCP estaba caído (el proyecto
seguía `ACTIVE_HEALTHY` y PostgREST sirviendo; sólo la conexión directa daba timeout). Las dos
son **código ya pusheado que le llega al usuario**, así que van a la auditoría
(`github_repo_problemas`) apenas vuelva la conexión.

Ninguna de las dos la causé yo. Las dos vienen de antes de esta sesión y se repiten todos los días.

---

## 1 · Deadlock diario entre el cron 57 y el cron 68 — el stock rápido queda viejo

**Síntoma.** `deadlock detected`, **11 veces el 12/09** (02:20, 08:00, 08:10, 08:20, 08:40, 10:30,
10:50, 11:50, 13:20, 14:00, 15:30). La **víctima es siempre la misma**:

```
Process A: SELECT public.refresh_stocks_carga_rapida()      <- cron 57, la que muere
Process B: select public.reconciliar_pipeline_stock();      <- cron 68
```

El detalle del log es un ciclo de espera limpio:

```
Process 2871537 waits for ShareLock on transaction 2446578; blocked by process 2871532.
Process 2871532 waits for ShareLock on transaction 2446545; blocked by process 2871537.
```

**Qué significa.** Las dos funciones tocan las mismas filas de stock **en orden distinto**. Cuando
sus horarios coinciden (57 corre cada 10 min, 68 cada 30), se traban y Postgres mata a una: siempre
`refresh_stocks_carga_rapida()`. O sea que **~11 veces por día el cache de carga rápida no se
refresca** y la pantalla de Stock sirve un número viejo, sin que nadie se entere: el cron no avisa.

**Fix propuesto** (a aplicar y medir cuando vuelva la conexión), en orden de menor a mayor riesgo:

1. **Correr los horarios** para que no se pisen — `cron.alter_job` nada más, cero cambio de lógica,
   reversible en una línea. Baja la frecuencia del choque pero no lo elimina: si una corrida se
   estira, se vuelven a cruzar.
2. **Candado de aplicación (el fix real).** Un `pg_advisory_xact_lock(<misma clave>)` al principio de
   las dos funciones las serializa: no pueden interleavearse nunca más, y no cambia lo que hace
   ninguna. Toca dos funciones compartidas → va anotado en `docs/ROLLBACK-PRODUCCION.md`.

**Medición para el antes/después:** contar `deadlock detected` en 24 h. Hoy: **11**. Objetivo: 0.

```sql
-- una vez que vuelva el SQL: ver el orden en que cada una toca las filas
select prosrc from pg_proc where proname in
  ('refresh_stocks_carga_rapida','reconciliar_pipeline_stock');
select jobid, schedule, command from cron.job where jobid in (57, 68);
```

---

## 2 · `vista_ppp_pedidos_entregados` tira 500 — el panel de Entregados queda vacío

**Síntoma.** `invalid input syntax for type date: ""`, **39 veces en 24 h** (2 el 11/09 a las 17 h,
4 a las 18, 5 a las 19, 17 a las 20, 4 a las 21, 1 a medianoche, 2 y 4 hoy). El que falla es
PostgREST 14.5 sobre:

```
SELECT np, tanda, cod_cliente, razon_social, m3, fecha_carga, fecha_ppp, fecha_reparto,
       fecha_salida, facturado_at, cajas_pedidas, cajas_entregadas, cajas_falto
  FROM public.vista_ppp_pedidos_entregados ORDER BY facturado_at DESC
```

que es **exactamente** lo que pide `pppRefreshDelivered()` (`index.html:30384`).

**A quién le pega.** Al panel **Entregados / En viaje** de la PPP. Y pega **callado**: el front usa
`supaFetchAllSafe`, que se traga el error y devuelve `[]` — el supervisor ve el panel vacío y
piensa que no hay entregas, no que la consulta se rompió.

**Causa probable.** Alguna columna de texto con `''` que la vista castea a `date`. La vista **no
es la del repo**: `sql/ppp_vistas_sheet.sql:28` no tiene `fecha_carga` ni `fecha_ppp`, así que la
versión viva quedó adelantada al archivo versionado. Hay que sacar la definición real y arreglar
el cast (un `nullif(x,'')::date`, no un `::date` pelado).

```sql
-- una vez que vuelva el SQL
select pg_get_viewdef('public.vista_ppp_pedidos_entregados'::regclass, true);
```

Y de paso: **volver a versionar la vista** en `sql/ppp_vistas_sheet.sql`, que quedó desactualizado.

---

## Nota aparte: el `REFRESH MATERIALIZED VIEW` cada 2 minutos

El cron 55 lanza `REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada` **cada 2 minutos**
(≈30 arranques por hora, todas las horas del día). Un refresh manual del mismo matview medido hoy
tardó **43,5 s**. En los logs de 24 h hay ~700 arranques y sólo ~30 líneas de "completed" — puede
ser muestreo del log, pero conviene mirarlo: si cada refresh no termina antes del siguiente, se
apilan tomando conexiones, y eso encaja con que la conexión directa del MCP diera timeout durante
casi una hora mientras la app seguía andando.

```sql
select jobid, schedule, command from cron.job where jobid = 55;
select * from cron.job_run_details where jobid = 55 order by start_time desc limit 20;
```

No lo toco sin medirlo: bajar la frecuencia del refresh cambia cuán fresco está el stock, y eso
es una decisión de negocio, no de plomería.


---

## Lo que apareció al abrir el SQL (18:00 UTC)

Con la conexión de vuelta, `cron.job_run_details` mostró que **el deadlock era la punta chica**.
En 24 h:

| cron | qué hace | corridas | fallidas | % |
|---|---|--:|--:|--:|
| 55 (`*/2`) | `REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada` | 688 | **212** | 31% |
| 57 (`*/5`) | `refresh_stocks_carga_rapida()` | 275 | **96** | 35% |
| 68 (`*/10`) | `reconciliar_pipeline_stock()` | 137 | 0 | 0% |

De las 96 del cron 57, **sólo 11 son el deadlock**. Las otras 85, y las 212 del cron 55, son
todas lo mismo:

```
ERROR: duplicate key value violates unique constraint "idx_vista_stock_procesada_cod"
ERROR: could not create unique index "idx_vista_stock_procesada_cod"
```

**El matview del stock no se estaba refrescando un tercio del tiempo.** Ése era el problema
grande, y no aparecía en `postgres_logs` como error de la app porque el que falla es el cron, y
el cron no le avisa a nadie.

**Causa raíz:** el CTE `stock` normalizaba la clave (`053` → `53`) pero no agrupaba. Dos grafías
del mismo artículo en `vista_saldos_stock` daban dos filas con el mismo `cod`, y el índice único
que `REFRESH CONCURRENTLY` necesita las rechazaba. Al momento de mirar, la tabla estaba limpia:
el fallo aparecía cada vez que alguien escribía un movimiento con la grafía que faltaba. El
matview estaba **a un movimiento mal escrito de fallar, sobre cualquier código**.

Arreglado en `sql/gv_stock_procesada_dup_v1633.sql`, con centinela
`public.gv_stock_procesada_dup` para las otras cuatro fuentes que también pueden duplicar.

### Y un tercer hallazgo, de paso

`vista_ppp_pedidos_entregados` **no tenía `security_invoker`** (`reloptions` en null), aunque el
archivo versionado decía que sí: corría como `postgres` y salteaba la RLS. Se prendió después de
comprobar que `anon` lee las 5 tablas base completas, así que no cambió nada para la app.
Conviene barrer el resto de las vistas buscando lo mismo.

### Medición del antes / después

| | antes | después |
|---|---|---|
| `vista_stock_procesada` | 363 filas · 48197.00 | **igual** (no-op comprobado) |
| `REFRESH CONCURRENTLY` | fallaba 1 de cada 3 | corre limpio |
| `vista_ppp_pedidos_entregados` | 500 | 1227 filas, y como `anon` también |
| `gv_stock_procesada_dup` | — | 0 filas |
| facturación neto | $1.395.224.315,83 | **sin moverse** |
