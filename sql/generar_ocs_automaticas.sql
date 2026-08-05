-- =====================================================================
-- generar_ocs_automaticas.sql — OCs automáticas los MIÉRCOLES 7:00 AR (v7.18)
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
--     default 1,5), topado a la capacidad de góndola (Capacidad_Sector). Si el artículo
--     NO tiene proyección: el objetivo = capacidad de góndola (v7.68), pero SOLO para los
--     que tienen proveedor real (si no, no se pide por tener góndola vacía).
--   A pedir = ceil(max(0, Máximo + Pedidos − Stock)).
--
-- v7.68 — CAMBIO DE FONDO: el universo YA NO sale de OC_Maximos (lista a mano) sino de
--   STOCK. Todo se encapsula en la vista `vista_generador_oc` (universo = productos
--   terminados de stock ∪ proyección ∪ pedidos; stock con empresa LK/CH mergeada — arregla
--   el sobre-pedido de códigos partidos; uni×caja = maestro→backup estático→uxb). OC_Maximos
--   quedó como SOLO config de proveedor/%/índice/activo por código. El front (ocgEnter) y
--   este cron leen la MISMA vista. Los "(sin proveedor)" se muestran pero NO se auto-generan.
--
-- v7.65: "Log/ Fabr" (fábrica) SÍ genera OC (pedido del usuario). "Racks" (importación)
-- se EXCLUYE — se abastece por otra vía. (Igual que el generador manual.)
-- Las líneas quedan en `Ordenes_Compra` con `notas = 'auto <fecha>'`, estado
-- 'pendiente' y rubro 'Art Term' — o sea que la Recepción de Mercadería las ve
-- como OC vigente al toque (ver `ROC` / v7.07).
--
-- IDEMPOTENTE por día: si ya hay OCs de hoy —de CUALQUIER origen, automáticas o
-- cargadas a mano— no genera nada (para no duplicar) y AVISA por Telegram para que
-- alguien las revise, en vez de saltear en silencio. `generar_ocs_automaticas(true)`
-- fuerza igual. (Hasta v7.20 la guarda miraba sólo `notas like 'auto%'`: si alguien
-- generaba a mano un miércoles antes de las 7, el cron sumaba las suyas encima.)
--
-- AVISOS por Telegram (dedup diario, tg_enqueue -> telegram_outbox):
--   generó         -> '📑 OCs GENERADAS AUTOMÁTICAMENTE …'    (dedup ocauto_<día>)
--   ya había OCs   -> '⚠ OCs AUTOMÁTICAS NO GENERADAS … REVISÁ las OCs de hoy …'
--                                                            (dedup ocauto_skip_<día>)
--   falló          -> '🚨 FALLÓ la generación automática de OCs …' + el error SQL
--                                                            (dedup ocauto_err_<día>)
-- El bloque de generación tiene su propio `exception when others`: si algo revienta,
-- la inserción se deshace pero el aviso de error SÍ sale (antes moría en silencio).
--
-- Devuelve 'ok:<n>' | 'sin_items' | 'ya_hay_del_dia:<n>' | 'error: <sqlerrm>'.
--
-- El generador MANUAL de la app (index.html → ocgEnter) usa exactamente la misma
-- fórmula desde v7.18, así que dan lo mismo.
--
-- v7.39: cada línea guarda además oc_max / oc_pedidos / oc_stock / oc_uni_caja (los
-- valores usados al generar) para que el IMPRESO de la OC reproduzca el formato de la
-- planilla del tallerista sin recalcular: Cajas=cantidad, Falta Pedidos=máx(0,
-- Pedidos−Stock), % Lleno=(Stock−Pedidos)/Máximo, Uni x Caja=oc_uni_caja.
--
-- v7.42: guarda además oc_ncaja = tipo de caja del producto (columna "Caja N°" del
-- impreso). Sale de `Articulos_Cajas.N_Caja`, tomando la N_Caja MÁS FRECUENTE por
-- código normalizado (desempate: la más chica). Falta Pedidos y % Lleno quedan
-- CONGELADOS al momento de generar (se desactivó el cron 'oc-backfill-diario' que los
-- refrescaba a diario): reflejan el estado del día de la OC, no el de hoy.
--
-- Cron: 'ocs-auto-miercoles' → '0 10 * * 3' (10:00 UTC = 7:00 AR, UTC-3 fijo).
-- Prueba en seco 2026-08-04: 104 líneas · 19 proveedores · 9.198 cajas
-- (165 NPs sin facturar → 138 cuentan como demanda; 27 ya pickeadas se netean).
-- Los dos caminos nuevos se probaron en una transacción con ROLLBACK (sin generar ni
-- mandar nada): con una OC de hoy → 'ya_hay_del_dia:1' + aviso encolado; con un check
-- constraint que rompe el INSERT → 'error: …' + aviso de error encolado.
--
-- ⚠ La definición VIVA está en la migración `generar_ocs_automaticas` de Supabase;
-- este archivo es la copia documentada para el repo.
-- =====================================================================


create or replace function public.generar_ocs_automaticas(p_forzar boolean default false)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_n int := 0; v_cajas numeric := 0; v_prov int := 0; v_msg text;
  v_hay int := 0; v_hay_auto int := 0; v_hay_man int := 0;
begin
  -- ¿ya hay OCs de hoy? (automáticas O cargadas a mano) → no duplicar, y avisar.
  if not p_forzar then
    select count(*), count(*) filter (where coalesce(notas, '') like 'auto%')
      into v_hay, v_hay_auto
      from public."Ordenes_Compra" where fecha = v_hoy;
    if v_hay > 0 then
      v_hay_man := v_hay - v_hay_auto;
      v_msg := '⚠ OCs AUTOMÁTICAS NO GENERADAS — ' || to_char(v_hoy, 'DD/MM') || E'\n' ||
               'Ya había ' || v_hay || ' línea(s) de hoy' ||
               case when v_hay_man > 0 and v_hay_auto > 0
                      then ' (' || v_hay_man || ' a mano + ' || v_hay_auto || ' automáticas)'
                    when v_hay_man > 0 then ' cargada(s) a mano'
                    else ' automáticas' end || '.' || E'\n' ||
               'No se generó nada para no duplicar. 👉 REVISÁ las OCs de hoy en Stock y Compras → ' ||
               'Compras (OCs): si falta pedir algo, generalas a mano con ⚙ Generar OCs.';
      begin
        perform public.tg_enqueue(v_msg, 'ocauto_skip_' || to_char(v_hoy, 'YYYYMMDD'));
        perform public.tg_outbox_flush();
      exception when others then null; end;
      return 'ya_hay_del_dia:' || v_hay;
    end if;
  end if;

  -- la generación va en su propio bloque: si algo revienta, el aviso sobrevive.
  begin
  with split as (   -- v7.68: TODO el cálculo vive en vista_generador_oc (universo desde STOCK,
                    -- Máximo = proy×índice o capacidad de góndola como objetivo, stock con empresa
                    -- LK/CH mergeada, pedidos, uni×caja). Acá SOLO se parte por proveedor (Prov 1 %
                    -- pr1 / Prov 2 = resto) y se insertan los que tienen proveedor real: los
                    -- "(sin proveedor)" se muestran en el front pero NO se auto-generan.
    select cod, descripcion, uni_x_caja as uni_caja, n_caja, proveedor as prov,
           round(maximo * pr1 / 100.0) as oc_max, round(pedidos * pr1 / 100.0) as oc_ped, round(stock * pr1 / 100.0) as oc_stk,
           round(total * pr1 / 100.0)::int as cantidad
      from public.vista_generador_oc
     where activo and total > 0 and tiene_prov_real
    union all
    select cod, descripcion, uni_x_caja, n_caja, proveedor2 as prov,
           maximo - round(maximo * pr1 / 100.0), pedidos - round(pedidos * pr1 / 100.0), stock - round(stock * pr1 / 100.0),
           total - round(total * pr1 / 100.0)::int
      from public.vista_generador_oc
     where activo and total > 0 and tiene_prov_real and proveedor2 is not null and pr2 > 0
  ),
  ins as (
    insert into public."Ordenes_Compra"
      (fecha, rubro, proveedor, codigo, descripcion, cantidad, cantidad_recibida, unidad, estado, notas,
       oc_max, oc_pedidos, oc_stock, oc_uni_caja, oc_ncaja)
    select v_hoy, 'Art Term', prov, cod, nullif(descripcion, ''),
           cantidad, 0, 'Cajas', 'pendiente',
           'auto ' || to_char(v_hoy, 'YYYY-MM-DD'),
           oc_max, oc_ped, oc_stk, uni_caja, n_caja
      from split
     where cantidad > 0 and nullif(btrim(prov), '') is not null
       and upper(btrim(prov)) not in ('RACKS', 'RACK')   -- v7.65: Racks afuera; Log/Fabr SÍ genera
    returning proveedor, cantidad
  )
  select count(*), coalesce(sum(cantidad), 0), count(distinct proveedor) into v_n, v_cajas, v_prov from ins;
  exception when others then
    v_msg := '🚨 FALLÓ la generación automática de OCs — ' || to_char(v_hoy, 'DD/MM') || E'\n' ||
             coalesce(sqlerrm, 'error desconocido') || ' (' || coalesce(sqlstate, '?') || ')' || E'\n' ||
             'NO se generó ninguna OC. 👉 Generalas a mano en Stock y Compras → Compras (OCs) → ⚙ Generar OCs.';
    begin
      perform public.tg_enqueue(v_msg, 'ocauto_err_' || to_char(v_hoy, 'YYYYMMDD'));
      perform public.tg_outbox_flush();
    exception when others then null; end;
    return 'error: ' || coalesce(sqlerrm, '?');
  end;

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
