-- ============================================================================
-- v17.21 — sales_lines se llena desde los comprobantes de ISIS
--
-- Reemplaza la carga manual mensual del Excel al Table Editor. La empresa sale
-- del esquema de origen, asi que el bug que hacia aparecer a Cencosud como
-- Relca no puede volver a pasar.
--
-- Chequeo previo: §3.em de docs/SUPABASE-GESTION-VIRGILIO.md y
-- sql/gv_chequeo_isis_como_fuente_v1716.sql. Resumen: ISIS reproduce el Excel
-- al entero desde 2026-02 (junio: 141 de 141 clientes y 183 de 196 articulos
-- identicos); antes de esa fecha el backfill de PDF viejos esta incompleto
-- (2024 -7 %, 2025 -6 %), por eso el corte.
--
-- ⚠ SE ENTREGA APAGADO. `GV_Sales_Auto_Config.activo = 0`: la funcion y el cron
-- corren, miden y NO escriben. Prender es una sola linea (abajo).
--
-- ORDEN DE APLICACION: primero VIRGILIO, despues LK.
-- ============================================================================


-- ###########################################################################
-- ## VIRGILIO (hrxfctzncixxqmpfhskv) — la fuente
-- ###########################################################################

-- Las ventas de las dos empresas, unidas y listas para consumir:
--   * NC en negativo
--   * sin comprobantes de proveedor (contraparte_tipo = 'cliente')
--   * sin las lineas de texto legal (codigo_articulo is null: "2 % Descuento
--     Web", "Pequenos Contribuyentes de la Ley 27.618"... todas con 0 cajas)
--   * la empresa sale del ESQUEMA, no de una columna que alguien puede olvidar
create or replace view public.gv_isis_ventas_feed
with (security_invoker = true) as
  select 'lk'::text                  as empresa,
         d.fecha::date               as fecha,
         btrim(d.contraparte_codigo) as cod_cliente,
         btrim(i.codigo_articulo)    as cod_articulo,
         ((case when d.tipo ~* '^NC' then -1 else 1 end) * i.cantidad_caja)::bigint as cajas,
         d.tipo                      as tipo_comprobante,
         d.id                        as documento_id,
         i.nro_linea
    from isis_lk.documentos d
    join isis_lk.documento_items i on i.documento_id = d.id
   where d.contraparte_tipo = 'cliente' and d.fecha is not null
     and d.contraparte_codigo is not null
     and i.codigo_articulo is not null and i.cantidad_caja is not null
  union all
  select 'chef'::text, d.fecha::date, btrim(d.contraparte_codigo), btrim(i.codigo_articulo),
         ((case when d.tipo ~* '^NC' then -1 else 1 end) * i.cantidad_caja)::bigint,
         d.tipo, d.id, i.nro_linea
    from isis_ch.documentos d
    join isis_ch.documento_items i on i.documento_id = d.id
   where d.contraparte_tipo = 'cliente' and d.fecha is not null
     and d.contraparte_codigo is not null
     and i.codigo_articulo is not null and i.cantidad_caja is not null;

comment on view public.gv_isis_ventas_feed is
  'v17.21 - ventas de ISIS listas para sales_lines de LK: las dos empresas unidas, NC en negativo, sin lineas de texto legal ni comprobantes de proveedor. La empresa sale del esquema (isis_lk / isis_ch).';

-- Acceso para el rol del FDW. Las tablas tienen RLS prendida: `documentos` ya
-- tenia su policy, a `documento_items` le faltaba.
grant usage  on schema isis_lk, isis_ch to lk_ppp_reader;
grant select on isis_lk.documentos, isis_lk.documento_items,
                isis_ch.documentos, isis_ch.documento_items to lk_ppp_reader;
grant select on public.gv_isis_ventas_feed to lk_ppp_reader;
create policy lk_ppp_reader_ro on isis_lk.documento_items for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_ro on isis_ch.documento_items for select to lk_ppp_reader using (true);


-- ###########################################################################
-- ## LK (kwkclwhmoygunqmlegrg) — el destino
-- ###########################################################################

drop foreign table if exists virgilio.isis_ventas;
create foreign table virgilio.isis_ventas (
  empresa text, fecha date, cod_cliente text, cod_articulo text,
  cajas bigint, tipo_comprobante text, documento_id bigint, nro_linea int
) server virgilio_db options (schema_name 'public', table_name 'gv_isis_ventas_feed');

create schema if not exists zz_backups;
revoke all on schema zz_backups from anon, authenticated;

-- El interruptor y el corte
create table if not exists public."GV_Sales_Auto_Config" (
  clave       text primary key,
  valor       text not null,
  nota        text,
  actualizado timestamptz not null default now()
);
alter table public."GV_Sales_Auto_Config" enable row level security;
revoke insert, update, delete, truncate on public."GV_Sales_Auto_Config" from anon, authenticated;

insert into public."GV_Sales_Auto_Config" (clave, valor, nota) values
 ('activo', '0', 'En 0 la funcion solo informa y NO escribe. Ponerlo en 1 para que reemplace de verdad.'),
 ('desde',  '2026-02-01', 'Corte: de esta fecha en adelante manda ISIS. Antes se deja lo cargado a mano (el backfill de PDF viejos esta incompleto: 2024 -7 %, 2025 -6 %).')
on conflict (clave) do nothing;

-- La carga. Idempotente: borra el tramo desde el corte y lo vuelve a escribir.
-- Con activo=0 devuelve la medicion y no toca nada.
create or replace function public.gv_sales_lines_auto_sync(p_aplicar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, virgilio, pg_temp
as $fn$
declare
  v_activo boolean; v_desde date; v_desde_txt text;
  v_hoy_filas bigint; v_hoy_cajas bigint;
  v_isis_filas bigint; v_isis_cajas bigint;
  v_borradas bigint := 0; v_insertadas bigint := 0; v_backup boolean := false;
begin
  select (valor = '1') into v_activo from public."GV_Sales_Auto_Config" where clave = 'activo';
  select valor::date  into v_desde  from public."GV_Sales_Auto_Config" where clave = 'desde';
  v_desde_txt := to_char(v_desde, 'YYYY-MM-DD');

  select count(*), coalesce(sum(boxes),0) into v_hoy_filas, v_hoy_cajas
    from public.sales_lines where invoice_date >= v_desde_txt;

  select count(*), coalesce(sum(v.cajas),0) into v_isis_filas, v_isis_cajas
    from virgilio.isis_ventas v
   where v.fecha >= v_desde
     and upper(btrim(v.cod_articulo)) not in (select upper(item_code) from public.sales_excluded_items);

  if not p_aplicar or not coalesce(v_activo,false) then
    return jsonb_build_object(
      'aplicado', false, 'activo', coalesce(v_activo,false), 'desde', v_desde_txt,
      'sales_lines_hoy', jsonb_build_object('filas', v_hoy_filas, 'cajas', v_hoy_cajas),
      'isis_traeria',    jsonb_build_object('filas', v_isis_filas, 'cajas', v_isis_cajas),
      'nota', case when not coalesce(v_activo,false)
                   then 'activo=0 en GV_Sales_Auto_Config: solo informa, no escribe'
                   else 'llamar con p_aplicar => true para aplicar' end);
  end if;

  -- backup una sola vez: la foto de como estaba antes de la primera corrida
  if to_regclass('zz_backups."GV_Backup_Sales_Lines_PreISIS"') is null then
    create table zz_backups."GV_Backup_Sales_Lines_PreISIS" as
      select * from public.sales_lines where invoice_date >= v_desde_txt;
    alter table zz_backups."GV_Backup_Sales_Lines_PreISIS" enable row level security;
    revoke insert, update, delete, truncate on zz_backups."GV_Backup_Sales_Lines_PreISIS" from anon, authenticated;
    v_backup := true;
  end if;

  delete from public.sales_lines where invoice_date >= v_desde_txt;
  get diagnostics v_borradas = row_count;

  -- row_hash tiene indice UNICO. La clave (empresa, documento, linea) es unica:
  -- medido 33.041 filas / 33.041 claves. El prefijo 'isis:' evita chocar con lo
  -- que dejo la carga manual.
  insert into public.sales_lines (invoice_date, customer_code, item_code, boxes,
                                  empresa, import_batch, imported_at, row_hash)
  select to_char(v.fecha,'YYYY-MM-DD'), v.cod_cliente, v.cod_articulo, v.cajas, v.empresa,
         'isis_auto', now(),
         'isis:' || v.empresa || ':' || v.documento_id || ':' || v.nro_linea
    from virgilio.isis_ventas v
   where v.fecha >= v_desde
     and upper(btrim(v.cod_articulo)) not in (select upper(item_code) from public.sales_excluded_items);
  get diagnostics v_insertadas = row_count;

  return jsonb_build_object('aplicado', true, 'desde', v_desde_txt, 'backup_creado', v_backup,
    'borradas', v_borradas, 'insertadas', v_insertadas, 'cajas', v_isis_cajas, 'at', now());
end $fn$;

revoke execute on function public.gv_sales_lines_auto_sync(boolean) from public, anon, authenticated;

-- El tablero para correr los dos en paralelo antes de prender
create or replace view public.gv_sales_isis_vs_excel
with (security_invoker = true) as
with corte as (select valor::date d from public."GV_Sales_Auto_Config" where clave='desde'),
 hoy as (
  select left(invoice_date,7) mes, empresa, sum(boxes)::bigint cajas, count(*)::bigint filas
    from public.sales_lines, corte
   where invoice_date >= to_char(corte.d,'YYYY-MM-DD') group by 1,2
), isis as (
  select to_char(v.fecha,'YYYY-MM') mes, v.empresa, sum(v.cajas)::bigint cajas, count(*)::bigint filas
    from virgilio.isis_ventas v, corte
   where v.fecha >= corte.d
     and upper(btrim(v.cod_articulo)) not in (select upper(item_code) from public.sales_excluded_items)
   group by 1,2
)
select coalesce(h.mes, i.mes) mes, coalesce(h.empresa, i.empresa) empresa,
       coalesce(h.cajas,0) cajas_cargadas, coalesce(i.cajas,0) cajas_isis,
       coalesce(i.cajas,0) - coalesce(h.cajas,0) diferencia,
       round(100.0*(coalesce(i.cajas,0) - coalesce(h.cajas,0))/nullif(h.cajas,0),1) pct,
       coalesce(h.filas,0) filas_cargadas, coalesce(i.filas,0) filas_isis
  from hoy h full join isis i on i.mes = h.mes and i.empresa = h.empresa;

-- El cron. Corre todos los dias 07:40 ART; mientras activo=0 no hace nada.
select cron.schedule('gv-sales-lines-desde-isis', '40 10 * * *',
  $cron$select public.gv_sales_lines_auto_sync(true);$cron$);


-- ###########################################################################
-- ## COMO SE PRENDE  (una linea, en LK)
-- ###########################################################################
--   update public."GV_Sales_Auto_Config" set valor='1', actualizado=now() where clave='activo';
--   select public.gv_sales_lines_auto_sync(true);   -- primera corrida a mano
--
-- ## COMO SE APAGA / ROLLBACK
--   update public."GV_Sales_Auto_Config" set valor='0' where clave='activo';
--   -- y para volver exactamente al estado previo:
--   delete from public.sales_lines where import_batch = 'isis_auto';
--   insert into public.sales_lines select * from zz_backups."GV_Backup_Sales_Lines_PreISIS";
--
-- ## QUE MIRAR ANTES DE PRENDER
--   select * from public.gv_sales_isis_vs_excel order by mes, empresa;
--   select public.gv_sales_lines_auto_sync();       -- sin aplicar, solo mide
