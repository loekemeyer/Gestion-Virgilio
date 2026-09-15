-- v18.62 (2026-09-15) — gv_lecturas_al_limite: cuánto margen queda contra el corte de 1000
-- filas de PostgREST, medido en vez de estimado.
--
-- Por qué existe
-- --------------
-- PostgREST corta toda respuesta en `db-max-rows` (1000) y devuelve **HTTP 200** con las
-- primeras 1000. No hay error, no hay log, no hay nada. El `limit=` de la URL sólo puede
-- achicar, nunca agrandar, así que un `limit=20000` no protege de nada — sólo da la sensación
-- de que sí.
--
-- El 15/09 eso dejó a los operarios sin poder pickear: `PPP_Web_Base` cruzó las 1000 filas el
-- 14/09 (976 → 1097) y, como las filas vienen ordenadas, lo que se perdió fue lo MÁS NUEVO —
-- justo los pedidos que se estaban armando. E25A «sin cajas disponibles», D71A sin códigos, y
-- E01G armada con códigos que durante el picking nunca se vieron (hubo que desarmarla entera).
--
-- Luis, el mismo día: *"un centinela que grite y nadie escuche no sirve, hay que anticiparse"*.
-- Por eso esto NO es una alerta: es una regla que se mira antes, junto con el test
-- `tests/lecturas-paginadas.cjs`, que es el que de verdad impide que entre una lectura nueva
-- sin paginar. Esta vista responde la otra mitad: **a cuántas filas del corte estamos**.
--
-- Cómo se usa
-- -----------
--   select * from public.gv_lecturas_al_limite where estado <> 'ok';
--
-- Lo que aparezca con `ATENCION` todavía no rompió nada, pero le quedan menos de 300 filas de
-- margen: a ritmo normal son semanas. Lo que aparezca como `paginada obligatoria` YA pasó el
-- corte, así que cualquier lectura suya sin `supaFetchAll` está devolviendo datos incompletos
-- ahora mismo y en silencio.
--
-- Al agregar una tabla que crece, sumarla acá Y a `RELACIONES_GRANDES` del test.

create or replace view public.gv_lecturas_al_limite as
with medidas as (
  select 'Movimientos_Stock'::text rel, count(*)::bigint n from public."Movimientos_Stock"
  union all select 'Registros_Produccion_Virgilio', count(*) from public."Registros_Produccion_Virgilio"
  union all select 'Entregas_Virgilio', count(*) from public."Entregas_Virgilio"
  union all select 'gv_ppp_np_items', count(*) from public.gv_ppp_np_items
  union all select 'gv_ppp_base_pedidos', count(*) from public.gv_ppp_base_pedidos
  union all select 'gv_venta_mensual_cliente', count(*) from public.gv_venta_mensual_cliente
  union all select 'gv_ppp_entregados_meta', count(*) from public.gv_ppp_entregados_meta
  union all select 'vista_historial_entregas', count(*) from public.vista_historial_entregas
  union all select 'PPP_Web_Base', count(*) from public."PPP_Web_Base"
  union all select 'Facturacion_NP', count(*) from public."Facturacion_NP"
  union all select 'GV_Geo_Cliente', count(*) from public."GV_Geo_Cliente"
  union all select 'PPP_Web_Programacion', count(*) from public."PPP_Web_Programacion"
  union all select 'gv_ppp_programacion_diaria', count(*) from public.gv_ppp_programacion_diaria
  union all select 'vista_faltantes_sin_completar', count(*) from public.vista_faltantes_sin_completar
  union all select 'GV_Tandas_Auto_Log', count(*) from public."GV_Tandas_Auto_Log"
  union all select 'vista_nombres_articulos', count(*) from public.vista_nombres_articulos
  union all select 'vista_uxb_articulo', count(*) from public.vista_uxb_articulo
  union all select 'vista_marca_articulo', count(*) from public.vista_marca_articulo
  union all select 'vista_saldos_stock', count(*) from public.vista_saldos_stock
)
select rel relacion, n filas, 1000 - n margen,
       case when n >= 1000 then 'paginada obligatoria (ya pasa el corte)'
            when n >= 700  then 'ATENCION: a menos de 300 filas del corte'
            else 'ok' end estado
  from medidas order by n desc;

alter view public.gv_lecturas_al_limite set (security_invoker = true);
grant select on public.gv_lecturas_al_limite to anon, authenticated;

-- Foto al aplicarlo (15/09): 11 relaciones YA pasadas — Movimientos_Stock 61.349,
-- Registros_Produccion_Virgilio 32.135, Entregas_Virgilio 11.185, gv_ppp_np_items 10.963,
-- gv_ppp_base_pedidos 9.664, gv_venta_mensual_cliente 9.174, gv_ppp_entregados_meta 2.897,
-- vista_historial_entregas 1.542, PPP_Web_Base 1.308, Facturacion_NP 1.265, GV_Geo_Cliente
-- 1.017 (ésta estaba mordiendo sin que nadie lo supiera) — y 2 en ATENCION:
-- vista_faltantes_sin_completar 718 y GV_Tandas_Auto_Log 705.
--
-- Rollback:  drop view public.gv_lecturas_al_limite;
