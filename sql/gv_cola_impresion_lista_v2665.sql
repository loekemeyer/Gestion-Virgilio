-- v26.65 (Luis, 05/10): COLA DE IMPRESIÓN NP — todas las NP (pasadas y presentes) con las hojas
-- que se pueden imprimir porque está la data, y si ya salieron.
--   · picking   → es de la TANDA (TP de la tanda; marca «PK <tanda>» en Impresion_NP)
--   · armado    → es de la NP (TAL con resumen, o Entregas_Virgilio de un armado vivo; marca «<np>»)
--   · facturado → es de la NP (Facturacion_NP.facturado_at + el resumen del TAL; marca «FAC <np>»)
-- La impresión AUTOMÁTICA sale sólo por el helper conectado y respondiendo; lo que no salió queda
-- pendiente acá (front: gvImprimirAuto). Lectura pura, SECURITY INVOKER: lee lo mismo que ya lee
-- el front con la clave pública (probado como anon).
--
-- Pendiente (para el badge y «Imprimir pendientes»), cada uno desde que existe su marca:
--   picking  TP desde 2026-10-01 (v25.51) · armado TAL desde 2026-08-25 12:10 (ancla de vista_cola_impresion)
--   facturado desde 2026-10-05 13:00 (antes la marca vivía sólo en el navegador de la estación).
--
-- Rollback: drop function if exists public.gv_cola_impresion_lista(date, date);

create or replace function public.gv_cola_impresion_lista(p_desde date, p_hasta date)
returns table (
  fecha date, np text, empresa text, tanda text, cod_cliente text, razon_social text,
  pick_ts timestamptz, pick_leg text, pick_impreso_en timestamptz, pick_pend boolean,
  arm_ts timestamptz, arm_resumen text, arm_leg text, arm_arts jsonb, arm_falt jsonb,
  arm_impreso_en timestamptz, arm_pend boolean,
  fac_ts timestamptz, fac_impreso_en timestamptz, fac_pend boolean)
language sql stable security invoker
set search_path = public
as $$
with
_ci_web as (
  select distinct on (gv_ppp_web_np_label(p.empresa, p.np, p.np_idx))
         gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np,
         upper(btrim(coalesce(p.tanda, ''))) as tanda, p.fecha_entrega as fecha,
         btrim(coalesce(p.cod_cliente, '')) as cod, btrim(coalesce(p.razon_social, '')) as rs
    from "PPP_Web_Programacion" p
   order by gv_ppp_web_np_label(p.empresa, p.np, p.np_idx), p.actualizado_at desc nulls last
),
_ci_isis as (
  select distinct on (regexp_replace(btrim(d.np), '\.0+$', ''))
         regexp_replace(btrim(d.np), '\.0+$', '') as np,
         upper(btrim(coalesce(d.tanda, ''))) as tanda,
         case when d.fecha_entrega ~ '^\d{4}-\d{2}-\d{2}' then left(d.fecha_entrega, 10)::date end as fecha,
         btrim(coalesce(d.cod, '')) as cod, btrim(coalesce(d.razon_social, '')) as rs
    from gv_ppp_programacion_diaria d
   where coalesce(btrim(d.np), '') <> ''
   order by regexp_replace(btrim(d.np), '\.0+$', ''), d.id desc
),
_ci_fac as (
  select distinct on (regexp_replace(btrim(f.np), '\.0+$', ''))
         regexp_replace(btrim(f.np), '\.0+$', '') as np,
         upper(btrim(coalesce(f.tanda, ''))) as tanda, f.fecha_salida as fecha,
         btrim(coalesce(f.cod_cliente, '')) as cod, btrim(coalesce(f.razon_social, '')) as rs,
         f.facturado_at
    from "Facturacion_NP" f
   where coalesce(btrim(f.np), '') <> ''
   order by regexp_replace(btrim(f.np), '\.0+$', ''), f.facturado_at desc nulls last
),
_ci_tal as (
  select distinct on (regexp_replace(btrim(split_part(r.texto, '|', 1)), '\.0+$', ''))
         regexp_replace(btrim(split_part(r.texto, '|', 1)), '\.0+$', '') as np,
         upper(btrim(split_part(r.texto, '|', 3))) as tanda, r.ts_cliente as arm_ts,
         split_part(r.texto, '|', 4) as resumen, r.legajo
    from "Registros_Produccion_Virgilio" r
   where r.opcion = 'TAL' and coalesce(r.legajo, '') not in ('0', '1')
   order by regexp_replace(btrim(split_part(r.texto, '|', 1)), '\.0+$', ''), r.ts_cliente desc
),
_ci_np as (
  select w.np from _ci_web w where w.fecha between p_desde and p_hasta
  union select i.np from _ci_isis i where i.fecha between p_desde and p_hasta
  union select f.np from _ci_fac f where f.fecha between p_desde and p_hasta
  union select t.np from _ci_tal t
   where (t.arm_ts at time zone 'America/Argentina/Buenos_Aires')::date between p_desde and p_hasta
),
_ci_base as (
  select n.np,
         coalesce(w.fecha, i.fecha, f.fecha, (t.arm_ts at time zone 'America/Argentina/Buenos_Aires')::date) as fecha,
         coalesce(nullif(w.tanda, ''), nullif(i.tanda, ''), nullif(t.tanda, ''), nullif(f.tanda, '')) as tanda,
         coalesce(nullif(w.cod, ''), nullif(i.cod, ''), nullif(f.cod, '')) as cod,
         coalesce(nullif(w.rs, ''), nullif(i.rs, ''), nullif(f.rs, '')) as rs,
         f.facturado_at, t.arm_ts, nullif(t.resumen, '') as resumen, t.legajo as arm_leg
    from _ci_np n
    left join _ci_web w on w.np = n.np
    left join _ci_isis i on i.np = n.np
    left join _ci_fac f on f.np = n.np
    left join _ci_tal t on t.np = n.np
),
_ci_ev as materialized (   -- sin materialized el plan lo re-agrega una vez por fila (2,4 s)
  select btrim(e.np) as np,
         coalesce(jsonb_agg(jsonb_build_object('cod', upper(btrim(e.cod_art)), 'cajas', e.cajas_entregadas)
                  order by upper(btrim(e.cod_art))) filter (where coalesce(e.cajas_entregadas, 0) > 0), '[]'::jsonb) as arts,
         coalesce(jsonb_agg(jsonb_build_object('cod', upper(btrim(e.cod_art)), 'cajas', e.cajas_falto)
                  order by upper(btrim(e.cod_art))) filter (where coalesce(e.cajas_falto, 0) > 0), '[]'::jsonb) as falt
    from "Entregas_Virgilio" e
   where btrim(e.np) in (select b.np from _ci_base b)
     and coalesce(e.tanda, '') !~ '-X$'          -- un armado anulado no es hoja (v21.21)
   group by btrim(e.np)
),
_ci_tp as (
  select distinct on (upper(btrim(r.texto))) upper(btrim(r.texto)) as tanda, r.ts_cliente as ts, r.legajo
    from "Registros_Produccion_Virgilio" r
   where r.opcion = 'TP' and coalesce(r.legajo, '') not in ('0', '1')
   order by upper(btrim(r.texto)), r.ts_cliente desc
)
select b.fecha, b.np,
       case when gv_emp_de_np(b.np) = 'lk' then 'LK' else 'CH' end,
       b.tanda, b.cod, b.rs,
       tp.ts, tp.legajo, ip.impreso_en,
       (tp.ts is not null and ip.np is null and tp.ts >= '2026-10-01 00:00-03'::timestamptz),
       b.arm_ts, b.resumen, b.arm_leg, coalesce(ev.arts, '[]'::jsonb), coalesce(ev.falt, '[]'::jsonb),
       ia.impreso_en,
       ((b.resumen is not null or jsonb_array_length(coalesce(ev.arts, '[]'::jsonb)) > 0
                               or jsonb_array_length(coalesce(ev.falt, '[]'::jsonb)) > 0)
        and ia.np is null and b.arm_ts >= '2026-08-25 12:10-03'::timestamptz),
       b.facturado_at, ifa.impreso_en,
       (b.facturado_at is not null and b.resumen is not null and ifa.np is null
        and b.facturado_at >= '2026-10-05 13:00-03'::timestamptz)
  from _ci_base b
  left join _ci_tp tp on b.tanda is not null and tp.tanda = b.tanda
  left join "Impresion_NP" ip on ip.np = 'PK ' || b.tanda
  left join "Impresion_NP" ia on ia.np = b.np
  left join "Impresion_NP" ifa on ifa.np = 'FAC ' || b.np
  left join _ci_ev ev on ev.np = b.np
 where b.fecha between p_desde and p_hasta
   and coalesce(b.tanda, '') !~ '^PRUEBA'         -- clientes de prueba (v21.63)
 order by b.fecha desc, b.tanda nulls last, b.np;
$$;

revoke all on function public.gv_cola_impresion_lista(date, date) from public;
grant execute on function public.gv_cola_impresion_lista(date, date) to anon, authenticated, service_role;
