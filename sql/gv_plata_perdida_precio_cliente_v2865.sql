-- v28.64 (Luis, 08/10): Plata perdida — precio del CLIENTE del pedido y sin los códigos sin precio.
-- 1) empresa de la NP por gv_empresa_de_np_texto (antes 'LK 0001' caía como chef).
-- 2) precio: primero el del cliente (GV_Precios_Cliente, último facturado al cliente), después la lista de SU empresa.
-- 3) la pantalla lee por gv_plata_perdida() (supervisor) y sólo filas con precio. anon no lee la vista.
-- Rollback: la definición anterior está en zz_backups."GV_Backup_PlataPerdida_def_20261008".
create or replace view public.vista_plata_perdida as
 WITH ev AS (
   SELECT e_1.id, e_1.fecha_salida, e_1.cod_cliente, e_1.np, e_1.cod_art, e_1.cajas_pedidas, e_1.cajas_entregadas,
          e_1.cajas_falto, e_1.tanda, e_1.creado, e_1.gv_empresa,
          coalesce(gv_empresa_de_np_texto(e_1.np),
                   CASE WHEN regexp_replace(e_1.np, '\.0+$', '') ~ '^9' THEN 'lk' ELSE 'chef' END) AS empresa,
          upper(btrim(e_1.cod_art)) ~ '[0-9E]L$' AS es_art_lk
     FROM "Entregas_Virgilio" e_1
    WHERE COALESCE(e_1.cajas_falto, 0) > 0
 ), ev2 AS (
   SELECT ev.*,
          CASE WHEN ev.es_art_lk THEN 'lk' ELSE ev.empresa END AS empresa_precio,
          CASE WHEN ev.es_art_lk THEN norm_cod(regexp_replace(upper(btrim(ev.cod_art)), 'L$', '')) ELSE norm_cod(ev.cod_art) END AS nc_precio,
          CASE WHEN ev.es_art_lk THEN canon_cod(regexp_replace(upper(btrim(ev.cod_art)), 'L$', '')) ELSE canon_cod(ev.cod_art) END AS cc_precio
     FROM ev
 ), pr AS (
   SELECT e.*,
          nullif(nullif(COALESCE(pcl.precio_unit, pfc.precio_neto,
                   CASE WHEN e.empresa_precio = 'chef' THEN pc.precio_unit ELSE pv.precio_unit END), 8888), 0) AS pu,
          COALESCE(pc.descripcion, pv.descripcion, '') AS descr,
          COALESCE(uxe.uxb, 1) AS uxb
     FROM ev2 e
     LEFT JOIN "GV_Precios_Cliente" pcl ON pcl.empresa = e.empresa AND pcl.cod_cliente = regexp_replace(e.cod_cliente, '\D', '', 'g') AND norm_cod(pcl.cod) = e.nc_precio
     LEFT JOIN "GV_Precio_Facturado_Cache" pfc ON pfc.empresa = e.empresa AND pfc.cod_cliente = regexp_replace(e.cod_cliente, '\D', '', 'g') AND pfc.cod_canon = e.cc_precio
     LEFT JOIN precios_venta_chef pc ON e.empresa_precio = 'chef' AND norm_cod(pc.cod) = e.nc_precio
     LEFT JOIN precios_venta pv ON norm_cod(pv.cod) = e.nc_precio
     LEFT JOIN gv_uxb_emp uxe ON uxe.empresa_precio = e.empresa_precio AND uxe.cod_norm = e.nc_precio
 )
 SELECT e.np, norm_cod(e.cod_art) AS cod, btrim(e.cod_art) AS cod_raw, e.cajas_falto AS cajas, e.cajas_pedidas AS ped,
        e.cajas_entregadas AS ent, "left"(e.fecha_salida, 10) AS fecha, btrim(e.cod_cliente) AS cod_cliente,
        COALESCE(e.pu, 0::numeric) AS precio_unit, e.uxb, e.descr AS descripcion,
        (e.pu IS NOT NULL AND e.pu > 0) AS precio_ok,
        CASE WHEN e.pu > 0 THEN COALESCE(e.cajas_falto, 0) * e.uxb::numeric * e.pu ELSE 0::numeric END AS plata,
        COALESCE(btrim(cv.vend), '') AS vendedor,
        COALESCE(fnp.razon_social, '') AS razon_social
   FROM pr e
   LEFT JOIN gv_cliente_contacto cv ON cv.empresa = e.empresa AND cv.cod = regexp_replace(btrim(e.cod_cliente), '^0+', '')
   LEFT JOIN "Facturacion_NP" fnp ON btrim(fnp.np) = btrim(e.np);

create or replace function public.gv_plata_perdida()
returns setof public.vista_plata_perdida
language plpgsql stable security definer set search_path = public, pg_temp
as $fn$
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  return query select * from public.vista_plata_perdida v where v.cajas > 0 and v.precio_ok;
end
$fn$;
revoke all on function public.gv_plata_perdida() from public, anon;
grant execute on function public.gv_plata_perdida() to authenticated;
