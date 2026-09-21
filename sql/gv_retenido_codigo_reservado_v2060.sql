-- v20.60 — EL CODIGO DE UN PEDIDO RETENIDO QUEDA RESERVADO
--
-- Luis, 2026-09-21: "el problema si vuelve con el codigo viejo es si se pisa con algun pedido que
-- haya quedado dentro de la tanda con ese codigo y haya quilombo (como ya hubo). Verifica que no pase."
--
-- Medido ese dia, y el riesgo era real: `GV_PPP_Web_Retenido.tanda_previa` NO estaba entre las 11
-- fuentes de `gv_tandas_codigos_usados_sync()`, la memoria que desde la v19.98 impide que un codigo
-- de tanda se recicle. Al sacar el ultimo pedido de una tanda, su codigo desaparece de todas las
-- tablas vivas y vuelve a la bolsa de codigos libres — aunque haya un pedido esperando para volver
-- ahi. E50A, E26B y E52A (vaciadas el 18/09 13:14-13:18) estaban las tres libres:
--
--   codigo | en la memoria | prog web | prog isis | stock | eventos
--   E50A   |      no       |    0     |     0     |   0   |    0
--   E26B   |      no       |    0     |     0     |   0   |    0
--   E52A   |      no       |    0     |     0     |   0   |    0
--   D69H   |      si       |    2     |     0     |   3   |    6
--
-- O sea: «+ Tanda nueva» o el armador automatico podian darle E50A a un pedido cualquiera, y
-- despues el retenido volvia a E50A y se metia ADENTRO de esa tanda ajena. El guard de la v20.56
-- no lo tapaba: con el codigo tomado por otra tanda, `tanda_estado` daba 'sin empezar', que es uno
-- de los dos estados que dejan volver.
--
-- La reserva es VIVA, no va a la memoria permanente y por una razon: si el codigo entrara a
-- `GV_Tandas_Codigos_Usados` con el pedido todavia esperando, `gv_ppp_web_codigo_tomado` daria true
-- para su propio dueño y el pedido no podria volver NUNCA a su tanda. Por eso son dos preguntas
-- distintas y ahora hay una funcion para cada una:
--
--   gv_ppp_web_codigo_tomado(cod)              -> "¿este codigo se uso alguna vez?"  (el GENERADOR)
--   gv_ppp_web_codigo_vivo(cod, emp, order_id) -> "¿hay algo VIVO adentro que no sea mio?" (el RETORNO)
--
-- Y la memoria igual se entera: el sync suma la fuente 'retenido', asi que si el pedido termina en
-- una tanda nueva y su reserva se borra, el codigo ya quedo quemado y no vuelve a la bolsa.

-- 1) LA PREGUNTA DEL RETORNO: ¿hay algo vivo adentro de ese codigo que no sea mi propia reserva?
create or replace function public.gv_ppp_web_codigo_vivo(
  p_codigo text, p_empresa text default null, p_order_id bigint default null)
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $$
  select exists (select 1 from public."PPP_Web_Programacion" w
                  where upper(btrim(coalesce(w.tanda, ''))) = upper(btrim(p_codigo)))
      or exists (select 1 from public."GV_PPP_Programacion_Diaria" d
                  where upper(btrim(coalesce(d.tanda, ''))) = upper(btrim(p_codigo)))
      or exists (select 1 from public."PPP_Web_Tandas" t
                  where upper(btrim(t.codigo)) = upper(btrim(p_codigo)) and t.estado <> 'descartada')
      or exists (select 1 from public."GV_PPP_Prog_Override" o
                  where upper(btrim(coalesce(o.tanda, ''))) = upper(btrim(p_codigo)))
      -- ⚠ sin coalesce: asi entra por el indice de `ref` (0,1 ms). Con coalesce son 49 ms de seq scan.
      or exists (select 1 from public."Movimientos_Stock" m
                  where upper(btrim(m.ref)) = upper(btrim(p_codigo))
                    and m.tipo in ('picking', 'separado', 'facturado'))
      -- la reserva de OTRO pedido retenido tambien ocupa el codigo
      or exists (select 1 from public."GV_PPP_Web_Retenido" t
                  where upper(btrim(t.tanda_previa)) = upper(btrim(p_codigo))
                    and (p_empresa is null or p_order_id is null
                         or t.empresa <> lower(btrim(p_empresa)) or t.order_id <> p_order_id));
$$;

grant execute on function public.gv_ppp_web_codigo_vivo(text, text, bigint)
  to anon, authenticated, service_role;

-- 2) LA PREGUNTA DEL GENERADOR: se le suma la reserva viva, para que ningun codigo con un pedido
--    esperando salga a la bolsa. (v20.60 — el resto queda tal cual estaba.)
create or replace function public.gv_ppp_web_codigo_tomado(p_codigo text)
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $$
  -- v19.69 (problema 407): un código que ya no figura en ninguna programación pero TIENE stock del
  -- pipeline sigue estando tomado. Si se recicla, los movimientos de la tanda vieja quedan bajo el
  -- mismo `ref` que los de la nueva: el índice `mov_stock_pipeline_dedup` frena el renombre
  -- («duplicate key») o, peor, la fusión mezcla cajas de dos tandas de épocas distintas.
  --
  -- v19.98 (Thomas, 18/09) — UN CÓDIGO DE TANDA NO SE RECICLA NUNCA MÁS.
  -- `GV_Tandas_Codigos_Usados` es la memoria que no se borra; la llena `gv_tandas_codigos_usados_sync()`
  -- (cron `gv-tandas-codigos-usados`, cada 10 min) desde las 12 tablas donde un código deja rastro.
  --
  -- v20.60 (Luis, 21/09) — y la RESERVA de un pedido retenido cuenta como uso. Al sacar el ultimo
  -- pedido de una tanda el codigo se vacia de todas las tablas vivas, y sin esta linea volvia a la
  -- bolsa mientras su dueño lo esperaba: otra tanda se lo llevaba y el retenido caia adentro.
  select exists (select 1 from public."GV_Tandas_Codigos_Usados" where codigo = upper(btrim(p_codigo)))
      or exists (select 1 from public."GV_PPP_Web_Retenido" t
                  where upper(btrim(t.tanda_previa)) = upper(btrim(p_codigo)))
      or exists (select 1 from public."GV_PPP_Programacion_Diaria" where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Programacion"    where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Tandas"          where codigo = p_codigo and estado <> 'descartada')
      or exists (select 1 from public."GV_PPP_Prog_Override"    where tanda = p_codigo)
      or exists (select 1 from public."Movimientos_Stock" m
                  where upper(btrim(m.ref)) = upper(btrim(p_codigo))
                    and m.tipo in ('picking', 'separado', 'facturado'));
$$;

-- 3) LA MEMORIA: 12.ª fuente. Asi el codigo queda quemado aunque despues el pedido se vaya a una
--    tanda nueva y su reserva se borre.
create or replace function public.gv_tandas_codigos_usados_sync(p_desde interval default null::interval)
returns integer language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_n int; v_d timestamptz := case when p_desde is null then '-infinity'::timestamptz else now() - p_desde end;
begin
  insert into public."GV_Tandas_Codigos_Usados" (codigo, fuente)
  select cod, fuente from (
    select upper(btrim(texto)) cod, 'evento' fuente from public."Registros_Produccion_Virgilio"
      where opcion in ('EP','TP','AP','TAP','PUB','APX','EPX') and ts_cliente >= v_d
    union all select upper(btrim(tanda)), 'entregas'   from public."Entregas_Virgilio"          where creado >= v_d
    union all select upper(btrim(tanda)), 'lock'       from public."GV_Tandas_Lock"             where ts >= v_d
    union all select upper(btrim(tanda)), 'facturacion' from public."Facturacion_NP"
    union all select upper(btrim(tanda)), 'lio'        from public."Etiquetas_Lio"
    union all select upper(btrim(tanda)), 'anulada'    from public."GV_Tanda_Anulada"
    union all select upper(btrim(tanda)), 'prog_web'   from public."PPP_Web_Programacion"
    union all select upper(btrim(tanda)), 'prog_isis'  from public."GV_PPP_Programacion_Diaria"
    union all select upper(btrim(tanda)), 'override'   from public."GV_PPP_Prog_Override"
    union all select upper(btrim(codigo)),'tanda_web'  from public."PPP_Web_Tandas"
    -- v20.60: la tanda de la que se saco un pedido retenido. Sin esto el codigo se vaciaba de todas
    -- las tablas vivas y volvia a la bolsa mientras su dueño lo esperaba (E50A, E26B, E52A, 18/09).
    union all select upper(btrim(tanda_previa)), 'retenido' from public."GV_PPP_Web_Retenido"
    union all select upper(btrim(ref)),   'stock'      from public."Movimientos_Stock"
      where tipo in ('picking','separado','facturado')
  ) z
  where cod ~ '^[A-Z]+[0-9]+[A-Z]+$'
  on conflict (codigo) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- 4) LA VISTA: el estado de la tanda de origen se mide con lo VIVO, no con la memoria. Si preguntara
--    por la memoria, el codigo que la v20.60 acaba de reservar bloquearia a su propio dueño.
create or replace view public.gv_ppp_web_retenido as
 SELECT t.empresa,
    t.order_id,
    t.np_idx,
    t.np,
    t.tanda_previa,
    t.fecha_previa,
    COALESCE(e.pick, false) AS ya_pickeada,
    COALESCE(e.arm, false) AS ya_armada,
    t.motivo,
    t.por,
    t.creado_at,
        CASE
            WHEN t.np IS NOT NULL THEN gv_ppp_web_np_label(t.empresa, t.np, t.np_idx)
            ELSE NULL::text
        END AS np_label,
    COALESCE(v.nps, 0::bigint) > 0 AS tanda_viva,
    v.fecha AS tanda_fecha,
    COALESCE(v.nps, 0::bigint) AS tanda_nps,
        CASE
            WHEN s.n > 0 THEN 'salio'::text
            WHEN f.n > 0 THEN 'facturada'::text
            WHEN COALESCE(e.arm, false) THEN 'armada'::text
            WHEN COALESCE(e.pick, false) THEN 'pickeada'::text
            WHEN COALESCE(v.nps, 0::bigint) > 0 THEN 'sin empezar'::text
            WHEN gv_ppp_web_codigo_vivo(t.tanda_previa, t.empresa, t.order_id) THEN 'codigo tomado'::text
            ELSE 'no existe'::text
        END AS tanda_estado
   FROM "GV_PPP_Web_Retenido" t
     LEFT JOIN LATERAL ( SELECT bool_or(r.opcion = ANY (ARRAY['TP'::text, 'EP'::text])) AS pick,
            bool_or(r.opcion = 'TAP'::text) AS arm
           FROM "Registros_Produccion_Virgilio" r
          WHERE upper(btrim(r.texto)) = upper(btrim(t.tanda_previa)) AND (r.opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'AP'::text, 'TAP'::text])) AND (COALESCE(btrim(r.legajo), ''::text) <> ALL (ARRAY['0'::text, '1'::text]))) e ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS nps,
            min(w.fecha_entrega) AS fecha
           FROM "PPP_Web_Programacion" w
          WHERE upper(btrim(COALESCE(w.tanda, ''::text))) = upper(btrim(t.tanda_previa))) v ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS n
           FROM "Facturacion_NP" f2
          WHERE upper(btrim(COALESCE(f2.tanda, ''::text))) = upper(btrim(t.tanda_previa))) f ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS n
           FROM "Registros_Produccion_Virgilio" r
          WHERE upper(btrim(split_part(r.texto, '|'::text, 1))) = upper(btrim(t.tanda_previa)) AND (r.opcion = ANY (ARRAY['CCN'::text, 'CRN'::text])) AND (COALESCE(btrim(r.legajo), ''::text) <> ALL (ARRAY['0'::text, '1'::text]))) s ON true;

-- ⚠ CREATE OR REPLACE VIEW sin WITH (...) borra las reloptions: sin esta linea la vista corre como
--    postgres y saltea la RLS.
alter view public.gv_ppp_web_retenido set (security_invoker = true);

-- 5) LOS CENTINELAS. Las tres reglas se pierden solas si alguien hace un CREATE OR REPLACE
--    partiendo de una copia vieja (es lo que paso con trg_normalizar_empresa_stock, problema 390).
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_tandas_codigos_usados_sync','funcion','GV_PPP_Web_Retenido',
  'La tanda de la que se saco un pedido retenido cuenta como codigo usado. Sin esta fuente el codigo se vacia de todas las tablas vivas y vuelve a la bolsa mientras su dueño lo espera: otra tanda se lo lleva y el retenido cae adentro.',
  'Luis','v20.60'),
 ('gv_ppp_web_codigo_tomado','funcion','GV_PPP_Web_Retenido',
  'La reserva VIVA de un pedido retenido ocupa el codigo aunque la memoria todavia no lo tenga. Es lo que impide que el generador de tandas nuevas se lo lleve.',
  'Luis','v20.60'),
 ('gv_ppp_web_retenido','vista','gv_ppp_web_codigo_vivo',
  'El estado de la tanda de origen se mide con lo VIVO, no con la memoria de codigos usados: preguntando por la memoria, el codigo que la propia reserva quemo bloquearia a su dueño y el pedido no podria volver nunca.',
  'Luis','v20.60');

-- 6) y se corre el sync una vez, para que los 3 codigos que ya estaban sueltos entren a la memoria.
select public.gv_tandas_codigos_usados_sync();

-- ── CHEQUEOS ─────────────────────────────────────────────────────────────────────────────────
-- ninguna regla perdida
--   select * from public.gv_reglas_perdidas;                       -- vacia = todo bien
-- el codigo reservado NO sale de la bolsa, pero su dueño puede volver
--   select np_label, tanda_previa, tanda_estado,
--          public.gv_ppp_web_codigo_tomado(tanda_previa)                 as tomado_generador,
--          public.gv_ppp_web_codigo_vivo(tanda_previa, empresa, order_id) as vivo_ajeno
--     from public.gv_ppp_web_retenido order by np_label;
--   -- medido el 21/09: E50A/E26B/E52A -> tomado_generador=true, vivo_ajeno=false, estado 'no existe'
-- y la reserva sola alcanza, sin la memoria (probado en transaccion abortada):
--   do $$ declare a boolean; begin
--     delete from public."GV_Tandas_Codigos_Usados" where codigo = 'E50A';
--     select public.gv_ppp_web_codigo_tomado('E50A') into a;
--     raise exception 'E50A sin memoria = %', a; end $$;   -- tiene que dar t
--
-- ⚠ LO QUE QUEDA AFUERA A PROPOSITO: si una tanda ajena llegara igual a ocupar el codigo (hoy
--    solo se puede escribiendo la tabla a mano: el generador, `gv_ppp_tanda_renombrar` y
--    `ppp_web_armar_tandas` pasan todos por `gv_ppp_web_codigo_tomado`), la vista diria
--    'sin empezar' y el pedido volveria adentro de esa tanda. No se cerro porque los dos chequeos
--    posibles dan falsos positivos sobre tandas legitimas: la fecha cambia cuando se reprograma, y
--    la tanda NO es de un solo cliente (medido el 21/09: 20 de 77 tandas web tienen mas de uno).
