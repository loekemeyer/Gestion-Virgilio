-- v15.01 — Pedidos Importación: 437EL / 438EL (LK) separados de 437E / 438E (CH)
-- Proyecto Supabase: hrxfctzncixxqmpfhskv
--
-- Dueño (2026-09-11): "se piden por separado, LK y CH. 438EL es para LK (para la impo,
-- después se vende como 438E y descuenta el de LK) y 438E para CH. No en conjunto."
--
-- El backend ya calculaba proyección y stock POR FILA (marca LK / CH) en v_importados_ordenes;
-- lo que los juntaba era el front, que agrupa por cod_art. Solución: la fila LK pasa a llamarse
-- …EL (convención L = góndola LK, la misma de la página de Chef) y la vista resuelve proyección,
-- stock y ventas con gv_cod_stock(cod_art), que pela la L → 438EL hereda proy/stock LK de 438E.
--
-- Backups: GV_Importados_bkp_437_438_20260911, GV_Importados_Volumen_bkp_437_438_20260911.

-- 1) Datos
update public."Importados" set cod_art = '437EL', actualizado = now() where id = 69 and cod_art = '437E' and marca = 'LK';
update public."Importados" set cod_art = '438EL', actualizado = now() where id = 65 and cod_art = '438E' and marca = 'LK';
update public."GV_Importados_Baches" set cod_art = '437EL' where importado_id = 69;
update public."GV_Importados_Baches" set cod_art = '438EL' where importado_id = 65;
insert into public."Importados_Volumen" (cod, largo_cm, ancho_cm, alto_cm, m3_master, uni_inner, uni_master, fuente)
select '437EL', largo_cm, ancho_cm, alto_cm, m3_master, uni_inner, uni_master, fuente from public."Importados_Volumen" where cod = '437E'
on conflict (cod) do nothing;
insert into public."Importados_Volumen" (cod, largo_cm, ancho_cm, alto_cm, m3_master, uni_inner, uni_master, fuente)
select '438EL', largo_cm, ancho_cm, alto_cm, m3_master, uni_inner, uni_master, fuente from public."Importados_Volumen" where cod = '438E'
on conflict (cod) do nothing;

-- 2) Vista: normaliza con gv_cod_stock (antes: ltrim(upper(btrim(x)),'0')). Misma lista de columnas.
--    Efecto colateral buscado: las entregas cargadas como …EL (438EL: 16 cajas, 439EL: 31 cajas)
--    ahora descuentan el stock LK del código base. La proyección sólo toma códigos BASE de
--    proyeccion_madre (una fila 574EL=0 no debe pisar el seed de 574E).
create or replace view public.v_importados_ordenes as
with cfg as (
  select meses_objetivo from public."Importados_Config" where id = 1
), mov as (
  select gv_cod_stock(ms.cod_art) as cod_norm,
         case when upper(coalesce(ms.marca,'')) = 'CH' then 'Chef' else 'Loeke' end as plant,
         sum(ms.delta_uni) as base_uni,
         min(ms.ts) filter (where ms.tipo = 'inicial') as inicial_ts
  from public."Importados_Mov_Stock" ms
  group by gv_cod_stock(ms.cod_art),
           case when upper(coalesce(ms.marca,'')) = 'CH' then 'Chef' else 'Loeke' end
), arm as (
  select gv_cod_stock(e.cod_art) as cod_norm, 'Loeke'::text as plant, e.creado as ts, coalesce(e.cajas_entregadas, 0::numeric) as cajas
  from public."Entregas_Virgilio" e
  union all
  select gv_cod_stock(e."Cod") as cod_norm, 'Chef'::text as plant, e.created_at as ts, coalesce(e."Cajas", 0) as cajas
  from public."Entregas Tallerista Cervantes" e
), ventas as (
  select a.cod_norm, a.plant, sum(a.cajas) as vc
  from arm a
  join mov m_1 on m_1.cod_norm = a.cod_norm and m_1.plant = a.plant
  where m_1.inicial_ts is not null and a.ts >= m_1.inicial_ts
  group by a.cod_norm, a.plant
), proy as (
  select gv_cod_stock(pm.cod) as cod_norm, max(pm.proy_uni_mes) as proy_uni_mes
  from public.proyeccion_madre pm
  where gv_cod_stock(pm.cod) = ltrim(upper(btrim(pm.cod)), '0')
  group by gv_cod_stock(pm.cod)
)
select i.id, i.cod_art, i.marca, i.proveedor, i.descripcion, i.fob_uni, i.uni_x_caja, i.principal, i.activo, i.notas,
       i.est_madre_seed, i.est_madre_override, i.pedido_manual,
       coalesce(i.pedido_curso, 0::numeric) as pedido_curso,
       case when upper(coalesce(i.marca,'')) = 'CH' then 'Chef' else 'Loeke' end as planta,
       p.proy_uni_mes as est_madre_live,
       (select cfg.meses_objetivo from cfg) as meses_objetivo,
       coalesce(i.est_madre_override,
                case when upper(coalesce(i.marca,'')) <> 'CH' then p.proy_uni_mes else null::numeric end,
                i.est_madre_seed, 0::numeric) as est_madre_eff,
       case when i.est_madre_override is not null then 'override'
            when upper(coalesce(i.marca,'')) <> 'CH' and p.proy_uni_mes is not null then 'live'
            else 'seed' end as est_madre_fuente,
       coalesce(m.base_uni, 0::numeric) - coalesce(v.vc, 0::numeric) * coalesce(i.uni_x_caja, 0::numeric) as stock_actual
from public."Importados" i
left join mov m    on m.cod_norm = gv_cod_stock(i.cod_art) and m.plant = case when upper(coalesce(i.marca,'')) = 'CH' then 'Chef' else 'Loeke' end
left join ventas v on v.cod_norm = gv_cod_stock(i.cod_art) and v.plant = case when upper(coalesce(i.marca,'')) = 'CH' then 'Chef' else 'Loeke' end
left join proy p   on p.cod_norm = gv_cod_stock(i.cod_art);

-- 3) Feed a la página LK: sólo filas no-CH (438E·CH tiene su fecha; no debe pisar la de 438EL·LK)
create or replace function public.lk_reingresos_feed()
returns table(cod text, reingreso_est date, sin_stock boolean)
language sql stable security definer set search_path to 'public' as $$
  with imp as (
    select gv_cod_stock(cod_art) as cod,
           max(reingreso_est)         as reingreso_est,
           max(nullif(uni_x_caja, 0)) as uxc
    from public."Importados"
    where coalesce(activo, true) and reingreso_est is not null
      and upper(coalesce(marca, '')) <> 'CH'
    group by gv_cod_stock(cod_art)
  ),
  parte as (
    select gv_cod_stock(cod) as cod, sum(coalesce(stock_parte, 0)) as stock_parte
    from public.vista_importados_stock_parte
    group by gv_cod_stock(cod)
  )
  select i.cod, i.reingreso_est,
         ( coalesce(svp.pedidos_ped, 0)
           > coalesce(svp.stock_total, 0) + coalesce(floor(coalesce(pt.stock_parte, 0) / nullif(i.uxc, 0)), 0)
         ) as sin_stock
  from imp i
  left join public.vista_stock_vs_pedidos svp on svp.cod = i.cod
  left join parte pt on pt.cod = i.cod;
$$;

-- ROLLBACK
--   update public."Importados" i set cod_art = b.cod_art from public."GV_Importados_bkp_437_438_20260911" b where b.id = i.id;
--   update public."GV_Importados_Baches" set cod_art = '437E' where importado_id = 69;
--   update public."GV_Importados_Baches" set cod_art = '438E' where importado_id = 65;
--   delete from public."Importados_Volumen" where cod in ('437EL','438EL');
--   Vista y feed anteriores: mismas definiciones con ltrim(upper(btrim(x)),'0') en vez de gv_cod_stock(x),
--   sin el filtro "where gv_cod_stock(pm.cod) = ltrim(...)" en proy, y sin "marca <> 'CH'" en el feed
--   (ver docs/SUPABASE-GESTION-VIRGILIO.md §3.bm).
