-- v23.93 (Luis, 29/09) — «📲 Avisar programación» tomaba SÓLO las NP de ISIS.
--
-- El síntoma: el módulo abría con 15 filas y ninguna era de la página. Medido antes del cambio:
--   select count(*) filas, count(*) filter (where np ~ '^(LK|CH) ') web
--     from public.vista_ppp_programacion_pendiente;   -- 15 filas, 0 web
--
-- La causa: vista_ppp_programacion_pendiente leía únicamente gv_ppp_prog_rs (el espejo de ISIS).
-- Desde que los pedidos de la página se programan solos (v13.47), el 99 % de lo programado vive
-- en PPP_Web_Programacion, así que el aviso al cliente no salía para casi nadie.
--
-- El arreglo es UNION ALL con la rama web. Lo de aguas abajo NO se toca:
-- vista_avisar_programacion ya resuelve empresa, teléfono y vendedor por empresa a partir de la NP
-- (gv_empresa_de_np_texto), así que con el prefijo `LK 0123` / `CH 0045` agrupa bien sola.
--
-- ⚠ La NP web se etiqueta con gv_ppp_web_np_label(empresa, np, np_idx), NUNCA con np pelado:
--    el código de cliente es por empresa (regla de Thomas, 16/09) y sin prefijo `4181` de LK y
--    `4181` de Chef son dos personas distintas.
-- ⚠ Se saltean las canceladas (GV_PPP_Web_NP_Cancelada) y las ya facturadas con cierre, igual que
--    la rama de ISIS: avisarle a un cliente de un pedido cancelado es peor que no avisarle.
-- ⚠ security_invoker = true: CREATE OR REPLACE VIEW sin WITH (...) BORRA las reloptions.

create or replace view public.vista_ppp_programacion_pendiente
with (security_invoker = true) as
 select p.tanda, p.np, p.tipo, p.cod as cod_cliente, p.razon_social, p.m3, p.zona, p.barrio,
        p.direccion, p.op, p.fecha_recep, p.fecha_entrega, p.fecha_fc, p.observaciones
   from gv_ppp_prog_rs p
  where not exists (select 1 from "Facturacion_NP" f
                     where f.np = p.np and f.cierre_id is not null)
union all
 select w.tanda,
        public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
        'WEB'::text as tipo,
        btrim(w.cod_cliente) as cod_cliente, w.razon_social, w.m3, w.zona, w.barrio,
        w.direccion, w.op,
        to_char(w.fecha_recep, 'YYYY-MM-DD') as fecha_recep,
        to_char(w.fecha_entrega, 'YYYY-MM-DD') as fecha_entrega,
        null::text as fecha_fc,
        w.observaciones
   from "PPP_Web_Programacion" w
  where w.fecha_entrega is not null
    and not exists (select 1 from "Facturacion_NP" f
                     where f.np = public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)
                       and f.cierre_id is not null)
    and not exists (select 1 from "GV_PPP_Web_NP_Cancelada" c
                     where c.empresa = w.empresa and c.order_id = w.order_id and c.np_idx = w.np_idx);

alter view public.vista_ppp_programacion_pendiente set (security_invoker = true);

-- ── medición (29/09, después) ─────────────────────────────────────────────────
-- select count(*) filas, count(*) filter (where np ~ '^(LK|CH) ') web
--   from public.vista_ppp_programacion_pendiente;              -- 141 filas, 126 web
-- select count(*) from (select np from public.vista_ppp_programacion_pendiente
--                        group by np having count(*) > 1) z;   -- 0 NP duplicadas
-- select count(*) grupos,
--        count(*) filter (where telefono is not null) con_tel,
--        count(*) filter (where empresa is null) sin_empresa
--   from public.vista_avisar_programacion;                     -- 82 · 67 · 0

-- ⚠ Y se prueba como ANON, que es la identidad del navegador (trampa de la v20.45: una vista con
--    security_invoker sobre una tabla con RLS no da error, devuelve MENOS filas):
-- do $$ declare n int; begin
--   set local role anon; select count(*) into n from public.vista_avisar_programacion; reset role;
--   raise notice 'anon ve %', n; end $$;

-- ── centinela (pendiente del «sí» del dueño: es un insert) ────────────────────
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
-- values ('vista_ppp_programacion_pendiente','vista','PPP_Web_Programacion',
--         'Avisar programación tiene que tomar TAMBIÉN los pedidos web, no sólo los de ISIS',
--         'Luis','v23.93');

-- ── rollback ─────────────────────────────────────────────────────────────────
-- create or replace view public.vista_ppp_programacion_pendiente
-- with (security_invoker = true) as
--  select p.tanda, p.np, p.tipo, p.cod as cod_cliente, p.razon_social, p.m3, p.zona, p.barrio,
--         p.direccion, p.op, p.fecha_recep, p.fecha_entrega, p.fecha_fc, p.observaciones
--    from gv_ppp_prog_rs p
--   where not exists (select 1 from "Facturacion_NP" f
--                      where f.np = p.np and f.cierre_id is not null);
