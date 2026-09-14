-- =============================================================================
-- v17.87 (2026-09-14) — el armado se REPORTA al servidor, y el servidor lo repara
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · tercer pase del problema 194
-- REEMPLAZA a sql/gv_entregas_reconstruir_v1782.sql (ese quedó como historia; la
-- definición vigente de gv_entregas_reconstruir y del centinela es ESTA).
-- =============================================================================
-- LA OBJECION DEL DUENO, QUE ES LA CORRECTA (14/09)
--   "para arreglar un problema que se daba porque algo vivia solo en el front, no lo
--    vayamos a arreglar con una solucion que solo viva en el front, no?"
--   y antes: "no me interesa un centinela que avise, cae en oidos sordos eso.
--    necesito que el sistema funcione y contemple esos casos".
--
--   Las dos son la misma exigencia: que esto lo resuelva el servidor, no el celular
--   del operario ni una alerta que alguien tenga que leer.
--
-- SE INTENTO RESOLVERLO 100% EN EL BACKEND, SIN TOCAR EL FRONT. NO ALCANZA.
--   Se probaron DOS derivaciones contra las 1.280 filas reales que el front ya habia
--   grabado (todas las NP con TAP), para ver si el servidor podia deducir el armado
--   con los eventos que YA existian:
--
--     intento 1 · pedido + TAL          → 1.159 bien, 114 se abstiene, 6 MAL
--     intento 2 · pedido + PKC + FAL    → 1.258 bien,   8 se abstiene, 13 MAL
--
--   Por que no cierra, medido caso por caso:
--     · el TAL cuenta LIOS, no cajas — en un pedido de 72 cajas del 550 el resumen dice 4;
--     · el PKC no es la ultima palabra: en 11 de los 13 errores el picking marco faltante
--       y el armado IGUAL salio completo (98673: pkc 2->0 y Entregas 2/2/0). El deposito lo
--       resolvio entre el picking y el cierre, y eso no deja ningun evento;
--     · y hay faltantes sin ningun evento que los explique (44607, codigos 727E y 836).
--
--   Escribir la facturacion mal en el 1% de las filas es peor que no escribirla. Asi que
--   adivinar queda descartado: el dato tiene que EMITIRSE.
--
-- ENTONCES, DONDE VIVE CADA COSA (y por que esto NO es "arreglarlo en el front")
--   · El HECHO fisico (que se armo, que falto) solo puede nacer en el deposito, igual que
--     el TAP, el TAL, el PKC y el FAL, que ya nacen ahi desde siempre. Lo que estaba mal
--     no era eso: era que el armado NO SE REPORTABA — se escribia derecho a una tabla que
--     podia fallar, y si fallaba quedaba solo en el localStorage de ese celular.
--   · Ahora el armado se reporta como evento 'ENT' por la MISMA cola que el TAP y el TAL
--     (enqueueReport → IndexedDB, reintentos). Esa cola es la que el 14/09 funciono
--     mientras el POST a Entregas_Virgilio moria con 42501.
--   · La LOGICA y la REPARACION viven en el servidor: esta funcion + el cron 87. El front
--     no repara nada y no decide nada; reporta.
--
-- COMO SE RECONSTRUYE AHORA: EXACTO, SIN HEURISTICA
--   texto del evento = NP|TANDA|cod:pedidas:entregadas:falto,…|ENT
--   Un item por RENGLON del pedido, en orden, sin agrupar (un codigo puede venir en dos
--   renglones y el front escribe dos filas: asi se respeta, y por eso el "candado 4" de la
--   v17.84 — que se abstenia justo en ese caso — YA NO HACE FALTA y se saco).
--
--   Sin evento ENT no se reconstruye NADA. No se adivina.
--
-- PRUEBA DE PUNTA A PUNTA (14/09, transaccion revertida por un RAISE)
--   Se fabrico el evento ENT que el front emitiria para las 55 filas de D67L, se BORRARON
--   las 55 filas, y se dejo que el servidor las rehiciera:
--     "originales=55 · reconstruidas desde el evento ENT=55 · DIFERENCIAS=0"
--   Comparando np, cod_art, las tres cantidades, cod_cliente y fecha_salida, con EXCEPT ALL
--   en los dos sentidos (asi que tampoco sobra ninguna).
--
-- EL FRONT (index.html, v17.85): _compSendEntregasEvento, emitido en compTerminar ANTES
--   del POST a Entregas_Virgilio — si el POST falla, el evento ya salio. No emite para el
--   operador de PRUEBA (legajo 0/1), igual que _compSaveEntregas, para no fabricar armados
--   fantasma. Test: tests/comp-ent-evento.cjs (en la suite).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Cabecera unificada de NP (ISIS + web): tanda, cliente, fecha de entrega.
--    ⚠ `PPP_Web_Programacion.np` es el numero CRUDO (49) y `Entregas_Virgilio` guarda la
--      ETIQUETA ('LK 0049'), que arma `gv_ppp_web_np_label`. Sin esta conversion el
--      centinela marca como "sin entregas" NPs web que SI estan grabadas (paso: 14 falsos
--      positivos en la primera version).
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
select public.gv_ppp_web_np_label(w.empresa, w.np::integer, w.np_idx::integer),
       upper(btrim(w.tanda)),
       w.cod_cliente,
       left(w.fecha_entrega::text, 10),
       'web'
  from public."PPP_Web_Programacion" w
 where nullif(btrim(w.tanda), '') is not null;

grant select on public.gv_np_prog to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) El detalle EXACTO del armado, tal como lo reporto el front.
--    Si una NP tiene mas de un evento (rearmado), gana el ULTIMO.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.gv_armado_ent_items
with (security_invoker = true) as
with ent as (
  select split_part(r.texto, '|', 1)                 as np,
         upper(btrim(split_part(r.texto, '|', 2)))   as tanda,
         split_part(r.texto, '|', 3)                 as detalle,
         r.created_at,
         row_number() over (partition by split_part(r.texto, '|', 1)
                            order by r.created_at desc, r.id desc) as rn
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'ENT'
     and nullif(btrim(split_part(r.texto, '|', 3)), '') is not null
)
select e.np, e.tanda, it.ord::int as renglon,
       btrim(split_part(it.v, ':', 1))                        as cod_art,
       nullif(btrim(split_part(it.v, ':', 2)), '')::numeric   as cajas_pedidas,
       nullif(btrim(split_part(it.v, ':', 3)), '')::numeric   as cajas_entregadas,
       nullif(btrim(split_part(it.v, ':', 4)), '')::numeric   as cajas_falto,
       e.created_at
  from ent e,
       lateral unnest(string_to_array(e.detalle, ',')) with ordinality as it(v, ord)
 where e.rn = 1
   and btrim(it.v) <> ''
   and nullif(btrim(split_part(it.v, ':', 2)), '') is not null;

grant select on public.gv_armado_ent_items to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) CENTINELA — armado cerrado (TAP) que no llego a Entregas_Virgilio.
--    Con la v17.85 todo armado nuevo trae ENT, asi que lo unico que puede caer en
--    "a mano" es un celular corriendo una version anterior. Vacio = todo bien.
-- ─────────────────────────────────────────────────────────────────────────────
drop view if exists public.gv_armado_sin_entregas;
create view public.gv_armado_sin_entregas
with (security_invoker = true) as
with tap as (
  select upper(btrim(r.texto)) as tanda, max(r.created_at) as tap_at
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'TAP' and r.created_at > now() - interval '30 days'
   group by 1
)
select p.tanda, p.np, p.cod_cliente, p.fecha_salida, t.tap_at,
       (select count(*) from public."Entregas_Virgilio" e where e.np = p.np) as filas_entregas,
       (select count(*) from public.gv_armado_ent_items i where i.np = p.np) as items_ent,
       case when exists (select 1 from public.gv_armado_ent_items i where i.np = p.np)
              then 'reconstruible'
            else 'sin evento ENT (armado anterior a la v17.85) — a mano' end as motivo
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
--
--    LOS CANDADOS
--    1. Solo NPs con CERO filas. Una con filas parciales no se toca (sale en el centinela).
--    2. Exige el evento ENT. Sin el no se escribe nada — ver arriba por que no se adivina.
--    3. Colchon de p_min_edad_min minutos desde el TAP: no se mete con un armado recien
--       cerrado que el dispositivo puede estar por subir.
--    4. Una NP DESARMADA o CANCELADA no se resucita (v17.89, ver el comentario en el cuerpo).
--       PROBADO con control positivo, en transaccion revertida: sin desarme reconstruye las
--       55 filas de D67L; con la NP 98686 marcada desarmada, reconstruye 37 (55-18) y esa NP
--       queda en 0.
--    (El candado 4 de la v17.84 era otro —el de codigos en dos renglones— y YA NO EXISTE:
--     el evento trae una entrada por renglon, asi que ese caso se reconstruye bien.)
--
--    Y si el dispositivo sube DESPUES, trg_entregas_virgilio_dedup lo descarta: las
--    cantidades son identicas, porque salen del mismo calculo que el front ya hizo.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_entregas_reconstruir(
  p_tanda        text    default null,
  p_min_edad_min integer default 10,
  p_dias         integer default 7
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
  objetivo as (
    select distinct i.np, i.tanda, t.tap_at,
           (select p.cod_cliente  from public.gv_np_prog p where p.np = i.np limit 1) as cod_cliente,
           (select p.fecha_salida from public.gv_np_prog p where p.np = i.np limit 1) as fecha_salida
      from public.gv_armado_ent_items i
      join tap t on t.tanda = i.tanda
     where (p_tanda is null or i.tanda = upper(btrim(p_tanda)))
       and not exists (select 1 from public."Entregas_Virgilio" e where e.np = i.np)
       -- CANDADO 4 (v17.89) — una NP DESARMADA o CANCELADA no se resucita.
       -- gv_ppp_np_desarmar (v17.88, otro chat el mismo dia) NO borra Entregas_Virgilio:
       -- oculta la NP (ISIS) o le saca la tanda (web), y DEVUELVE EL STOCK a gondola. Sin
       -- este candado, una NP desarmada antes de que su armado llegara a Entregas volveria
       -- sola en la corrida siguiente y, peor, trg_entregas_reconciliar volveria a mover ese
       -- stock: cajas contadas dos veces sobre un desarme que ya las devolvio.
       -- Hoy tambien la frenaria el "cod_cliente is not null" de mas abajo (al desarmar, la
       -- NP sale de la programacion), pero eso es un efecto lateral, no una decision: si
       -- manana un desarme dejara la NP en la PPP, el cron la resucitaria. Esto es explicito.
       and not exists (select 1 from public."GV_Desarmes" d
                        where upper(btrim(d.np)) = upper(btrim(i.np)))
       and not exists (select 1 from public."NP_Canceladas" c
                        where upper(btrim(c.np)) = upper(btrim(i.np)))
       and not exists (select 1 from public."GV_PPP_Prog_Override" ov
                        where upper(btrim(ov.np)) = upper(btrim(i.np)) and ov.oculto)
  ),
  nuevas as (
    insert into public."Entregas_Virgilio"
      (fecha_salida, cod_cliente, np, cod_art, cajas_pedidas, cajas_entregadas, cajas_falto, tanda)
    select o.fecha_salida, o.cod_cliente, o.np, i.cod_art,
           i.cajas_pedidas, i.cajas_entregadas, i.cajas_falto, o.tanda
      from objetivo o
      join public.gv_armado_ent_items i on i.np = o.np
     where o.cod_cliente is not null and o.fecha_salida is not null
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
-- 6) Los crones (aplicados el 14/09)
--      jobid 87 · gv-entregas-reconstruir      · */10 * * * *      · repara
--      jobid 88 · gv-alerta-armado-sin-entregas· 15 11-23 * * 1-6  · avisa lo que NO puede
--    El 88 es la red de ULTIMA instancia, no la solucion: con la v17.85 su unico caso
--    posible es un celular corriendo una version vieja. Definicion en el v1782.
-- ─────────────────────────────────────────────────────────────────────────────

-- SE DROPEARON las heuristicas del intento fallido, para no dejar objetos muertos que
-- alguien tome por buenos: gv_armado_por_np, gv_pedido_renglones, gv_armado_tal_items.

-- ─────────────────────────────────────────────────────────────────────────────
-- PRUEBA DE PUNTA A PUNTA — se revierte sola. Correrla al tocar esta funcion.
-- ─────────────────────────────────────────────────────────────────────────────
-- do $$
-- declare v_orig int; v_ins int; v_dif int; v_t text := 'D67L'; r record;
-- begin
--   create temp table snap on commit drop as
--     select np, upper(btrim(cod_art)) cod, cajas_pedidas p, cajas_entregadas e, cajas_falto f,
--            cod_cliente cc, fecha_salida fs
--       from public."Entregas_Virgilio" where tanda = v_t;
--   select count(*) into v_orig from snap;
--   for r in select np, string_agg(upper(btrim(cod_art))||':'||cajas_pedidas||':'||cajas_entregadas||':'||cajas_falto, ',' order by id) det
--              from public."Entregas_Virgilio" where tanda = v_t group by np
--   loop
--     insert into public."Registros_Produccion_Virgilio" (id, client_id, legajo, opcion, descripcion, texto, ts_cliente, created_at)
--     values (gen_random_uuid(), 'prueba_ent_'||r.np, '237', 'ENT', 'Entregas por NP (TAP)',
--             upper(r.np||'|'||v_t||'|'||r.det||'|ENT'), now(), now() - interval '1 hour');
--   end loop;
--   delete from public."Entregas_Virgilio" where tanda = v_t;
--   perform public.gv_entregas_reconstruir(v_t, 0, 30);
--   select count(*) into v_ins from public."Entregas_Virgilio" where tanda = v_t;
--   select count(*) into v_dif from (
--     (select np,cod,p,e,f,cc,fs from snap
--      except all
--      select np, upper(btrim(cod_art)), cajas_pedidas, cajas_entregadas, cajas_falto, cod_cliente, fecha_salida
--        from public."Entregas_Virgilio" where tanda = v_t)
--     union all
--     (select np, upper(btrim(cod_art)), cajas_pedidas, cajas_entregadas, cajas_falto, cod_cliente, fecha_salida
--        from public."Entregas_Virgilio" where tanda = v_t
--      except all
--      select np,cod,p,e,f,cc,fs from snap)) z;
--   raise exception 'PUNTA A PUNTA (se revierte): originales=% reconstruidas=% DIFERENCIAS=%',
--     v_orig, v_ins, v_dif;
-- end $$;

-- ROLLBACK
--   select cron.unschedule('gv-entregas-reconstruir');
--   select cron.unschedule('gv-alerta-armado-sin-entregas');
--   drop function public.gv_entregas_reconstruir(text, integer, integer);
--   drop function public.gv_alerta_armado_sin_entregas_telegram();
--   drop view public.gv_armado_sin_entregas;
--   drop view public.gv_armado_ent_items;
--   drop view public.gv_np_prog;
--   drop table public."GV_Entregas_Reparadas";
--   (y sacar _compSendEntregasEvento de index.html)
-- =============================================================================
