-- v25.94 — PENDIENTE DEL «SÍ» (gv_ppp_prog_arbol está en GV_Reglas_Centinela).
-- Pedido: "hacer que aparezca en la PPP cuando vuelve ... y vuelva a estar en la Programación
-- como Facturado pero con el badge de VOLVIÓ".
--
-- Hoy un pedido que salió y VOLVIÓ (↩ s/salida = FSS posterior a su última carga, sin CRN) queda
-- con su fecha de entrega vieja: cae en «Pedidos atrasados», no en la Programación. Con esto su
-- día pasa a ser max(fecha original, HOY): aparece en el día de hoy de la Programación (estado
-- Facturado, el badge ↩ VOLVIÓ lo pone el front) y sale de atrasados. Si se lo pasa a otro día
-- con «📅 Cambiar de día», manda ese día (es mayor que hoy). Al recargarse (CCN nuevo) deja de
-- ser «vuelto» y sigue el camino normal (En Salida → Recepción Remitos).
--
-- Las dos reglas protegidas (franja manual > cliente, NP web cancelada) NO se tocan: el parche
-- sólo agrega el CTE `_vu_volvio` y cambia el día en `dia`. Idempotente y con raise si no matchea.
-- Rollback: volver a aplicar la definición de zz_backups / la anterior sin `_vu_volvio`.

do $patch$
declare
  v_def text := pg_get_functiondef('public.gv_ppp_prog_arbol(date,date)'::regprocedure);
  v_new text;
  v_old_dia text := $o$dia as (
  -- v19.29: el día de una NP en espera es el centinela. Con eso entra en el rango sólo cuando
  -- quien pregunta llega hasta ahí (la Programación), y nunca en un rango de días reales
  -- (Pedidos atrasados, Avance del día).
  select u.*, (case when u.en_espera then public.gv_ppp_espera_fecha() else u.fe end) as fe_dia
    from uni u
   where (case when u.en_espera then public.gv_ppp_espera_fecha() else u.fe end) between p_desde and p_hasta
),$o$;
  v_new_dia text := $n$_vu_volvio as (
  -- v25.94-volvio: salió, el cliente no la recibió (↩ s/salida = FSS) y no se volvió a cargar.
  -- Vuelve a la Programación en el día de HOY (o en el que le pongan después, si es más tarde).
  select x.np
    from (select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
                 max(r.ts_cliente) filter (where r.opcion = 'FSS') as fss,
                 max(r.ts_cliente) filter (where r.opcion = 'CCN') as ccn,
                 max(r.ts_cliente) filter (where r.opcion = 'CRN') as crn
            from public."Registros_Produccion_Virgilio" r
           where r.opcion in ('FSS', 'CCN', 'CRN')
             and coalesce(btrim(r.legajo), '') not in ('0', '1')
             and btrim(coalesce(r.texto, '')) <> ''
             and r.ts_cliente >= now() - interval '60 days'
           group by 1) x
   where x.fss is not null
     and x.fss > coalesce(x.ccn, '-infinity'::timestamptz)
     and x.crn is null
),
dia as (
  -- v19.29: el día de una NP en espera es el centinela. Con eso entra en el rango sólo cuando
  -- quien pregunta llega hasta ahí (la Programación), y nunca en un rango de días reales
  -- (Pedidos atrasados, Avance del día).
  select u.*, (case when u.en_espera then public.gv_ppp_espera_fecha()
                    when vu.np is not null then greatest(u.fe, (now() at time zone 'America/Argentina/Buenos_Aires')::date)
                    else u.fe end) as fe_dia
    from uni u
    left join _vu_volvio vu on vu.np = upper(u.np)
   where (case when u.en_espera then public.gv_ppp_espera_fecha()
               when vu.np is not null then greatest(u.fe, (now() at time zone 'America/Argentina/Buenos_Aires')::date)
               else u.fe end) between p_desde and p_hasta
),$n$;
begin
  if v_def like '%v25.94-volvio%' then raise notice 'ya aplicado'; return; end if;
  if position(v_old_dia in v_def) = 0 then raise exception 'gv_ppp_prog_arbol: el CTE dia no matchea (otra sesión la cambió): no se aplica'; end if;
  v_new := replace(v_def, v_old_dia, v_new_dia);
  execute v_new;
end
$patch$;

-- Chequeo (con un pedido vuelto sin recargar tiene que salir en hoy, estado facturado):
-- select fecha, np, estado from public.gv_ppp_prog_arbol(current_date, current_date) where np = '<np>';
-- select * from public.gv_reglas_perdidas;   -- vacía
