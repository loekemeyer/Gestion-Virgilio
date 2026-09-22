-- ============================================================================
-- v20.95 (Thomas, 2026-09-22) — EL ARMADO AUTOMÁTICO NO PROGRAMA CUARENTENA
--                                NI CLIENTE NUEVO SIN APROBACIÓN HUMANA.
--
-- Thomas, textual: "armado automatico no deberia programar automaticamente
-- clientes nuevos ni clientes en cuarentena que no hayan sido aprobados por un
-- humano, nunca. Si ya fueron aprobados y se atrasa la entrega o algo asi, si se
-- puede reprogramar automaticamente, pero primero aprobado por humano."
--
-- QUÉ ESTABA PASANDO (medido el 22/09):
--   Ningún objeto del armado miraba la cuarentena. Barrido sobre pg_proc:
--     gv_ppp_web_armar_pendientes  -> 0 apariciones de 'cuarentena'
--     ppp_web_armar_tandas         -> 0
--     gv_ppp_web_juntar_clientes   -> 0
--     gv_pedidos_web_excluidos     -> 0
--   La retención vivía SOLO en el front (el chip de A Programar). El armador sólo
--   saltea lo diferido (a0), lo retenido A MANO en GV_PPP_Web_Retenido (a0b) y lo
--   cancelado (a0c): alcanzaba con que el pedido no tuviera fila en esa tabla para
--   que el cron lo programara igual.
--
--   Dos casos reales, los dos SIN una sola fila en GV_Cuarentena_Liberados:
--     · LK 0094/0095/0096 (order 1448, Silvano Lucas Martin 4282) — CLIENTE NUEVO,
--       pipeline en etapa 'ingresado'. Vivi lo devolvió a cuarentena el 18/09
--       ("No pago") y aun así quedó en E72A para el 28/09.
--     · CH 0004 (order 218, Ierakuin Srl 1665) — DEUDA $2.062.528,58. Vivi lo
--       devolvió dos veces (15/09 y 18/09, "No pago todavia") y quedó en E71A
--       para el 28/09.
--
-- QUÉ ES "APROBADO POR HUMANO": una fila en GV_Cuarentena_Liberados que levante
--   ESE motivo. La escriben el botón de Cuarentena y el checkmark ✅ del pipeline
--   de Clientes nuevos (los dos vía gv_cuarentena_liberar). Una vez aprobado, el
--   pedido vuelve a los pases normales y se reprograma solo como cualquier otro:
--   es la segunda mitad de la regla, y está probada abajo.
--
-- ⚠ EL CRITERIO DE QUÉ RETIENE NO SE DUPLICA: lo da gv_cuarentena_marcar_calc, la
--   MISMA función que usa la pantalla, con todas sus excepciones vivas
--   (gv_excepcion_cuarentena, reposición chica v19.44, mismo pedido v20.52 y la
--   resta de motivos liberados v20.86). Si mañana cambia una regla de cuarentena,
--   el armado la hereda sola. Medido: Suppa (1482, deuda $836.909) NO retiene,
--   porque su deuda es la factura de otra NP del MISMO pedido — y eso es correcto.
--
-- ⚠ FAIL-CLOSED, al revés del patrón habitual del repo. En la v19.44 la regla era
--   "lo nuevo va en su propio catch para que, si falla, no se lleve puesto lo que
--   funciona". Acá NO: si la cuarentena no se puede evaluar (sin permiso, o la
--   marcación explota), gv_cuarentena_retiene_lote devuelve TODO el lote y no se
--   programa nada. Un armado que no corre se ve (GV_PPP_Web_Armado_Log y
--   gv_ppp_web_armado_salud); un pedido con deuda que sale en el camión, no.
--   Ojo con el guard de gv_cuarentena_marcar_calc: su WHERE termina en
--   (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()), así que sin
--   permiso devuelve CERO FILAS — que leído como "no hay retenidos" sería
--   exactamente el bug al revés. Por eso el chequeo se hace ANTES, afuera.
--
-- ⚠ Y EL PASE VA DESPUÉS DEL TOPE (a00), no antes: así el guard evalúa a lo sumo
--   `armado_tope_pedidos` (hoy 120) y no los 172 que entran. Costo medido del
--   guard: 1.041 ms sobre 218 pedidos, de los cuales 766 ms son
--   gv_cuarentena_mismo_pedido_seguro. En la corrida real NO se notó, porque lo
--   que se ahorra es mayor: el armado cuesta ~43 ms por pedido y los retenidos
--   dejaron de procesarse. LK, mismas ~170 filas de entrada:
--     antes  (09:40 / 09:45 / 09:50): 4.515 / 5.499 / 4.951 ms
--     después (10:00 / 10:05):        4.327 / 4.306 ms
--
-- ⚠ El alias del subselect se llama `_cq_r` y NO `r`: gv_ppp_web_armar_pendientes
--   declara `r record`, así que un alias `r` la vuelve ambigua y la función explota
--   EN EJECUCIÓN con 42702, no al crearse (es el pozo de la v19.56, problema 400).
--   Pasó en el primer intento y lo cazó la prueba de abajo, no la lectura.
--
-- Chequeos:
--   select * from public.gv_reglas_perdidas;            -- vacía = las 2 reglas siguen
--   select * from public.gv_cuarentena_ya_programado(); -- lo retenido que igual tiene tanda
--   select * from public.gv_ppp_web_armado_salud;       -- que el armado siga corriendo
-- ============================================================================

-- ── 1) El guard ─────────────────────────────────────────────────────────────
create or replace function public.gv_cuarentena_retiene_lote(p_empresa text, p_filas jsonb)
returns table(order_id bigint)
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
-- v20.95 (Thomas, 2026-09-22) — QUIEN NO PUEDE PROGRAMARSE SOLO.
--   Devuelve los order_id del lote que estan retenidos por Cuarentena o por Cliente nuevo y
--   NO tienen aprobacion humana (fila en GV_Cuarentena_Liberados que levante ese motivo).
--   El criterio de que retiene NO se escribe aca: lo da gv_cuarentena_marcar_calc, la misma
--   funcion que usa la pantalla. Si se cambia una regla de cuarentena, el armado la hereda.
-- ⚠ FAIL-CLOSED, a proposito y al reves del patron habitual: si no se puede evaluar (sin
--   permiso, o la marcacion explota) devuelve TODO el lote, o sea que no se programa nada.
--   Un armado que no corre se ve (GV_PPP_Web_Armado_Log, gv_ppp_web_armado_salud); un pedido
--   con deuda que sale en el camion, no.
declare
  v_ped jsonb;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    return query select distinct (x->>'order_id')::bigint
      from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) x
     where coalesce(x->>'order_id','') ~ '^[0-9]+$';
    return;
  end if;

  select coalesce(jsonb_agg(distinct jsonb_build_object(
           'order_id', x->>'order_id',
           'empresa',  lower(coalesce(p_empresa,'lk')),
           'cod',      btrim(x->>'cod'),
           'np',       nullif(btrim(coalesce(x->>'np','')),''),
           'razon_social', nullif(btrim(coalesce(x->>'razon_social','')),''))), '[]'::jsonb)
    into v_ped
    from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) x
   where coalesce(x->>'order_id','') ~ '^[0-9]+$'
     and nullif(btrim(coalesce(x->>'cod','')), '') is not null;

  return query
    select distinct m.order_id::bigint
      from public.gv_cuarentena_marcar_calc(v_ped) m
     where m.order_id ~ '^[0-9]+$';
exception when others then
  raise warning 'gv_cuarentena_retiene_lote fallo (%): se retiene TODO el lote', sqlerrm;
  return query select distinct (x->>'order_id')::bigint
    from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) x
   where coalesce(x->>'order_id','') ~ '^[0-9]+$';
end $fn$;

revoke execute on function public.gv_cuarentena_retiene_lote(text, jsonb) from public, anon;
grant  execute on function public.gv_cuarentena_retiene_lote(text, jsonb) to authenticated, service_role;

-- ── 2) El pase (a0d) dentro del armador ─────────────────────────────────────
-- Se aplica SOBRE LA DEFINICIÓN VIVA (varias sesiones tocan esta función), es
-- idempotente, y FALLA con un raise si el texto no matchea en vez de escribir una
-- versión vieja encima.
do $outer$
declare
  v_def text;
  v_new text;
  v_anc_dec constant text := '  v_t0         timestamptz := clock_timestamp();';
  v_anc_a   constant text := '  -- (a) forzados con fecha (Chef de una razon social que entro por LK ese dia)';
  v_blk text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'gv_ppp_web_armar_pendientes';
  if v_def is null then raise exception 'no encuentro gv_ppp_web_armar_pendientes'; end if;

  if position('(a0d)' in v_def) > 0 then
    raise notice 'ya tiene el pase (a0d): no se toca';
    return;
  end if;

  if position(v_anc_dec in v_def) = 0 then raise exception 'no matchea el ancla del declare'; end if;
  if position(v_anc_a   in v_def) = 0 then raise exception 'no matchea el ancla del pase (a)'; end if;

  v_blk := $blk$  -- (a0d) v20.95 (Thomas, 2026-09-22) -- CUARENTENA Y CLIENTE NUEVO: NUNCA SE PROGRAMAN SOLOS.
  --   Textual: "armado automatico no deberia programar automaticamente clientes nuevos ni
  --   clientes en cuarentena que no hayan sido aprobados por un humano, nunca. Si ya fueron
  --   aprobados y se atrasa la entrega o algo asi, si se puede reprogramar automaticamente,
  --   pero primero aprobado por humano."
  --   Hasta hoy NINGUN objeto del armado miraba la cuarentena (medido: ni armar_pendientes, ni
  --   ppp_web_armar_tandas, ni juntar_clientes, ni gv_pedidos_web_excluidos nombran la palabra):
  --   la retencion vivia SOLO en el front, en el chip de A Programar. Alcanzaba con que el
  --   pedido no tuviera fila en GV_PPP_Web_Retenido para que el cron lo programara igual. Asi
  --   salieron solos LK 1448 (Silvano, cliente nuevo sin aprobar -> E72A del 28/09) y CH 0004
  --   (Ierakuin, deuda 2.062.529 -> E71A del 28/09), los dos sin una fila en Liberados.
  --   APROBADO POR HUMANO = fila en GV_Cuarentena_Liberados que levante ESE motivo. La escriben
  --   el boton de Cuarentena y el checkmark del pipeline de Clientes nuevos. Una vez aprobado,
  --   el pedido vuelve a los pases normales y se reprograma solo como cualquier otro.
  --   ⚠ El criterio de QUE retiene no se duplica aca: lo da gv_cuarentena_marcar_calc, la misma
  --   que usa la pantalla, con sus exenciones (gv_excepcion_cuarentena, reposicion chica v19.44,
  --   mismo pedido v20.52). Si manana cambia una regla de cuarentena, el armado la hereda sola.
  --   ⚠ Y gv_cuarentena_retiene_lote es FAIL-CLOSED: si no se puede evaluar, retiene todo.
  v_ret := coalesce((select array_agg(distinct _cq_r.order_id::text)
                       from public.gv_cuarentena_retiene_lote(p_empresa, p_filas) _cq_r), '{}');
  if coalesce(array_length(v_ret, 1), 0) > 0 then
    p_filas := coalesce((
      select jsonb_agg(x)
        from jsonb_array_elements(p_filas) x
       where not ((x->>'order_id') = any (v_ret))), '[]'::jsonb);
  end if;

$blk$;

  v_new := replace(v_def, v_anc_dec, v_anc_dec || E'\n  v_ret        text[];');
  v_new := replace(v_new, v_anc_a, v_blk || v_anc_a);

  if v_new = v_def then raise exception 'el reemplazo no cambio nada'; end if;
  execute v_new;
end $outer$;

-- ── 3) Centinelas ───────────────────────────────────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_ppp_web_armar_pendientes','funcion','gv_cuarentena_retiene_lote',
  'El armado automatico NUNCA programa un pedido retenido por cuarentena o cliente nuevo sin aprobacion humana (pase a0d).','Thomas','v20.95'),
 ('gv_cuarentena_retiene_lote','funcion','se retiene TODO el lote',
  'El guard de cuarentena del armado es FAIL-CLOSED: si no se puede evaluar, retiene todo en vez de dejar pasar.','Thomas','v20.95')
on conflict do nothing;

-- ── 4) LA PRUEBA: se CORRE el armador, no se lee ────────────────────────────
-- Las dos mitades de la regla, en una transaccion que se revierte con el raise final.
--
-- (4.a) SIN aprobacion -> no se programa. Resultado medido el 22/09:
--   PRUEBA >> 2026-09-29 E74A np=1 cods={1402}
--             || con tanda: 1448:SIN TANDA, 1448:SIN TANDA, 1448:SIN TANDA, 999999901:E74A
--   (el cliente sano se armo; el cliente nuevo sin aprobar quedo afuera)
--
-- do $prueba$
-- declare v_txt text; v_filas jsonb;
-- begin
--   delete from public."GV_PPP_Web_Retenido" where empresa='lk' and order_id=1448;
--   update public."PPP_Web_Programacion" set tanda=null, fecha_entrega=null
--    where empresa='lk' and order_id=1448;
--   v_filas := jsonb_build_array(
--     jsonb_build_object('order_id','1448','np_idx',1,'np','94','cod','4282',
--       'razon_social','Silvano Lucas Martin','zona','Zona 3 - CABA Oeste','m3','0.19','lineas',18,'cajas','30'),
--     jsonb_build_object('order_id','999999901','np_idx',1,'np','9901','cod','1402',
--       'razon_social','Olimpico S.R.L.','zona','Zona 3 - CABA Oeste','m3','0.20','lineas',5,'cajas','10'));
--   select coalesce(string_agg(format('%s %s np=%s cods=%s', r_fecha, r_tanda, r_np_count, r_cods), ' | '), '(no armo nada)')
--     into v_txt from public.gv_ppp_web_armar_pendientes('lk', null, v_filas, '[]'::jsonb);
--   v_txt := v_txt || '  ||  con tanda: ' || coalesce((
--     select string_agg(w.order_id||':'||coalesce(w.tanda,'SIN TANDA'), ', ' order by w.order_id)
--       from public."PPP_Web_Programacion" w where w.order_id in (1448, 999999901)), '(ninguna)');
--   raise exception 'PRUEBA >> %', v_txt;
-- end $prueba$;
--
-- (4.b) CON aprobacion humana -> se programa solo. Resultado medido:
--   PRUEBA APROBADO >> 2026-10-02 E61E np=1  ||  1448 quedo: E61E
--
-- do $prueba2$
-- declare v_txt text; v_filas jsonb;
-- begin
--   delete from public."GV_PPP_Web_Retenido" where empresa='lk' and order_id=1448;
--   update public."PPP_Web_Programacion" set tanda=null, fecha_entrega=null
--    where empresa='lk' and order_id=1448;
--   insert into public."GV_Cuarentena_Liberados"(empresa, order_id, motivos, liberado_por, liberado_at, persona)
--   values ('lk', 1448, array['cliente_nuevo'], 'prueba@prueba', now(), 'PRUEBA');
--   v_filas := jsonb_build_array(
--     jsonb_build_object('order_id','1448','np_idx',1,'np','94','cod','4282',
--       'razon_social','Silvano Lucas Martin','zona','Zona 3 - CABA Oeste','m3','0.19','lineas',18,'cajas','30'));
--   select coalesce(string_agg(format('%s %s np=%s', r_fecha, r_tanda, r_np_count), ' | '), '(no armo nada)')
--     into v_txt from public.gv_ppp_web_armar_pendientes('lk', null, v_filas, '[]'::jsonb);
--   v_txt := v_txt || '  ||  1448 quedo: ' || coalesce((
--     select string_agg(coalesce(w.tanda,'SIN TANDA'), ', ') from public."PPP_Web_Programacion" w
--      where w.empresa='lk' and w.order_id=1448 and w.np_idx=1), '(?)');
--   raise exception 'PRUEBA APROBADO >> %', v_txt;
-- end $prueba2$;
