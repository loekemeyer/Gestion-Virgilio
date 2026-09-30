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
