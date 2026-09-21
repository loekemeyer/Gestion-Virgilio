-- ════════════════════════════════════════════════════════════════════════════════════════
-- v20.63 (Thomas, 2026-09-21) — LA FECHA DE RECEPCIÓN LA TIENE EL ARMADOR Y LA TIRA
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Thomas: *"los pedidos de chef del nuevo formato no tienen fecha de recepcion"*.
--
-- ⚠ ES MÁS QUE EL FORMATO NUEVO DE CHEF. Medido el 21/09 sobre `PPP_Web_Programacion`:
--
--   | quién                                   | NP sin fecha de recepción |
--   |-----------------------------------------|---------------------------|
--   | Chef, order_id de 7 dígitos (1001430+)  | 5  (CH 0020-0024)         |
--   | **LK, pedidos normales del 18 al 21/09**| **9** (LK 0160…LK 0185)   |
--
-- Las 9 de LK las programó el automático (`creado_por = 'sistema'`) y **sí** están en el
-- feed: no es un problema de Chef, es del armador.
--
-- ⚠ LA CAUSA: el armador TIENE la fecha y no la escribe.
--
--   La fecha viaja desde la página hasta el armador: `gv_pedidos_web_np_lk` y
--   `gv_pedidos_web_np_chef` la devuelven como `fecha_recep`, la Edge Function la mete en
--   `p_filas` (*"La antigüedad es con lo que se ordena la cola cuando no entra todo"*), y
--   `ppp_web_armar_tandas` la parsea y **la usa para ordenar la cola FIFO**… y después su
--   `insert into "PPP_Web_Programacion"` **no incluye la columna**. Queda a merced del
--   trigger `gv_ppp_web_fecha_recep`, que la busca en el CACHE `lk_pedidos_match`:
--
--     · un pedido de LK programado a los 2-4 minutos de entrar todavía no está en el cache
--       (lo llena un sync cada 15 min) → queda NULL para siempre. Las 9 de LK se programaron
--       entre 0 y 4 minutos de entrar el pedido; ninguna de las que tienen fecha, después;
--     · los pedidos de Chef con order_id de 7 dígitos **no están en el cache ni van a estar**
--       (0 filas con id >= 1.000.000 en `lk_pedidos_match`, y `chef_orders_cache` de LK
--       tiene los ids 145..231 y ninguno nuevo) → NULL siempre. Ése es el caso de Thomas.
--
--   Ninguna de las 14 pasó por `PPP_Web_Tanda_Items` (el camino manual, que sí escribe la
--   columna): las 14 vienen del camino automático.
--
-- ⚠ Y NO SE PERSISTE LA FECHA CON FALLBACK. En `_sin_tanda` hay dos ahora:
--     `fecha_recep`      → `coalesce(<la del pedido>, current_date)`, para ORDENAR (no puede
--                          ser nula o la cola FIFO se rompe);
--     `fecha_recep_real` → la del pedido, pelada. **Es la que se guarda.**
--   Si el pedido no la trajo queda NULL, el trigger prueba el cache, y si tampoco, NULL y a
--   la vista del centinela. Escribir `current_date` sería anotar el día en que se programó
--   como si fuera el día en que entró el pedido: un dato equivocado que parece bueno.
-- ════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. el parche sobre la definición VIVA ───────────────────────────────────────────────
-- ⚠ Va como parche y no como el CREATE completo a propósito: la función tiene ~330 líneas,
-- el cambio son 4 anclajes, y la tocan varias sesiones (regla "traer la definición viva").
-- El bloque ABORTA si algún anclaje no aparece exactamente una vez, así que no puede
-- aplicarse a medias ni pisar el trabajo de otra sesión a ciegas.
do $$
declare s text; n1 int; n2 int; n3 int; n4 int;
  a1 text := E'         coalesce(nullif(x->>\'fecha_recep\',\'\')::date, current_date) as fecha_recep,';
  b1 text := E'         coalesce(nullif(x->>\'fecha_recep\',\'\')::date, current_date) as fecha_recep,\n'
          || E'         -- v20.63: la de arriba tiene fallback a hoy porque ORDENA la cola (FIFO) y no puede\n'
          || E'         -- ser nula. Esta es la de verdad, la que se PERSISTE: si el pedido no la trajo queda\n'
          || E'         -- nula y la completa el trigger gv_ppp_web_fecha_recep desde lk_pedidos_match. No se\n'
          || E'         -- inventa la fecha en que se programo.\n'
          || E'         nullif(x->>\'fecha_recep\',\'\')::date as fecha_recep_real,';
  a2 text := E'     tanda, zona, fecha_entrega, m3, m3_parcial, lineas, cajas)';
  b2 text := E'     tanda, zona, fecha_entrega, fecha_recep, m3, m3_parcial, lineas, cajas)';
  a3 text := E'         a.tanda, s.zona, v_fecha, s.m3, s.m3_parcial, s.lineas, s.cajas';
  b3 text := E'         a.tanda, s.zona, v_fecha, s.fecha_recep_real, s.m3, s.m3_parcial, s.lineas, s.cajas';
  a4 text := E'         fecha_entrega = excluded.fecha_entrega,';
  b4 text := E'         fecha_entrega = excluded.fecha_entrega,\n'
          || E'         fecha_recep = coalesce(public."PPP_Web_Programacion".fecha_recep, excluded.fecha_recep),';
begin
  s := pg_get_functiondef('public.ppp_web_armar_tandas(text,date,jsonb,text[],boolean)'::regprocedure);
  if s ~ 'fecha_recep_real' then raise notice 'ya aplicado, no se toca'; return; end if;
  select count(*) into n1 from regexp_matches(s, regexp_replace(a1,'([().|*+?\[\]{}\\^$])','\\\1','g'), 'g');
  select count(*) into n2 from regexp_matches(s, regexp_replace(a2,'([().|*+?\[\]{}\\^$])','\\\1','g'), 'g');
  select count(*) into n3 from regexp_matches(s, regexp_replace(a3,'([().|*+?\[\]{}\\^$])','\\\1','g'), 'g');
  select count(*) into n4 from regexp_matches(s, regexp_replace(a4,'([().|*+?\[\]{}\\^$])','\\\1','g'), 'g');
  if n1 <> 1 or n2 <> 1 or n3 <> 1 or n4 <> 1 then
    raise exception 'los anclajes no son unicos: n1=% n2=% n3=% n4=%', n1, n2, n3, n4;
  end if;
  s := replace(s, a1, b1);
  s := replace(s, a2, b2);
  s := replace(s, a3, b3);
  s := replace(s, a4, b4);
  execute s;
end $$;

-- ── 2. el centinela: qué NP quedó sin fecha, y si se puede recuperar ────────────────────
create or replace view public.gv_ppp_sin_fecha_recep as
 select public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np_label,
        p.empresa, p.order_id, p.cod_cliente, p.razon_social,
        p.tanda, p.fecha_entrega, p.creado_at, p.creado_por,
        (p.order_id >= 1000000) as formato_nuevo,
        m.fecha_pedido as fecha_del_feed,
        case when m.fecha_pedido is not null
               then 'se puede completar: el feed ya tiene el pedido'
             when p.order_id >= 1000000
               then 'el pedido no esta en el feed (order_id de 7 digitos, no entra a chef_orders_cache)'
             else 'el pedido no esta en el feed' end as motivo
   from public."PPP_Web_Programacion" p
   left join public.lk_pedidos_match m on m.empresa = p.empresa and m.order_id = p.order_id
  where p.fecha_recep is null;
alter view public.gv_ppp_sin_fecha_recep set (security_invoker = true);

-- ── 3. la regla que no se puede perder ──────────────────────────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
 ('ppp_web_armar_tandas','funcion','s\.fecha_recep_real',
  'El armador PERSISTE la fecha de recepcion que trae el pedido. La otra (fecha_recep, con fallback a hoy) solo ORDENA la cola FIFO y no se puede escribir: pondria el dia en que se programo. Sin esta regla la columna queda a merced del trigger, que lee el cache lk_pedidos_match, y un pedido recien entrado o de Chef formato nuevo se programa sin fecha.',
  'Thomas','v20.63')
) as v(objeto, clase, patron, regla, quien_pidio, version)
 where not exists (select 1 from public."GV_Reglas_Centinela" c
                    where c.objeto = v.objeto and c.patron = v.patron);

-- ════════════════════════════════════════════════════════════════════════════════════════
-- PROBADO CORRIENDO EL ARMADOR, no leyéndolo (regla: "un cambio de regla de armado no está
-- probado hasta que se corre el armador"). Dos pedidos de prueba, uno con fecha y otro sin,
-- dentro de una transacción abortada:
--
--   7777001 (trae 2026-09-10) -> fecha_recep = 2026-09-10   ✅
--   7777002 (no trae nada)    -> fecha_recep = NULL         ✅ (hoy era 2026-09-21)
--
-- ⚠ Con m³ chicos el armador NO programa nada (acumula hasta 0,80 m³, v13.67): la prueba se
-- corre con 1,1 / 1,2 m³ y los códigos en `p_forzar_cods`, o da 0 filas y parece que falla.
--
-- CHEQUEOS
--   select * from public.gv_reglas_perdidas;            -- vacía
--   select * from public.gv_ppp_sin_fecha_recep;        -- al 21/09: 14 (9 recuperables, 5 no)
--
-- LO QUE ESTO **NO** ARREGLA (queda a la vista en el centinela)
--   · Las 14 NP que ya estaban programadas sin fecha. Las 9 de LK se pueden completar desde
--     el feed —misma fuente que usa el trigger, no es inventar—; las 5 de Chef formato nuevo
--     no tienen de dónde. El UPDATE NO se ejecuta sin el "sí" del dueño (protocolo de datos):
--
--       -- backup primero
--       create table zz_backups."GV_Backup_FechaRecep_20260921" as
--         select * from public."PPP_Web_Programacion" where fecha_recep is null;
--       alter table zz_backups."GV_Backup_FechaRecep_20260921" enable row level security;
--       -- y recién entonces
--       update public."PPP_Web_Programacion" p
--          set fecha_recep = m.fecha_pedido, actualizado_at = now()
--         from public.lk_pedidos_match m
--        where m.empresa = p.empresa and m.order_id = p.order_id
--          and p.fecha_recep is null and m.fecha_pedido is not null;   -- 9 filas
--
--   · Que los pedidos de Chef con order_id de 7 dígitos entren al feed. Eso es del lado de
--     Chef/LK (`chef_orders_cache` no los tiene) y no se puede tocar desde este repo.
--
-- ROLLBACK: el parche inverso (los mismos 4 replace al revés) o
-- `sql/ppp_web_armar_tandas_v7_acumula.sql` + los parches posteriores. Y borrar la fila de
-- `GV_Reglas_Centinela` con version = 'v20.63'.
-- ════════════════════════════════════════════════════════════════════════════════════════
