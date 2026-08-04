-- =====================================================================
-- generar_ocs_automaticas.sql — OCs automáticas los MIÉRCOLES 7:00 AR (v7.17)
--
-- Pedido del usuario: que las órdenes de compra se generen solas, con esta
-- definición de stock y de demanda (distinta de la que tenía el generador manual):
--
--   Stock disponible = góndola (terminado) + a_guardar + racks + excedente.
--     NO entran: separar_pedidos (pickeado), a_facturar, facturado / FC sin salida,
--     racks_ch (Cervantes) ni para_envasar.
--   Demanda (Pedidos) = cajas del PPP de los pedidos que TODAVÍA no consumieron
--     stock: NP no facturada Y cuya tanda no tiene TP (picking terminado).
--     Un pedido "en armar sin marcar ningún artículo" o sin empezar SÍ cuenta;
--     uno ya pickeado NO — su mercadería está en separar_pedidos, que tampoco se
--     cuenta como stock: NETEA de los dos lados y no se pide dos veces lo mismo.
--   Máximo = proyección por tendencia (proyeccion_madre) × índice (OC_Maximos.indice,
--     default 1,5), topado a la capacidad de góndola (Capacidad_Sector). Si el
--     artículo no tiene proyección, cae al objetivo del Excel (OC_Maximos.max_cajas).
--   A pedir = ceil(max(0, Máximo + Pedidos − Stock)).
--
-- Proveedores INTERNOS (Racks, Log/Fabr) no generan OC (igual que el manual).
-- Las líneas quedan en `Ordenes_Compra` con `notas = 'auto <fecha>'`, estado
-- 'pendiente' y rubro 'Art Term' — o sea que la Recepción de Mercadería las ve
-- como OC vigente al toque (ver `ROC` / v7.07).
--
-- IDEMPOTENTE por día: si ya hay OCs automáticas de hoy no vuelve a generar
-- (devuelve 'ya_generada'). `select generar_ocs_automaticas(true)` fuerza.
-- Devuelve 'ok:<n>' | 'sin_items' | 'ya_generada'. Avisa por Telegram al terminar.
--
-- El generador MANUAL de la app (index.html → ocgEnter) usa exactamente la misma
-- fórmula desde v7.17, así que dan lo mismo.
--
-- Cron: 'ocs-auto-miercoles' → '0 10 * * 3' (10:00 UTC = 7:00 AR, UTC-3 fijo).
-- Prueba en seco 2026-08-04: 104 líneas · 19 proveedores · 9.198 cajas
-- (165 NPs sin facturar → 138 cuentan como demanda; 27 ya pickeadas se netean).
--
-- ⚠ La definición VIVA está en la migración `generar_ocs_automaticas` de Supabase;
-- este archivo es la copia documentada para el repo.
-- =====================================================================


create or replace function public.generar_ocs_automaticas(p_forzar boolean default false)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_n int := 0; v_cajas numeric := 0; v_prov int := 0; v_msg text;
begin
  if not p_forzar and exists (select 1 from public."Ordenes_Compra"
                               where fecha = v_hoy and coalesce(notas, '') like 'auto%') then
    return 'ya_generada';
  end if;

  with norm as (   -- misma normalización que el front (_ocgNorm)
    select regexp_replace(upper(btrim(m.cod)), '^0+(?=.)', '') as codn,
           upper(btrim(m.cod)) as cod, m.descripcion, btrim(coalesce(m.proveedor, '')) as proveedor,
           coalesce(m.max_cajas, 0)::numeric as max_excel,
           case when coalesce(m.indice, 0) > 0 then m.indice::numeric else 1.5 end as indice
      from public."OC_Maximos" m
     where m.activo and nullif(btrim(m.cod), '') is not null
  ),
  stk as (   -- SOLO góndola + a guardar + racks + excedente
    select regexp_replace(upper(btrim(cod_art)), '^0+(?=.)', '') as codn,
           sum(coalesce(terminado, 0) + coalesce(a_guardar, 0) + coalesce(racks, 0) + coalesce(excedente, 0)) as stock
      from public.vista_saldos_stock group by 1
  ),
  pickeadas as (   -- tandas con picking TERMINADO: su stock ya salió de góndola
    select distinct upper(btrim(texto)) as tanda
      from public."Registros_Produccion_Virgilio"
     where opcion = 'TP' and nullif(btrim(coalesce(texto, '')), '') is not null
  ),
  pend_np as (     -- pedidos que todavía no consumieron stock (netea)
    select distinct btrim(p.np) as np
      from public."PPP_Programacion_Diaria" p
     where btrim(p.np) not in (select btrim(np) from public."Facturacion_NP")
       and upper(btrim(coalesce(p.tanda, ''))) not in (select tanda from pickeadas)
  ),
  dem as (
    select regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)', '') as codn,
           sum(coalesce(b.cajas, 0)) as pedidos
      from public."PPP_Base_Pedidos" b
      join pend_np n on btrim(b.pedido) = n.np
     where nullif(btrim(b.articulo), '') is not null
     group by 1
  ),
  proy as (
    select regexp_replace(upper(btrim(cod)), '^0+(?=.)', '') as codn,
           max(coalesce(proy_cajas_mes, 0))::numeric as proy
      from public.proyeccion_madre group by 1
  ),
  cap as (
    select regexp_replace(upper(btrim(cod)), '^0+(?=.)', '') as codn,
           sum(coalesce(cajas_max, 0))::numeric as cap
      from public."Capacidad_Sector" group by 1
  ),
  calc as (
    select n.cod, n.descripcion, n.proveedor,
           coalesce(s.stock, 0) as stock, coalesce(d.pedidos, 0) as pedidos,
           least(
             ceil(case when p.proy is not null and p.proy > 0 then p.proy * n.indice else n.max_excel end),
             coalesce(nullif(c.cap, 0), 1e9)
           ) as maximo
      from norm n
      left join stk s on s.codn = n.codn
      left join dem d on d.codn = n.codn
      left join proy p on p.codn = n.codn
      left join cap c on c.codn = n.codn
     where upper(n.proveedor) not in ('RACKS', 'LOG/ FABR', 'LOG/FABR', 'LOG/ FABRICA')
       and nullif(n.proveedor, '') is not null
  ),
  ins as (
    insert into public."Ordenes_Compra"
      (fecha, rubro, proveedor, codigo, descripcion, cantidad, cantidad_recibida, unidad, estado, notas)
    select v_hoy, 'Art Term', proveedor, cod, nullif(descripcion, ''),
           ceil(maximo + pedidos - stock)::int, 0, 'Cajas', 'pendiente',
           'auto ' || to_char(v_hoy, 'YYYY-MM-DD')
      from calc
     where ceil(maximo + pedidos - stock) > 0
    returning proveedor, cantidad
  )
  select count(*), coalesce(sum(cantidad), 0), count(distinct proveedor) into v_n, v_cajas, v_prov from ins;

  if v_n = 0 then return 'sin_items'; end if;

  v_msg := '📑 OCs GENERADAS AUTOMÁTICAMENTE — ' || to_char(v_hoy, 'DD/MM') || E'\n' ||
           v_n || ' línea(s) · ' || v_prov || ' proveedor(es) · ' || round(v_cajas) || ' cajas' || E'\n' ||
           'Stock contado: góndola + a guardar + racks + excedente (sin pickeados / a facturar).' || E'\n' ||
           'Revisalas en Stock y Compras → Compras (OCs).';
  begin
    perform public.tg_enqueue(v_msg, 'ocauto_' || to_char(v_hoy, 'YYYYMMDD'));
    perform public.tg_outbox_flush();
  exception when others then null; end;

  return 'ok:' || v_n;
end $fn$;

revoke all on function public.generar_ocs_automaticas(boolean) from public;
grant execute on function public.generar_ocs_automaticas(boolean) to authenticated;

-- Cron: miércoles 07:00 AR = 10:00 UTC (UTC-3 fijo).
select cron.unschedule(jobid) from cron.job where jobname = 'ocs-auto-miercoles';
select cron.schedule('ocs-auto-miercoles', '0 10 * * 3', $$select public.generar_ocs_automaticas()$$);
