-- idea 4528 (noche 2026-09-05, agente mejoras-virgilio) · migración gv_np_prog_sin_base_web_v1328
-- Alerta de tanda WEB sin artículos. vista_np_prog_sin_base (v12.05) sólo mira ISIS (PPP_Programacion_Diaria
-- vs PPP_Base_Pedidos): una NP web programada sin líneas en PPP_Web_Base no la detectaba nadie y el
-- operario abría la tanda vacía. Dos vistas NUEVAS (gv_), sólo lectura, security_invoker.
-- El front (rama idea/4528) lee gv_np_prog_sin_base en vez de vista_np_prog_sin_base: mismas columnas + origen.
-- Medido al crearla: ISIS 0 · web 0 (las 18 NP web con tanda tienen líneas en PPP_Web_Base).
create or replace view public.gv_ppp_web_prog_sin_base with (security_invoker = true) as
  with prog as (
    select public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np,
           p.empresa, p.order_id, p.np_idx,
           nullif(btrim(coalesce(p.tanda, '')), '') as tanda,
           nullif(btrim(coalesce(p.razon_social, '')), '') as cliente,
           p.fecha_entrega::text as fecha_entrega,
           coalesce(p.m3, 0) as m3
      from public."PPP_Web_Programacion" p
     where p.np is not null and coalesce(nullif(btrim(p.tanda), ''), '') <> ''
  )
  select p.np, p.tanda, p.cliente, p.fecha_entrega, round(p.m3, 2) as m3, p.empresa, p.order_id, p.np_idx
    from prog p
   where not exists (select 1 from public."PPP_Web_Base" b
                      where b.empresa = p.empresa and b.order_id = p.order_id and b.np_idx = p.np_idx)
     and not exists (select 1 from public."Facturacion_NP" f where upper(btrim(f.np)) = upper(p.np))
     and not exists (select 1 from public."NP_Sin_Base_Revisadas" r where upper(btrim(r.np)) = upper(p.np));
grant select on public.gv_ppp_web_prog_sin_base to anon, authenticated, service_role;

create or replace view public.gv_np_prog_sin_base with (security_invoker = true) as
  select v.np, v.tanda, v.cliente, v.fecha_entrega, v.m3, 'isis'::text as origen from public.vista_np_prog_sin_base v
  union all
  select w.np, w.tanda, w.cliente, w.fecha_entrega, w.m3, 'web'::text from public.gv_ppp_web_prog_sin_base w;
grant select on public.gv_np_prog_sin_base to anon, authenticated, service_role;
-- Rollback: drop view public.gv_np_prog_sin_base; drop view public.gv_ppp_web_prog_sin_base;  (el front de main sigue leyendo la vieja)
