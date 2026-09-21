-- v20.83 — El QUINTO que elige fecha, y el armado anulado que seguia diciendo "armada".
--
-- Dos cosas que salieron del mismo pedido de Luis (21/09): *"parti la D69H si no es ningun
-- riesgo, queda programado para armado y entrega (martes no)"*. Las dos son la misma clase de
-- error: un dato viejo que sigue mandando.

-- ---------------------------------------------------------------------------------------
-- 1) EL QUINTO QUE ELIGE FECHA
-- ---------------------------------------------------------------------------------------
-- La v20.64 tapo los CUATRO que **calculan** el dia (gv_ppp_web_dia_camion,
-- gv_ppp_web_proximo_dia_con_cupo, gv_ppp_web_dia_minimo, gv_web_retiro_pactado) y dejo
-- afuera este, que **no calcula: copia** el dia que el cliente ya tiene.
--
-- Medido: el martes 22 se cerro a las 13:38:37 y **la corrida del armador de las 14:30:13
-- igual creo E12H (LK 0193, Distribuidora Pezzali, Zona 3) para ese mismo dia**. Entro por
-- los pases (a1) y (a2) de gv_ppp_web_armar_pendientes, que son los unicos que eligen la
-- fecha con gv_ppp_web_dia_cliente.
--
-- ⚠ Al tocar el armado, los que eligen fecha son CINCO, no cuatro. Y este no se encuentra
-- buscando "proximo_dia" ni "dia_camion": se encuentra buscando quien le pasa una fecha a
-- ppp_web_armar_tandas.

create or replace function public.gv_ppp_web_dia_cliente(p_empresa text, p_cod text, p_desde date, p_hasta date)
 returns date language sql stable set search_path to 'public'
as $function$
  select min(dia) from (
    select w.fecha_entrega as dia
      from public."PPP_Web_Programacion" w
     where w.empresa = p_empresa
       and btrim(coalesce(w.cod_cliente, '')) = btrim(coalesce(p_cod, ''))
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and w.fecha_entrega between p_desde and p_hasta
    union all
    select left(btrim(i.fecha_entrega::text), 10)::date
      from public.gv_ppp_programacion_diaria i
     where btrim(coalesce(i.cod, '')) = btrim(coalesce(p_cod, ''))
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and coalesce(i.tipo, '') <> 'KRIKOS'
       and coalesce(i.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date between p_desde and p_hasta
       and ((p_empresa = 'lk'   and btrim(i.np) ~ '^9')
         or (p_empresa = 'chef' and btrim(i.np) ~ '^4'))
  ) d
  where public.gv_es_dia_con_reparto(dia);   -- v20.83
$function$;

-- ---------------------------------------------------------------------------------------
-- 2) UN ARMADO ANULADO NO ES UN ARMADO
-- ---------------------------------------------------------------------------------------
-- gv_tanda_trabajo_hecho decidia "esta tanda tiene el armado hecho" con la SOLA existencia de
-- una fila en Entregas_Virgilio. Los eventos AP/TAP anulados ya no contaban (se renombran a
-- APX/TAPX), pero la fila de Entregas quedaba para siempre.
--
-- Caso D69H: su unica fila de Entregas (id 13028) es de **LK 0058**, un pedido que ya no esta
-- en la tanda, y su TAP se anulo en la v20.70. Con la pila en CERO, el guard de mover NP
-- (gv_np_mover_guard) seguia frenando la particion que pidio Luis con el cartel *"avisa a
-- sistemas"*.
--
-- ⚠ El criterio es la FECHA, no un interruptor: la fila cuenta si es POSTERIOR a la ultima
-- anulacion del armado de esa tanda. Si manana se vuelve a armar, la fila nueva es posterior
-- y vuelve a contar sola. Medido sobre las 1.059 tandas con filas de Entregas: cambia UNA,
-- D69H, que es justo la que se anulo.

create or replace function public.gv_tanda_trabajo_hecho(p_tanda text)
 returns table(tanda text, tiene_picking boolean, tiene_armado boolean, cajas numeric)
 language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
  with t as (select nullif(upper(btrim(coalesce(p_tanda,''))),'') tanda)
  select t.tanda,
    t.tanda is not null and (
      exists (select 1 from public."Movimientos_Stock" m
               where upper(btrim(m.ref)) = t.tanda and m.tipo = 'picking' and m.delta <> 0)
      or exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where r.opcion in ('EP','TP') and upper(btrim(r.texto)) = t.tanda
                    and not public.es_legajo_test(r.legajo))),
    t.tanda is not null and (
      exists (select 1 from public."Entregas_Virgilio" e
               where upper(btrim(e.tanda)) = t.tanda
                 and coalesce(e.creado, 'infinity'::timestamptz) >
                     coalesce((select max(a.anulado_en) from public."GV_Tanda_Anulada" a
                                where upper(btrim(a.tanda)) = t.tanda and a.fase = 'armado'),
                              '-infinity'::timestamptz))
      or exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where r.opcion in ('AP','TAP') and upper(btrim(r.texto)) = t.tanda
                    and not public.es_legajo_test(r.legajo))),
    coalesce((select sum(m.delta) from public."Movimientos_Stock" m
               where upper(btrim(m.ref)) = t.tanda and m.tipo = 'picking'
                 and m.deposito = 'separar_pedidos'), 0)
  from t;
$function$;

-- ---------------------------------------------------------------------------------------
-- 3) Lo que se movio con esto (backup en
--    zz_backups."GV_Backup_PPPWebProg_D69H_E12H_20260921", 3 filas)
-- ---------------------------------------------------------------------------------------
--   E12H  LK 0193  Pezzali   Zona 3 - CABA Oeste   22/09 -> 23/09  (el martes no sale camion)
--   D69H  LK 0070  Valimar   Zona 6 - GBA Norte    -> tanda nueva E70A, 23/09
--   D69H  LK 0083  Lin Chuang Zona 2 - CABA Centro  queda en D69H, 23/09
-- Ningun movimiento de stock: las dos tandas tenian la pila en cero.
--
-- Chequeo (los seis tienen que dar 0):
--   select * from public.gv_ppp_tanda_camion_mezclado;
--   select * from public.gv_ppp_tanda_dos_dias;
--   select * from public.gv_ppp_cliente_dos_dias;
--   select * from public.gv_ppp_super_mezclado;
--   select * from public.gv_tanda_armada_sin_armado;
--   select * from public.gv_dia_sin_reparto_ocupado;
