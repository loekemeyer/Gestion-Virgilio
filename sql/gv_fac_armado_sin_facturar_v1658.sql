-- v16.58 — Problema 58: una NP armada SIN TANDA no aparece en Facturación
--
-- El Facturador arma su lista recorriendo TANDAS (monitor de la PPP + `vista_tanda_status`).
-- Una NP que se armó pero quedó sin tanda en la PPP —o que ya ni figura en la PPP— no está en
-- ninguna tanda, así que **no se lista**, aunque esté armada, con salida registrada y sin
-- facturar. No hay error en pantalla: simplemente no está.
--
-- La prueba de que se armó es `Entregas_Virgilio` (una fila por artículo entregado), y esa
-- tabla no depende de la tanda. De ahí sale esta vista.
--
-- MEDIDO al 2026-09-13: **21 NP armadas sin facturar, 1.456 cajas**, de las cuales **8 son
-- invisibles** en la pantalla:
--
--   NP      origen            cliente          tanda  salida      cajas  por que no se ve
--   44612   isis              CENCOSUD S.A.    D72B   2026-09-10     28  esta en la PPP sin tanda
--   44613   isis              CENCOSUD S.A.    D72B   2026-09-10     76  esta en la PPP sin tanda
--   44614   isis              CENCOSUD S.A.    D72B   2026-09-10      5  esta en la PPP sin tanda
--   44615   isis              CENCOSUD S.A.    D72C   2026-09-10    118  esta en la PPP sin tanda
--   44616   isis              CENCOSUD S.A.    D72C   2026-09-10    291  esta en la PPP sin tanda
--   44617   isis              CENCOSUD S.A.    D72C   2026-09-10    120  esta en la PPP sin tanda
--   44500   fuera de la PPP   (cod 1768)       C86C   2026-07-22      5  la NP no esta en la PPP
--   98272   fuera de la PPP   (cod 2336)       D20F   2026-08-14      4  la NP no esta en la PPP
--
--   638 cajas son de CENCOSUD. Las otras 13 NP (809 cajas) sí se ven.
--
-- ⚠ Ojo con el registro viejo del problema: decía "sólo 8 se ven". Medido hoy es al revés:
-- **13 se ven y 8 no**. El total (21 NP) sí coincide.
--
-- La vista dice, por cada NP, si la pantalla la muestra y por qué no:
--   `se_ve_en_facturacion` (bool) y `por_que_no_se_ve` ('la NP esta en la PPP pero sin tanda'
--   / 'la NP no esta en la PPP').
--
-- FRONT: `facSinTandaCargar()` + el bloque de `facRender()` en `index.html` las inyectan como
-- filas normales, con la tanda del ARMADO, así se pueden **tildar igual que cualquier otra**
-- (no es sólo un aviso). Llevan un chip amarillo "sin tanda" para que se entienda de dónde
-- salieron. Si la vista no responde, la lista queda exactamente como antes.

create or replace view public.gv_fac_armado_sin_facturar with (security_invoker = true) as
with ent as (
  select btrim(e.np) as np,
         max(nullif(btrim(e.tanda),'')) as tanda_armado,
         max(nullif(btrim(e.fecha_salida),'')) as fecha_salida,
         sum(coalesce(e.cajas_entregadas,0)) as cajas,
         max(nullif(btrim(e.cod_cliente),'')) as cod
    from public."Entregas_Virgilio" e
   where nullif(btrim(e.np),'') is not null
   group by 1
), prog as (
  select btrim(d.np) as np, nullif(btrim(d.tanda),'') as tanda, d.razon_social, 'isis'::text as origen
    from public.gv_ppp_programacion_diaria d
  union all
  select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx), nullif(btrim(w.tanda),''), w.razon_social, 'web'
    from public."PPP_Web_Programacion" w where w.np is not null
)
select e.np,
       coalesce(p.origen, 'fuera de la PPP') as origen,
       e.cod,
       coalesce(p.razon_social, f.razon_social) as razon_social,
       e.tanda_armado,
       p.tanda as tanda_ppp,
       e.fecha_salida,
       e.cajas,
       (p.np is not null and p.tanda is not null) as se_ve_en_facturacion,
       case when p.np is null then 'la NP no esta en la PPP'
            when p.tanda is null then 'la NP esta en la PPP pero sin tanda'
            else null end as por_que_no_se_ve
  from ent e
  left join prog p on p.np = e.np
  left join public."Facturacion_NP" f on btrim(f.np) = e.np
 where not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = e.np);

grant select on public.gv_fac_armado_sin_facturar to anon, authenticated;

-- Chequeo:
--   select se_ve_en_facturacion, por_que_no_se_ve, count(*), sum(cajas)
--     from public.gv_fac_armado_sin_facturar group by 1,2;
