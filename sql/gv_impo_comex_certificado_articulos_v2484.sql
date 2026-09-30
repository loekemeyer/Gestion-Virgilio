-- v24.84 (Elías, 30/09): IMPO COMEX · una fila por artículo certificado.
-- Aplicado. Aditivo: 2 columnas nullable + 1 vista. Rollback al final.
alter table impo_comex.certificado_codigos add column if not exists marca text, add column if not exists descripcion text;
create or replace view impo_comex.v_certificado_articulos with (security_invoker = true) as
select cc.codigo,
       coalesce(nullif(btrim(cc.marca),''), pr.marca, c.marcas) as marca,
       coalesce(nullif(btrim(cc.descripcion),''), pr.nombre_producto, c.descripcion) as descripcion,
       c.titular_razon_social as importador,
       c.fabricante as elaborador,
       c.numero, c.tipo, c.organismo, c.fecha_emision, c.fecha_vencimiento, c.estado, c.dias_restantes,
       c.id as certificado_id,
       (cc.marca is not null or cc.descripcion is not null) as dato_del_certificado
  from impo_comex.certificado_codigos cc
  join impo_comex.v_certificados_estado c on c.id = cc.certificado_id
  left join lateral (
    select p.marca, p.nombre_producto from impo_comex.productos_referencia p
     where upper(btrim(cc.codigo)) in (upper(btrim(p.cod_lk)), upper(btrim(p.cod_ch)))
     order by p.id limit 1) pr on true;
-- Rollback:
-- drop view impo_comex.v_certificado_articulos;
-- alter table impo_comex.certificado_codigos drop column marca, drop column descripcion;

-- v24.86: país de origen y depósito del RNE (antes la IA los leía y se descartaban). Aplicado.
alter table impo_comex.certificados_inal add column if not exists pais_origen text, add column if not exists deposito text;
-- v_certificados_estado: se agregaron pais_origen, deposito AL FINAL (security_invoker=true conservado).

-- v24.87 (Elías): "Descripción" = NOMBRE del artículo. Anexo por código -> productos_referencia ->
-- precios_venta (LK) -> precios_venta_chef -> vista_nombres_articulos. Nunca la descripción general
-- del certificado: sin nombre, queda vacía. Aplicado con create or replace (security_invoker=true).

-- v24.98 (Elías): el nombre se busca también en las VERSIONES del código, con y sin letras.
-- impo_comex.nombre_articulo(cod): exacto > sin la L > con/sin E final > E intercalada > número+E > número.
-- Catálogo: productos_referencia > precios_venta > precios_venta_chef > vista_nombres_articulos.
-- La vista suma descripcion_de (código de donde salió) y descripcion_prio (1 exacto … 6 número pelado).
-- Al 30/09: 86 de 92 con nombre, 73 por versión. Sin nombre: 090E–093E, 443E, 443EL.
