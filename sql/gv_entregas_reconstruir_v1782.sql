-- ⚠⚠ SUPERADO por sql/gv_entregas_reconstruir_v1785.sql. Este archivo queda como
--    HISTORIA: su reconstruccion deducia el armado del TAL y de los PKC, y eso NO
--    alcanza — medido sobre 1.280 filas reales, erraba 6 (TAL) / 13 (PKC+FAL). La
--    version vigente reconstruye desde el evento ENT que el front reporta al cerrar
--    el armado, y es exacta. El "candado 4" de aca ya no existe alla: con el evento,
--    un codigo en dos renglones se reconstruye bien.
-- =============================================================================
-- v17.82 (2026-09-14) — el armado NO puede depender del cache del celular
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · segundo pase del problema 194
-- (no es un problema nuevo: es el mismo armado perdido, atacado en la raiz de diseno)
-- =============================================================================
-- EL PROBLEMA DE FONDO (dueno, 14/09: "deberia subir automatico y no depender del
-- cache del dispositivo local. suponete que cerro el celu y se fue a la casa")
--
--   Hasta hoy, si el POST del front a Entregas_Virgilio fallaba, la UNICA red de
--   contencion era `localStorage.vir_entregas_pend` + `_compFlushEntregas`, que
--   reintenta cuando ESE dispositivo vuelve a abrir la app. Si el operario apaga el
--   celular y se va, el armado no existe para el servidor hasta que vuelva.
--   Paso el 14/09 con D67M y E01J (armador legajo 237): el facturador quedo sin
--   subtotal y no habia forma de arreglarlo desde el servidor.
--
--   Y no hacia falta que estuviera: **los eventos SI llegan siempre**. El TAP y los
--   TAL (lios por NP, con codigo y cajas) viajan por la cola de eventos a
--   Registros_Produccion_Virgilio, que no tiene trigger de canonizacion y por eso
--   nunca fallo. O sea que el servidor YA TIENE todo lo necesario para reconstruir
--   Entregas_Virgilio solo. Eso es lo que hace este archivo.
--
-- COMO SE RECONSTRUYE UNA FILA
--   cajas_pedidas    ← gv_ppp_np_items (el pedido; cubre ISIS y web, por `origen`)
--   cajas_entregadas ← el detalle del TAL, acotado a lo pedido (igual que el front,
--                      que hace Math.max(it.cajas - falto, 0))
--   cajas_falto      ← pedidas − armadas
--   cod_cliente / fecha_salida / tanda ← la programacion (ISIS o web)
--
--   Es EXACTAMENTE la cuenta del front (`compTerminar`, index.html ~12630): el
--   pedido entero por NP, con el faltante restado.
--
-- VALIDACION ANTES DE ESCRIBIR NADA (14/09)
--   Se corrio la reconstruccion contra **D67L**, una tanda que el front SI habia
--   grabado bien ese mismo dia, y se comparo fila por fila contra las 55 reales:
--   **0 diferencias** en cod_art, cajas_pedidas, cajas_entregadas, cajas_falto,
--   cod_cliente y fecha_salida — incluidas las 2 filas con faltante (550 y 659).
--   Recien con eso se aplico a D67M / E01J (59 filas, ids 12153..12211).
--   Rollback de ese backfill: delete from public."Entregas_Virgilio"
--     where id between 12153 and 12211;
--
-- PRUEBA DE FUEGO DE LA FUNCION (14/09, en transaccion revertida por un RAISE)
--   Se BORRARON las 55 filas de D67L y se dejo que `gv_entregas_reconstruir('D67L', 0)`
--   las rehiciera sola, sin el dispositivo:
--       "originales=55 · reconstruidas=55 · DIFERENCIAS=0"
--   La comparacion fue EXCEPT ALL en los dos sentidos sobre np, cod_art, las tres
--   cantidades, cod_cliente y fecha_salida — asi que tampoco sobra ninguna.
--   Repetirla es sano cada vez que se toque esta funcion; el bloque esta al final.
--
-- LOS CUATRO CANDADOS (por que esto no puede duplicar un armado)
--   1. Solo toca NPs con **CERO** filas en Entregas_Virgilio. Una NP con filas
--      parciales NO se toca: sale en el centinela para mirarla a mano.
--   2. Exige que exista un **TAL con detalle parseable** para esa NP en esa tanda.
--      Sin TAL no hay con que saber que se armo, y asumir "0 armado" marcaria todo
--      el pedido como faltante, que es peor que no hacer nada. Queda en el centinela.
--   3. Colchon de `p_min_edad_min` minutos desde el TAP: no se mete con un armado
--      recien cerrado que el dispositivo puede estar por subir.
--   4. El pedido no puede traer el MISMO CODIGO EN DOS RENGLONES. El front escribe
--      UNA FILA POR RENGLON; `gv_ppp_np_items` los agrupa, asi que la reconstruccion
--      daria 1 fila con la suma. El total en cajas cerraria, pero las cantidades POR
--      FILA no, y entonces el dedup ya no reconoceria la subida tardia del
--      dispositivo y la dejaria entrar = armado y stock duplicados (el incidente del
--      11/09). Esas NP se dejan a mano y salen en el centinela.
--      Como se encontro: al revisar los 16 duplicados np|cod_art de la tabla, que son
--      TODOS de julio/agosto y TODOS este caso (ej. 590E en 4 y 6 cajas, ids
--      consecutivos). Es raro — 1 NP en 30 dias, y ninguna armada — pero existe.
--
--   Y si el dispositivo sube DESPUES: el trigger trg_entregas_virgilio_dedup lo
--   descarta, porque las cantidades son identicas (eso es lo que probo D67L).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Cabecera unificada de NP (ISIS + web): tanda, cliente, fecha de entrega.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.gv_np_prog
with (security_invoker = true) as
select pr.np::text            as np,
       upper(btrim(pr.tanda)) as tanda,
       pr.cod                 as cod_cliente,
       left(pr.fecha_entrega::text, 10) as fecha_salida,
       'isis'::text           as origen
  from public.gv_ppp_programacion_diaria pr
 where nullif(btrim(pr.tanda), '') is not null
union all
-- ⚠ `PPP_Web_Programacion.np` es el numero CRUDO (49); `Entregas_Virgilio` guarda la
--   ETIQUETA ('LK 0049'), que arma `gv_ppp_web_np_label`. Sin esta conversion el
--   centinela marca como "sin entregas" NPs web que SI estan grabadas: la primera
--   version de este archivo nacio con 14 falsos positivos por eso.
select public.gv_ppp_web_np_label(w.empresa, w.np::integer, w.np_idx::integer),
       upper(btrim(w.tanda)),
       w.cod_cliente,
       left(w.fecha_entrega::text, 10),
       'web'
  from public."PPP_Web_Programacion" w
 where nullif(btrim(w.tanda), '') is not null;

grant select on public.gv_np_prog to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) El detalle armado, sacado del TAL.
--    texto = np|lios|tanda|A=codXn,codXn;B=...|clase
--    El sufijo de empresa del codigo ('437E LK') se saca para cruzar con el pedido,
--    igual que hace el front con su clave normalizada.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.gv_armado_tal_items
with (security_invoker = true) as
with tal as (
  select split_part(r.texto, '|', 1)        as np,
         upper(split_part(r.texto, '|', 3)) as tanda,
         split_part(r.texto, '|', 4)        as detalle,
         r.created_at
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'TAL'
     and nullif(btrim(split_part(r.texto, '|', 4)), '') is not null
)
select t.np, t.tanda,
       upper(btrim(regexp_replace(m[1], '\s+(LK|CH)$', '', 'i'))) as art,
       sum(m[2]::numeric) as cajas_armadas,
       max(t.created_at)  as tal_at
  from tal t,
       lateral unnest(string_to_array(t.detalle, ';')) lio,
       lateral unnest(string_to_array(regexp_replace(lio, '^[A-Z]+=', ''), ',')) it,
       lateral regexp_match(btrim(it), '^(.*)X([0-9]+)$') m
 group by 1, 2, 3;

grant select on public.gv_armado_tal_items to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) CENTINELA — armado cerrado (TAP) que no llego a Entregas_Virgilio.
--    `motivo` dice si se puede reconstruir solo o hay que mirarlo a mano.
--    Vacio = todo bien.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.gv_armado_sin_entregas
with (security_invoker = true) as
with tap as (
  select upper(btrim(r.texto)) as tanda, max(r.created_at) as tap_at
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'TAP' and r.created_at > now() - interval '30 days'
   group by 1
)
select p.tanda, p.np, p.cod_cliente, p.fecha_salida, t.tap_at,
       (select count(*) from public.gv_ppp_np_items i where i.np::text = p.np) as items_pedido,
       (select count(*) from public."Entregas_Virgilio" e where e.np = p.np)   as filas_entregas,
       (select count(*) from public.gv_armado_tal_items a
         where a.np = p.np and a.tanda = p.tanda)                              as items_tal,
       case
         when (select count(*) from public.gv_ppp_np_items i where i.np::text = p.np) = 0
           then 'sin detalle de pedido — a mano'
         when (select count(*) from public.gv_armado_tal_items a
                where a.np = p.np and a.tanda = p.tanda) = 0
           then 'sin TAL con detalle — a mano'
         when exists (select 1 from public.gv_ppp_np_items i2
                       where i2.np::text = p.np and i2.renglones > 1)
           then 'codigo repetido en 2 renglones — a mano'
         else 'reconstruible'
       end as motivo
  from public.gv_np_prog p
  join tap t on t.tanda = p.tanda
 where not exists (select 1 from public."Entregas_Virgilio" e where e.np = p.np);

grant select on public.gv_armado_sin_entregas to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Log de lo que reparo el cron. Nace cerrado (RLS sin policies → anon ve 0 filas).
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public."GV_Entregas_Reparadas" (
  id          bigint generated always as identity primary key,
  tanda       text not null,
  np          text not null,
  filas       integer not null,
  cajas_ped   numeric,
  cajas_ent   numeric,
  cajas_falto numeric,
  tap_at      timestamptz,
  reparado_en timestamptz not null default now()
);
alter table public."GV_Entregas_Reparadas" enable row level security;
revoke all on public."GV_Entregas_Reparadas" from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) LA REPARACION. Idempotente: correrla dos veces no escribe dos veces.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_entregas_reconstruir(
  p_tanda        text    default null,   -- null = todas las que hagan falta
  p_min_edad_min integer default 10,     -- colchon desde el TAP
  p_dias         integer default 7       -- ventana hacia atras
) returns table(tanda text, np text, filas integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with tap as (
    select upper(btrim(r.texto)) as tanda, max(r.created_at) as tap_at
      from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'TAP'
       and r.created_at between now() - (p_dias || ' days')::interval
                            and now() - (p_min_edad_min || ' minutes')::interval
     group by 1
  ),
  objetivo as (                          -- candados 1 y 2
    select p.np, p.tanda, p.cod_cliente, p.fecha_salida, t.tap_at
      from public.gv_np_prog p
      join tap t on t.tanda = p.tanda
     where (p_tanda is null or p.tanda = upper(btrim(p_tanda)))
       and not exists (select 1 from public."Entregas_Virgilio" e where e.np = p.np)
       and exists (select 1 from public.gv_ppp_np_items i where i.np::text = p.np)
       and exists (select 1 from public.gv_armado_tal_items a
                    where a.np = p.np and a.tanda = p.tanda)
       -- candado 4: ver la cabecera. El front escribe una fila por RENGLON.
       and not exists (select 1 from public.gv_ppp_np_items i2
                        where i2.np::text = p.np and i2.renglones > 1)
  ),
  nuevas as (
    insert into public."Entregas_Virgilio"
      (fecha_salida, cod_cliente, np, cod_art, cajas_pedidas, cajas_entregadas, cajas_falto, tanda)
    select o.fecha_salida, o.cod_cliente, o.np, i.art, i.cajas,
           least(coalesce(a.cajas_armadas, 0), i.cajas),
           greatest(i.cajas - coalesce(a.cajas_armadas, 0), 0),
           o.tanda
      from objetivo o
      join public.gv_ppp_np_items i on i.np::text = o.np
      left join public.gv_armado_tal_items a
             on a.np = o.np and a.tanda = o.tanda and a.art = upper(btrim(i.art))
     returning "Entregas_Virgilio".tanda, "Entregas_Virgilio".np,
               cajas_pedidas, cajas_entregadas, cajas_falto
  ),
  log as (
    insert into public."GV_Entregas_Reparadas"
      (tanda, np, filas, cajas_ped, cajas_ent, cajas_falto, tap_at)
    select n.tanda, n.np, count(*)::int, sum(n.cajas_pedidas), sum(n.cajas_entregadas),
           sum(n.cajas_falto), (select max(o.tap_at) from objetivo o where o.np = n.np)
      from nuevas n group by n.tanda, n.np
     returning "GV_Entregas_Reparadas".tanda, "GV_Entregas_Reparadas".np,
               "GV_Entregas_Reparadas".filas
  )
  select l.tanda, l.np, l.filas from log l;
end;
$$;

revoke execute on function public.gv_entregas_reconstruir(text, integer, integer)
  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) El cron. Cada 10 min: si un armado no llego, lo repara sin el celular.
--    APLICADO el 14/09 → jobid 87, activo.
-- ─────────────────────────────────────────────────────────────────────────────
-- select cron.schedule('gv-entregas-reconstruir', '*/10 * * * *',
--                      $q$select public.gv_entregas_reconstruir();$q$);
--
-- Apagarlo:  select cron.alter_job(87, active := false);
-- Mirar que reparo:  select * from public."GV_Entregas_Reparadas" order by id desc;
-- Mirar lo que NO puede reparar solo:
--   select * from public.gv_armado_sin_entregas where motivo <> 'reconstruible';
--
-- ROLLBACK COMPLETO
--   select cron.unschedule('gv-entregas-reconstruir');
--   drop function public.gv_entregas_reconstruir(text, integer, integer);
--   drop view public.gv_armado_sin_entregas;
--   drop view public.gv_armado_tal_items;
--   drop view public.gv_np_prog;
--   drop table public."GV_Entregas_Reparadas";
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) PRUEBA DE FUEGO — borra una tanda ya grabada, la reconstruye y compara.
--    Se revierte sola con el RAISE del final. Correrla al tocar la funcion.
-- ─────────────────────────────────────────────────────────────────────────────
-- do $$
-- declare v_dif int; v_ins int; v_orig int; v_tanda text := 'D67L';
-- begin
--   create temp table snap on commit drop as
--     select np, upper(btrim(cod_art)) cod, cajas_pedidas, cajas_entregadas, cajas_falto,
--            cod_cliente, fecha_salida
--       from public."Entregas_Virgilio" where tanda = v_tanda;
--   select count(*) into v_orig from snap;
--   delete from public."Entregas_Virgilio" where tanda = v_tanda;
--   perform public.gv_entregas_reconstruir(v_tanda, 0);
--   select count(*) into v_ins from public."Entregas_Virgilio" where tanda = v_tanda;
--   select count(*) into v_dif from (
--     (select np,cod,cajas_pedidas,cajas_entregadas,cajas_falto,cod_cliente,fecha_salida from snap
--      except all
--      select np, upper(btrim(cod_art)), cajas_pedidas,cajas_entregadas,cajas_falto,cod_cliente,fecha_salida
--        from public."Entregas_Virgilio" where tanda = v_tanda)
--     union all
--     (select np, upper(btrim(cod_art)), cajas_pedidas,cajas_entregadas,cajas_falto,cod_cliente,fecha_salida
--        from public."Entregas_Virgilio" where tanda = v_tanda
--      except all
--      select np,cod,cajas_pedidas,cajas_entregadas,cajas_falto,cod_cliente,fecha_salida from snap)
--   ) z;
--   raise exception 'PRUEBA (se revierte): originales=% · reconstruidas=% · DIFERENCIAS=%',
--     v_orig, v_ins, v_dif;
-- end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- v17.84 (2026-09-14) — el centinela AVISA, no espera que alguien lo mire
-- ═════════════════════════════════════════════════════════════════════════════
-- Dueno, 14/09: "centinela no avisa nada, quedo cerrado esto entonces, no?"
-- La respuesta honesta era: la vista estaba en 0, pero una VISTA no avisa — hay que
-- acordarse de mirarla. Un centinela que nadie mira no es un centinela. Asi que se
-- engancha al mismo Telegram que ya usan gv_alerta_sin_eventos / _cruce_facturacion
-- (tg_enqueue + tg_outbox_flush, con clave de dedup para no repetir el mismo aviso).
--
-- Avisa TODO lo que siga colgado 30 min DESPUES del TAP — incluido lo marcado
-- "reconstruible": si a esa altura sigue ahi, es que el cron 87 no lo pudo arreglar,
-- y eso tambien hay que saberlo.

create or replace function public.gv_alerta_armado_sin_entregas_telegram()
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_txt text;
  v_n   int;
begin
  select count(*), string_agg('· NP ' || np || ' (' || tanda || ') — ' || motivo, E'\n' order by tap_at)
    into v_n, v_txt
    from public.gv_armado_sin_entregas
   where tap_at < now() - interval '30 minutes';
  if coalesce(v_n, 0) = 0 then return; end if;
  perform public.tg_enqueue(
    '⚠ GESTIÓN — ARMADO SIN ENTREGAS (' ||
      to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') || ')' || E'\n' ||
    'Se cerró el armado pero no llegó a Entregas_Virgilio, así que estas NP NO tienen subtotal y NO se pueden facturar:' || E'\n' ||
    v_txt || E'\n' ||
    'El cron gv-entregas-reconstruir (cada 10 min) repara solo lo que dice "reconstruible". Lo que dice "a mano" necesita a alguien. Doc: §3.fs de docs/SUPABASE-GESTION-VIRGILIO.md',
    'gv_armado_sin_entregas_' || v_hoy::text || '_' || md5(v_txt));
  perform public.tg_outbox_flush();
end $$;

revoke execute on function public.gv_alerta_armado_sin_entregas_telegram()
  from public, anon, authenticated;

-- APLICADO el 14/09 → jobid 88. 11-23 UTC = 08:15 a 20:15 ART, lun a sab.
-- select cron.schedule('gv-alerta-armado-sin-entregas', '15 11-23 * * 1-6',
--                      $q$select public.gv_alerta_armado_sin_entregas_telegram();$q$);

-- ─────────────────────────────────────────────────────────────────────────────
-- PRUEBAS DEL CANDADO 4 Y DE LA ALERTA (14/09, transaccion revertida por RAISE)
--
-- No existia NINGUN caso real con TAP para probar el candado 4 (1 sola NP en 30 dias
-- con codigo repetido, y sin armar), asi que se FABRICO el caso: un TAP de D69G y un
-- TAL de la NP 98608 (cod 323E en 2 renglones), y se le borraron sus filas.
--   · filas que reconstruyo la funcion = 0                                   ← el candado frena
--   · el centinela la muestra: "codigo repetido en 2 renglones — a mano"     ← NO frena en silencio
--   · la alerta arma el texto con las 3 NP de esa tanda
-- Y en la misma corrida, D67L siguio dando "originales=55 reconstruidas=55
-- DIFERENCIAS=0", o sea que el candado nuevo no rompio el camino normal.
--
-- ⚠ La prueba de la ALERTA se corta ANTES de tg_enqueue/tg_outbox_flush a proposito:
--   se verifica la consulta que arma el mensaje, no se manda un Telegram de prueba.
-- ─────────────────────────────────────────────────────────────────────────────

-- ROLLBACK de este bloque:
--   select cron.unschedule('gv-alerta-armado-sin-entregas');
--   drop function public.gv_alerta_armado_sin_entregas_telegram();
