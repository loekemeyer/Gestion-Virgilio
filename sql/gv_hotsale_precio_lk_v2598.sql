-- v25.98 · Hot Sale: lo que importan TIERRA NATIVA o CHEF no puede quedar a pérdida en LK (Thomas, 01/10/2026).
-- Thomas registra UNA vez a cuánto le venden en dólares a LK (tabla nueva GV_Importado_Precio_LK) y el dólar
-- (GV_HotSale_Param, clave 'dolar'); la pantalla saca la rentabilidad de LK por artículo = precio al que LK le
-- factura al súper (última factura de ISIS, $/u) ÷ (u$s × dólar) − 1, hoy, en las semanas de hot sale y ponderada.
-- Referencia para precargar: la última factura Chef → LK (isis_ch, cliente 1434 = Loekemeyer Hnos) de cada
-- artículo importado; el parser la marca «Pesos» pero el precio unitario (0,93 / 0,55 / 0,75) es en dólares.
-- Para Tierra Nativa no hay fuente (1 sola factura de compra parseada): se tipea.
-- Objetos NUEVOS; gv_hotsale_items_super cambia de firma (columnas AL FINAL).
-- ⚠⚠ CÓMO SE APLICÓ DE VERDAD (01/10/2026): el `drop function` se COLGABA en el MCP (execute_sql: 60 s sin
--    respuesta, 3 veces; ni `lock_timeout = 5s` ni `statement_timeout = 15s` saltaron, pg_stat_activity sin
--    nadie trabado, y el drop de una función sin uso también se colgaba — o sea, no es la base: es la capa
--    del MCP con esa sentencia). `create function` y `alter function … rename` andan. Así que la función
--    nueva se creó con otro nombre y se RENOMBRÓ: la vieja (11 columnas) quedó como
--    `gv_hotsale_items_super_v2593` (sin execute para anon/authenticated) y la nueva tomó el nombre.
--    El bloque de abajo deja ese camino; el `drop` original queda comentado por si el MCP lo vuelve a aceptar.
-- Rollback: alter function public.gv_hotsale_items_super(text,int) rename to gv_hotsale_items_super_v2598;
--           alter function public.gv_hotsale_items_super_v2593(text,int) rename to gv_hotsale_items_super;
--           grant execute on function public.gv_hotsale_items_super(text,int) to anon, authenticated, service_role;
--           drop function public.gv_hotsale_precio_lk_guardar(text,numeric,text); drop function public.gv_hotsale_param_guardar(text,numeric);
--           drop function public.gv_hotsale_params(); drop table public."GV_Importado_Precio_LK"; drop table public."GV_HotSale_Param";

create table if not exists public."GV_Importado_Precio_LK" (
  cod             text primary key,            -- código base (sin ceros a la izquierda, sin L)
  importador      text,                        -- 'Tierra Nativa' | 'Chef' (informativo, lo que decía GV_Imp_Proveedor al cargar)
  precio_usd      numeric not null check (precio_usd >= 0),   -- u$s por UNIDAD que le cobra el importador a LK
  nota            text,
  actualizado_por text,
  actualizado_at  timestamptz not null default now()
);
alter table public."GV_Importado_Precio_LK" enable row level security;
revoke all on public."GV_Importado_Precio_LK" from anon, authenticated;

create table if not exists public."GV_HotSale_Param" (
  clave           text primary key,            -- 'dolar' = $ por u$s
  valor           numeric not null,
  actualizado_por text,
  actualizado_at  timestamptz not null default now()
);
alter table public."GV_HotSale_Param" enable row level security;
revoke all on public."GV_HotSale_Param" from anon, authenticated;

create or replace function public.gv_hotsale_quien() returns text
language sql stable set search_path = public, pg_temp as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', current_user::text);
$$;

create or replace function public.gv_hotsale_precio_lk_guardar(p_cod text, p_precio_usd numeric, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cod text := regexp_replace(regexp_replace(upper(btrim(coalesce(p_cod,''))),'^0+',''),'([0-9E])L$','\1');
        v_imp text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then raise exception 'SOLO_SUPERVISOR'; end if;
  if v_cod = '' then raise exception 'COD_VACIO'; end if;
  if p_precio_usd is null then
    delete from public."GV_Importado_Precio_LK" where cod = v_cod;
    return jsonb_build_object('cod', v_cod, 'borrado', true);
  end if;
  select gp.importador into v_imp from public."Importados" im left join public."GV_Imp_Proveedor" gp on gp.proveedor = im.proveedor
   where regexp_replace(upper(btrim(im.cod_art)),'^0+','') = v_cod limit 1;
  insert into public."GV_Importado_Precio_LK" (cod, importador, precio_usd, nota, actualizado_por, actualizado_at)
  values (v_cod, v_imp, p_precio_usd, nullif(btrim(coalesce(p_nota,'')),''), gv_hotsale_quien(), now())
  on conflict (cod) do update set precio_usd = excluded.precio_usd, importador = coalesce(excluded.importador, "GV_Importado_Precio_LK".importador),
        nota = excluded.nota, actualizado_por = excluded.actualizado_por, actualizado_at = now();
  return jsonb_build_object('cod', v_cod, 'precio_usd', p_precio_usd, 'importador', v_imp);
end $$;

create or replace function public.gv_hotsale_param_guardar(p_clave text, p_valor numeric)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then raise exception 'SOLO_SUPERVISOR'; end if;
  if p_clave not in ('dolar') then raise exception 'CLAVE_DESCONOCIDA: %', p_clave; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'VALOR_INVALIDO'; end if;
  insert into public."GV_HotSale_Param" (clave, valor, actualizado_por, actualizado_at) values (p_clave, p_valor, gv_hotsale_quien(), now())
  on conflict (clave) do update set valor = excluded.valor, actualizado_por = excluded.actualizado_por, actualizado_at = now();
  return jsonb_build_object('clave', p_clave, 'valor', p_valor);
end $$;

create or replace function public.gv_hotsale_params()
returns jsonb language sql security definer set search_path = public, pg_temp as $$
  select case when (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
              then coalesce((select jsonb_object_agg(clave, jsonb_build_object('valor', valor, 'actualizado_at', actualizado_at, 'por', actualizado_por)) from public."GV_HotSale_Param"), '{}'::jsonb)
              else null end;
$$;

-- drop function if exists public.gv_hotsale_items_super(text, int);   -- se colgaba en el MCP (ver cabecera)
create function public.gv_hotsale_items_super_lk(p_super_key text, p_meses int default 12)
returns table(empresa text, cod text, cod_base text, descripcion text, es_importado boolean, rubro text, tipo text,
              ultima_compra date, cajas numeric, unidades numeric, lineas int,
              importador text, precio_usd_lk numeric, precio_usd_nota text, venta_unit numeric, venta_fecha date, uxb numeric,
              ref_chef_usd numeric, ref_chef_fecha date)
language sql security definer set search_path = public, pg_temp as $$
  with g as (select empresa, regexp_replace(cod,'^0+','') cod from public."GV_Supers" where activo and super_key = p_super_key),
  li as (
    select 'lk'::text empresa, i.codigo_articulo cod, i.descripcion, d.fecha, i.cantidad_caja, i.cantidad, i.precio_unit, i.id lid
      from g join isis_lk.documentos d on g.empresa = 'lk' and d.familia = 'factura_venta'
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = g.cod
       and d.fecha >= current_date - make_interval(months => greatest(coalesce(p_meses,12),1))
      join isis_lk.documento_items i on i.documento_id = d.id
    union all
    select 'chef', i.codigo_articulo, i.descripcion, d.fecha, i.cantidad_caja, i.cantidad, i.precio_unit, i.id
      from g join isis_ch.documentos d on g.empresa = 'chef' and d.familia = 'factura_venta'
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = g.cod
       and d.fecha >= current_date - make_interval(months => greatest(coalesce(p_meses,12),1))
      join isis_ch.documento_items i on i.documento_id = d.id),
  a as (
    select empresa, upper(btrim(cod)) cod,
           regexp_replace(regexp_replace(upper(btrim(cod)),'^0+',''),'([0-9E])L$','\1') cod_base,
           (array_agg(descripcion order by fecha desc, lid desc))[1] descripcion,
           max(fecha) ultima_compra,
           round(sum(coalesce(cantidad_caja,0)),2) cajas, round(sum(coalesce(cantidad,0)),2) unidades, count(*)::int lineas,
           (array_agg(precio_unit order by fecha desc, lid desc))[1] venta_unit,
           (array_agg(fecha order by fecha desc, lid desc))[1] venta_fecha,
           (array_agg(case when coalesce(cantidad_caja,0) > 0 and coalesce(cantidad,0) > 0 then round(cantidad / cantidad_caja, 2) end
                      order by fecha desc, lid desc) filter (where coalesce(cantidad_caja,0) > 0 and coalesce(cantidad,0) > 0))[1] uxb_fc
      from li where coalesce(btrim(cod),'') <> '' group by 1,2,3),
  chefref as (
    select regexp_replace(regexp_replace(upper(btrim(i.codigo_articulo)),'^0+',''),'([0-9E])L$','\1') cod_base,
           (array_agg(i.precio_unit order by d.fecha desc, i.id desc))[1] usd, max(d.fecha) fecha
      from isis_ch.documentos d join isis_ch.documento_items i on i.documento_id = d.id
     where d.familia = 'factura_venta' and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = '1434'
       and d.fecha >= current_date - interval '24 months'
     group by 1)
  select a.empresa, a.cod, a.cod_base, a.descripcion,
         (im.cod_art is not null) es_importado,
         coalesce(t.familia, 'Sin rubro') rubro, t.tipo, a.ultima_compra, a.cajas, a.unidades, a.lineas,
         case when im.cod_art is not null then gp.importador end importador,
         pl.precio_usd, pl.nota,
         a.venta_unit, a.venta_fecha,
         coalesce(a.uxb_fc, (select u.uxb from public.vista_uxb_articulo u where regexp_replace(upper(btrim(u.cod)),'^0+','') = a.cod_base limit 1)) uxb,
         case when im.cod_art is not null then cr.usd end ref_chef_usd,
         case when im.cod_art is not null then cr.fecha end ref_chef_fecha
    from a
    left join lateral (select im.cod_art, im.proveedor from public."Importados" im where regexp_replace(upper(btrim(im.cod_art)),'^0+','') = a.cod_base order by im.activo desc limit 1) im on true
    left join public."GV_Imp_Proveedor" gp on gp.proveedor = im.proveedor
    left join public."GV_Importado_Precio_LK" pl on pl.cod = a.cod_base
    left join chefref cr on cr.cod_base = a.cod_base
    left join lateral (select pt.familia, pt.tipo from public."GV_Producto_Tipo" pt
                        where regexp_replace(upper(btrim(pt.cod)),'^0+','') = a.cod_base limit 1) t on true
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by a.ultima_compra desc, a.cajas desc, a.cod;
$$;

-- la vieja queda de rollback con otro nombre; la nueva toma el nombre que llama hotsale.js
alter function public.gv_hotsale_items_super(text, int) rename to gv_hotsale_items_super_v2593;
alter function public.gv_hotsale_items_super_lk(text, int) rename to gv_hotsale_items_super;
revoke all on function public.gv_hotsale_items_super_v2593(text, int) from public, anon, authenticated;
revoke all on function public.gv_hotsale_items_super(text, int) from public;
revoke all on function public.gv_hotsale_precio_lk_guardar(text, numeric, text) from public;
revoke all on function public.gv_hotsale_param_guardar(text, numeric) from public;
revoke all on function public.gv_hotsale_params() from public;
grant execute on function public.gv_hotsale_items_super(text, int) to anon, authenticated, service_role;
grant execute on function public.gv_hotsale_precio_lk_guardar(text, numeric, text) to anon, authenticated, service_role;
grant execute on function public.gv_hotsale_param_guardar(text, numeric) to anon, authenticated, service_role;
grant execute on function public.gv_hotsale_params() to anon, authenticated, service_role;

-- Medido el 01/10 (como postgres, MCP): Jumbo (cencosud) 50 ítems · 31 importados · 26 por Tierra Nativa · 5 por Chef ·
-- 5 con referencia Chef → LK (816E 0,79 · 819E 0,98 · 812E 1,05 · 585E 1,50 · 811E 1,64, facturas del 28/01/26) ·
-- los 50 con venta_unit y uxb. 45 ms la llamada.
