-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.55 (2026-09-17) — EL ARMADOR TENÍA UN TECHO DE ~180 PEDIDOS Y SE CORTABA EN SILENCIO
--
-- Luis: *"arreglalos 3 priorizando el 1"*. Éste es el 1, y resultó bastante peor de lo que
-- decía el problema 384.
--
-- ⚠ PRIMERO, UNA CORRECCIÓN: la RPC que llega a 7,7 s NO es `ppp_web_armar_tandas` (así quedó
-- escrito en la §3.jb y está mal). Es **`gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)`**,
-- que es la que llama la Edge Function de los crons 71 y 73 y la que por dentro llama **7 veces**
-- a `ppp_web_armar_tandas`. En `pg_stat_statements`: **747 llamadas, media 1.771 ms, mín 36 ms,
-- máx 7.711 ms**.
--
-- ### El techo, medido
--
-- Se midió con `gv_ppp_web_armar_pendientes_simular` (que revierte con un savepoint propio, así
-- que se puede correr con carga real sin escribir nada), pasándole como `p_filas` los pedidos web
-- ya programados presentados como si estuvieran pendientes:
--
-- | pedidos pendientes | tarda |
-- |---|---|
-- | 124 | 5.197 ms |
-- | **248** | **9.007 ms** ← ya murió: `statement_timeout` = 8 s |
-- | 496 | 18.694 ms |
--
-- **Lineal, ~43 ms por pedido** (estable: tres corridas seguidas con 124 dieron 5.333 / 5.286 /
-- 5.674 ms, así que no es plan cache frío). O sea: **con más de ~180 pendientes la RPC muere y no
-- arma NADA**. Y ahí está lo peligroso: lo que no se arma queda pendiente, la corrida siguiente
-- entra con más, tarda más, vuelve a morir. **Espiral.**
--
-- ### Y no avisaba
--
-- El cron 73 sólo dispara la Edge Function por HTTP (`net.http_post`), así que **tarda 0,05 s y
-- figura `succeeded` pase lo que pase del otro lado**. Un statement cortado por timeout tampoco
-- queda en `pg_stat_statements`. Nadie se enteraba.
--
-- ### El arreglo: tope por corrida, y VA PRIMERO
--
-- `PPP_Web_Config.armado_tope_pedidos` (120 por defecto; **0 = sin tope**, el comportamiento de
-- antes). El bloque `(a00)` recorta `p_filas` **por cliente completo** —nunca parte un cliente,
-- para no romper la regla "un cliente, un día"— y lo que queda lo toma la corrida siguiente, que
-- es 5 minutos después. Si un solo cliente ya pasa el tope, entra igual: mejor una corrida larga
-- que no arrancar nunca.
--
-- ⚠ **DÓNDE se pone el tope importa tanto como el tope.** Primero se puso después de los filtros
-- (a0…a0c) y con 496 de entrada seguía tardando **9,6 s**: no alcanza con recortar, hay que
-- recortar **antes de todo**. Puesto al principio:
--
-- | | sin tope | con tope 120 |
-- |---|---|---|
-- | 496 pedidos de entrada | 18.694 ms | **4.104 ms** (y 4.036 ms la segunda vez) |
--
-- Con el tope, **el peor caso deja de depender de cuántos pendientes haya**: siempre procesa
-- ≤ 120 y tarda ~4 s, con 4 s de margen sobre el límite.
--
-- ⚠ Con `p_filas` por debajo del tope el bloque no hace nada: el comportamiento es idéntico al de
-- antes (el `if` sólo entra cuando `entraron > tope`).
--
-- ### ⚠ EL AGUJERO QUE ABRIÓ EL TOPE, Y QUE LO ENCONTRÓ EL PROPIO LOG
--
-- La primera corrida real con el tope puesto lo cantó enseguida:
--
-- | hora | empresa | entraron | procesados | pospuestos | tandas |
-- |---|---|---|---|---|---|
-- | 17:45 | lk | 131 | 119 | **12** | 0 |
-- | 17:50 | lk | 131 | 119 | **12** | 0 |
--
-- **Las dos corridas idénticas.** El feed devuelve siempre los mismos pendientes y en el mismo
-- orden, así que el recorte elegía siempre a los mismos clientes: **esos 12 pedidos no se iban a
-- evaluar nunca**. Un tope sin rotación no pospone, esconde.
--
-- Por eso el arranque del recorte **rota**: `turno = floor(epoch/300)`, que cambia cada 5 minutos
-- —la frecuencia del cron 73— y los clientes se toman en orden circular desde ahí. Medido sobre
-- esos mismos datos (70 clientes, tope 119 pedidos): turnos consecutivos eligen **67, 67, 68,
-- 68** clientes, distintos entre sí, así que en pocas vueltas pasaron todos.
--
-- (Los `tandas = 0` de esas corridas son correctos y son otra cosa: esos 131 pendientes son los
-- que quedan en *A Programar* a propósito —Retira, súper, zonas manuales sin camión previsto—,
-- así que el armador los mira y no arma. Lo que importaba era que los 12 se miraran igual.)
--
-- ### Y ahora deja registro
--
-- `GV_PPP_Web_Armado_Log` (una fila por corrida: empresa, entraron, procesados, pospuestos,
-- tandas, ms) y la vista **`gv_ppp_web_armado_salud`**, que es la que hay que mirar:
--
-- ```sql
-- select * from public.gv_ppp_web_armado_salud;
-- -- estado: ok | BACKLOG | LENTO (a menos de 2 s del límite) | SIN CORRER hace mas de 20 min
-- ```
--
-- Una corrida que muere **no deja fila** (la transacción se deshace), así que el hueco —
-- `hace_min` grande — es la señal de que murió. Por eso el centinela mira las dos cosas.
--
-- ### Los otros dos del problema 384
--
-- - **Cron 92 `gv-refrescar-articulo-empresa`** (5,2 s de media, **22,4 s** de máximo): **se
--   arregló solo**. La función tarda **91 ms**; todo lo demás era esperar el
--   `pg_advisory_xact_lock(5768)` que comparte con el cron 68. Medido el mismo día: 22,37 s a las
--   17:00 (chocando con el 68) → **0,21 s a las 17:30**, ya con la v19.53 puesta.
-- - **Cron 90 `gv-cruce-fc-asig`** (4-6 s, constante): ése **no** espera ningún lock. Medido:
--   `gv_cruce_fc_asig_refrescar()` tarda **831 / 814 / 819 ms** con el cache caliente y 5.303 ms
--   en frío; `gv_cruce_fc_asignacion()` sola son 864 ms de las 905 filas que cruza, y el upsert
--   8 ms — **de esas 905 filas cambian 0** en régimen. O sea que lo que cuesta es **leer las
--   facturas con el cache frío**, no el algoritmo. Como el cron 34 (que barría el cache cada 2
--   minutos escaneando 63.614 filas) ya no está, esto debería bajar solo. **No se tocó**: hacer
--   el cruce incremental es un cambio de lógica sobre facturación y no se justifica por 5 s cada
--   10 minutos. Si no baja, la palanca es la frecuencia del cron, y ésa la decide el dueño
--   (afecta cuán fresca está la Conciliación).
--
-- Problema 384.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ── 1) El registro de cada corrida ─────────────────────────────────────────────────────────
create table if not exists public."GV_PPP_Web_Armado_Log" (
  id          bigserial primary key,
  ts          timestamptz not null default now(),
  empresa     text        not null,
  entraron    int         not null default 0,
  procesados  int         not null default 0,
  pospuestos  int         not null default 0,
  tandas      int         not null default 0,
  ms          int         not null default 0
);
alter table public."GV_PPP_Web_Armado_Log" enable row level security;
create index if not exists gv_ppp_web_armado_log_ts on public."GV_PPP_Web_Armado_Log" (ts desc);
grant select on public."GV_PPP_Web_Armado_Log" to anon, authenticated;

-- ── 2) El tope, configurable ───────────────────────────────────────────────────────────────
insert into public."PPP_Web_Config" (clave, valor)
select 'armado_tope_pedidos', 120
 where not exists (select 1 from public."PPP_Web_Config" where clave = 'armado_tope_pedidos');

-- ── 3) El parche a gv_ppp_web_armar_pendientes ─────────────────────────────────────────────
-- ⚠ Va como parche con anclas y no como CREATE completo a propósito: la función tiene 19.841
-- caracteres y es el corazón del armado, con todas las reglas del dueño adentro. Un CREATE
-- transcrito a mano es más riesgoso que un `replace` sobre la definición viva, que falla ruidoso
-- si el ancla no está. La definición completa se saca siempre con:
--   select pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
-- El ROLLBACK exacto está al final de este archivo.
do $mig$
declare d text; nue text; a_dec text; n_dec text; a_ini text; n_ini text; a_log text; n_log text;
begin
  d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if position('(a00) v19.55' in d) > 0 then raise notice 'ya estaba aplicado'; return; end if;

  a_dec := E'  v_piso   date;\n';
  if position(a_dec in d) = 0 then raise exception 'ancla declare'; end if;
  n_dec := a_dec || E'  v_tope       int;\n  v_entraron   int := 0;\n  v_pospuestos int := 0;\n  v_t0         timestamptz := clock_timestamp();\n';
  nue := replace(d, a_dec, n_dec);

  a_ini := E'  -- (a0) v15.67';
  if position(a_ini in nue) = 0 then raise exception 'ancla a0'; end if;
  n_ini :=
    E'  -- (a00) v19.55 (Luis) -- TOPE DE PEDIDOS POR CORRIDA: VA PRIMERO, ANTES DE TODO.\n'
 || E'  --   El armado cuesta ~43 ms por pedido (medido, estable en 3 corridas seguidas: 124\n'
 || E'  --   pedidos = 5,3 s), o sea que con ~180 pendientes la RPC cruza el statement_timeout de\n'
 || E'  --   8 s y NO ARMA NADA. Y lo que no se arma se acumula: la corrida siguiente tarda mas y\n'
 || E'  --   ya no sale nunca (espiral). Medido sin tope: 124 -> 5,2 s, 248 -> 9,0 s (muerta),\n'
 || E'  --   496 -> 18,7 s. Con el tope: 496 de entrada -> 4,1 s.\n'
 || E'  --   Corta por CLIENTE COMPLETO (nunca parte un cliente, para no romper "un cliente, un\n'
 || E'  --   dia") y lo que queda lo toma la corrida siguiente, que es cada 5 min. Si un solo\n'
 || E'  --   cliente ya pasa el tope entra igual: mejor una corrida larga que no arrancar nunca.\n'
 || E'  --   ⚠ VA ANTES DE LOS FILTROS (a0..a0c) Y ESO IMPORTA: con el tope puesto despues de\n'
 || E'  --   ellos la misma entrada de 496 tardaba 9,6 s (no alcanza con recortar, hay que\n'
 || E'  --   recortar TEMPRANO).\n'
 || E'  --   ⚠ Y EL ARRANQUE ROTA EN CADA CORRIDA (turno = epoch/300, o sea cambia cada 5 min, que\n'
 || E'  --   es la frecuencia del cron 73). Sin esto el tope abre un agujero: el feed devuelve\n'
 || E'  --   siempre los mismos pendientes EN EL MISMO ORDEN, asi que los ultimos nunca entraban.\n'
 || E'  --   Se vio en la primera corrida real: 131 pedidos, 119 procesados, los mismos 12\n'
 || E'  --   pospuestos dos corridas seguidas. Con la rotacion, de 70 clientes entran 67-68 por\n'
 || E'  --   turno y en pocas vueltas pasaron todos.\n'
 || E'  --   PPP_Web_Config.armado_tope_pedidos (0 = sin tope, el comportamiento de antes).\n'
 || E'  v_entraron := jsonb_array_length(coalesce(p_filas, ''[]''::jsonb));\n'
 || E'  v_tope := coalesce((select valor::int from public."PPP_Web_Config" where clave = ''armado_tope_pedidos''), 0);\n'
 || E'  if v_tope > 0 and v_entraron > v_tope then\n'
 || E'    with _tp_z as (select x, row_number() over () ord from jsonb_array_elements(p_filas) x),\n'
 || E'         _tp_g as (select btrim(coalesce(_tp_z.x->>''cod'','''')) cod, min(_tp_z.ord) ord0, count(*) n from _tp_z group by 1),\n'
 || E'         _tp_k as (select count(*)::int kk from _tp_g),\n'
 || E'         _tp_r as (select _tp_g.*, (row_number() over (order by _tp_g.ord0))::int ix from _tp_g),\n'
 || E'         _tp_o as (select _tp_r.*, ((_tp_r.ix - 1\n'
 || E'                 - (floor(extract(epoch from now()) / 300)::bigint % (select kk from _tp_k))::int\n'
 || E'                 + (select kk from _tp_k)) % (select kk from _tp_k)) rot from _tp_r),\n'
 || E'         _tp_a as (select _tp_o.cod, _tp_o.rot, sum(_tp_o.n) over (order by _tp_o.rot) hasta from _tp_o),\n'
 || E'         _tp_e as (select _tp_a.cod from _tp_a where _tp_a.hasta <= v_tope\n'
 || E'                   union select _tp_a.cod from _tp_a where _tp_a.rot = 0)\n'
 || E'    select coalesce(jsonb_agg(_tp_z.x order by _tp_z.ord), ''[]''::jsonb) into p_filas\n'
 || E'      from _tp_z where btrim(coalesce(_tp_z.x->>''cod'','''')) in (select cod from _tp_e);\n'
 || E'    v_pospuestos := v_entraron - jsonb_array_length(coalesce(p_filas, ''[]''::jsonb));\n'
 || E'  end if;\n\n'
 || a_ini;
  nue := replace(nue, a_ini, n_ini);

  a_log := E'  return query select * from _gv_res order by 1, 2;';
  if position(a_log in nue) = 0 then raise exception 'ancla return'; end if;
  n_log :=
    E'  -- v19.55 -- QUEDA REGISTRO DE CADA CORRIDA. Antes esto se cortaba EN SILENCIO: el cron solo\n'
 || E'  --   dispara la Edge Function por HTTP, asi que figura succeeded pase lo que pase. Una\n'
 || E'  --   corrida que muere no deja fila: por eso el centinela mira tambien los HUECOS.\n'
 || E'  begin\n'
 || E'    insert into public."GV_PPP_Web_Armado_Log"(empresa, entraron, procesados, pospuestos, tandas, ms)\n'
 || E'    values (p_empresa, v_entraron, v_entraron - v_pospuestos, v_pospuestos,\n'
 || E'            (select count(*) from _gv_res),\n'
 || E'            round(extract(epoch from (clock_timestamp() - v_t0)) * 1000));\n'
 || E'  exception when others then null;\n'
 || E'  end;\n\n'
 || a_log;
  nue := replace(nue, a_log, n_log);
  execute nue;
end $mig$;

-- ── 4) El centinela ────────────────────────────────────────────────────────────────────────
create or replace view public.gv_ppp_web_armado_salud as
with u as (
  select l.empresa,
         max(l.ts) ultima,
         max(l.ms) filter (where l.ts >= now() - interval '24 hours') ms_max_24h,
         sum(l.pospuestos) filter (where l.ts >= now() - interval '2 hours') pospuestos_2h,
         count(*) filter (where l.ts >= now() - interval '2 hours') corridas_2h
    from public."GV_PPP_Web_Armado_Log" l
   group by 1
),
b as (
  select distinct on (l.empresa) l.empresa, l.pospuestos, l.entraron, l.ms, l.ts
    from public."GV_PPP_Web_Armado_Log" l order by l.empresa, l.ts desc
)
select u.empresa,
       u.ultima,
       round(extract(epoch from (now() - u.ultima))/60)::int hace_min,
       b.entraron      ultima_entraron,
       b.pospuestos    ultima_pospuestos,
       b.ms            ultima_ms,
       u.ms_max_24h,
       8000 - coalesce(u.ms_max_24h,0) margen_ms,
       u.corridas_2h,
       coalesce(u.pospuestos_2h,0) pospuestos_2h,
       case
         when u.ultima < now() - interval '20 minutes' then 'SIN CORRER hace mas de 20 min'
         when coalesce(u.ms_max_24h,0) > 6000          then 'LENTO: a menos de 2 s del limite de 8 s'
         when coalesce(u.pospuestos_2h,0) > 0          then 'BACKLOG: quedaron pedidos para la proxima corrida'
         else 'ok'
       end estado
  from u join b on b.empresa = u.empresa;

alter view public.gv_ppp_web_armado_salud set (security_invoker = true);
grant select on public.gv_ppp_web_armado_salud to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ROLLBACK
--
-- Lo más rápido, sin tocar la función: apagar el tope.
--   update public."PPP_Web_Config" set valor = 0 where clave = 'armado_tope_pedidos';
-- Con 0 el bloque (a00) no hace nada y el armador se comporta exactamente como antes.
--
-- Para sacar el código también (el bloque (a00), el log y las variables):
--
-- do $rb$
-- declare d text; nue text;
-- begin
--   d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
--   nue := regexp_replace(d, E'  -- \\(a00\\) v19\\.54.*?end if;\\n\\n', '', 'ns');
--   nue := regexp_replace(nue, E'  -- v19\\.54 -- QUEDA REGISTRO.*?  end;\\n\\n', '', 'ns');
--   nue := replace(nue, E'  v_tope       int;\n  v_entraron   int := 0;\n  v_pospuestos int := 0;\n  v_t0         timestamptz := clock_timestamp();\n', '');
--   execute nue;
-- end $rb$;
--
-- ⚠ Verificar después con:
--   select position('(a00) v19.55' in pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure));
-- ═══════════════════════════════════════════════════════════════════════════════════════════
