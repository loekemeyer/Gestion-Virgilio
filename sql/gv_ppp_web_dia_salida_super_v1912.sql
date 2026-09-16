-- =============================================================================
-- gv_ppp_web_dia_salida_super_v1912.sql — v19.12 (2026-09-16)
-- Proyecto VIRGILIO (hrxfctzncixxqmpfhskv)
--
-- EL CHIP DE A PROGRAMAR LE PROMETIA "SE ARMA SOLO" A UN SUPER. Quinta puerta del
-- mismo bug de siempre: **un súper con zona NUMÉRICA**.
--
-- `gv_ppp_web_dia_salida` es el justificativo por pedido que muestra la tarjeta
-- ("🤖 se arma solo → mar 23/9", "🔒 no lo toca el automático", "🛒 súper: a mano"…).
-- Decidía "súper" mirando el TEXTO DE LA ZONA (`zona ilike 'super%'`), igual que
-- `_sin_tanda` antes de la v18.28, `_ex` / `gv_ppp_web_dia_camion` antes de la v18.60
-- y `_open` antes de la v18.87. Pero el padrón que manda es **`GV_Supers`**, y un
-- súper puede venir con zona numérica:
--
--   LK 1450 · Matiz SA · cod 4263 = **Gigot** (súper ACTIVO en GV_Supers)
--   entrega en Constitución → zona "Zona 1 - CABA Sur" (automática)
--
-- `ppp_web_armar_tandas` lo saltea con `gv_es_super` (v18.28), así que ese pedido
-- **no lo programa nadie hasta que un supervisor le pone día** — y el chip decía
-- "se arma solo para el 23/09 · en minutos". El supervisor esperaba una tanda que no
-- iba a salir: el pedido entró el 15/09 y seguía en A Programar el 16/09.
--
-- Problema auditado: 359.
--
-- CAMBIOS
--   1. el payload trae `cod` (el front lo manda desde la v19.12, `aprCargarSalida`);
--      si no viene —página vieja cacheada— se busca por (empresa, order_id) en
--      `PPP_Web_Programacion` y, si tampoco está, la función se comporta como antes.
--   2. CTE `sup`: súper = `gv_es_super(empresa, cod)`, el MISMO padrón que usa el
--      armado. Las tres ramas del CASE (r_dia / r_motivo / r_detalle) lo miran.
--      ⚠ En `r_detalle` el orden del CASE NO era el de las otras dos (la zona
--      automática se evaluaba antes que el súper), así que hacía falta insertar la
--      rama a mano: LK 1450 salía con motivo "super" y detalle "se arma sola".
--   3. `pend_auto` (el m³ pendiente con el que se decide si el intradía arma ya) deja
--      de contar los súper: el armado no los va a levantar.
--
-- VERIFICADO con la lista real de A Programar del 16/09:
--   select r_idx, r_motivo, r_detalle from gv_ppp_web_dia_salida('[
--     {"zona":"Zona 1 - CABA Sur","m3":0,    "empresa":"lk","order_id":1450,"cod":"4263"},
--     {"zona":"Super",           "m3":4.272,"empresa":"lk","order_id":1468,"cod":"1651"},
--     {"zona":"Zona 1 - CABA Sur","m3":0.171,"empresa":"lk","order_id":1470,"cod":"4069"}]'::jsonb);
--   -- 1450 -> super · "Súper (padrón GV_Supers): camión propio, lo programa el supervisor"
--   -- 1468 -> super · idem (antes ya salía bien, por zona "Super")
--   -- 1470 -> job   · "se arma sola … desde el 23/09"   (y en la corrida de las 16:05 salió: E29A)
--
-- CUBIERTO en `tests/enviar-a-programar-deshace.cjs` (el chip no puede mentir sobre
-- el automático: ahora exige que `aprCargarSalida` mande también el `cod`).
--
-- ⚠ LA LECCIÓN, otra vez (está en el CLAUDE.md): **al tocar el armado, buscar
-- `'super|retira|expo'` y preguntarse si ahí no debería ir `gv_es_super`.** Van cinco.
-- Chequeo de mezclas: `select * from public.gv_ppp_super_mezclado;` (vacía = todo bien).
--
-- ROLLBACK: los tres replaces al revés (quitar el CTE `sup`, las 3 ramas y el `cod`).
-- No toca datos: es una función de sólo lectura.
--
-- ⚠ Como en `gv_turno_entrega_oc_v1911.sql`, esto se aplicó con `DO` blocks sobre
-- `pg_get_functiondef` (parchear LO VIVO y fallar si el ancla no está) en vez de pegar
-- un CREATE que envejece. Para la definición de hoy:
--   select pg_get_functiondef('public.gv_ppp_web_dia_salida(jsonb,timestamptz)'::regprocedure);
-- =============================================================================

-- ── 1) `cod` en el parseo + CTE `sup` (súper por padrón) ─────────────────────
do $mig$
declare v_def text; v_new text; v_n int;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_dia_salida(jsonb,timestamp with time zone)'::regprocedure);
  v_new := v_def;

  if position('end as order_id
      from jsonb_array_elements(' in v_new) = 0 then raise exception 'no encontre el order_id del CTE f'; end if;
  v_new := replace(v_new, 'end as order_id
      from jsonb_array_elements(',
'end as order_id,
           /* v19.12 — el CODIGO de cliente. Hace falta para saber si es un SUPER: no se
              puede deducir de la zona (ver el CTE sup). Si el front no lo manda (pagina
              vieja cacheada) se lo busca por (empresa, order_id) en la programacion. */
           nullif(btrim(coalesce(x.v->>''cod'','''')), '''') as cod
      from jsonb_array_elements(');

  if position('with ordinality as x(v, ord)
  ),' in v_new) = 0 then raise exception 'no encontre el cierre del CTE f'; end if;
  v_new := replace(v_new, 'with ordinality as x(v, ord)
  ),',
'with ordinality as x(v, ord)
  ),
  /* v19.12 — SUPER SE DECIDE POR EL PADRON `GV_Supers`, NO POR LA ZONA (quinta puerta
     del mismo bug: v18.28 _sin_tanda, v18.60 _ex y dia_camion, v18.87 _open). Caso
     testigo: LK 1450, Matiz SA (cod 4263 = Gigot), entrega en Constitucion -> "Zona 1 -
     CABA Sur". ppp_web_armar_tandas lo saltea con gv_es_super y esta funcion le decia
     "se arma solo -> 23/09 en minutos". */
  sup as (
    select f.idx
      from f
     where f.empresa is not null
       and public.gv_es_super(f.empresa,
             coalesce(f.cod,
               (select g.cod_cliente
                  from public."PPP_Web_Programacion" g
                 where g.empresa = f.empresa and g.order_id = f.order_id
                 limit 1)))
  ),');

  select count(*) into v_n from regexp_matches(v_new,
    'f\.zona ilike ''s_per%'' or f\.zona ilike ''súper%'' or f\.zona ilike ''super%''','g');
  if v_n <> 3 then raise exception 'esperaba 3 tests de super por zona, encontre %', v_n; end if;
  v_new := replace(v_new,
    'f.zona ilike ''s_per%'' or f.zona ilike ''súper%'' or f.zona ilike ''super%''',
    '(f.zona ilike ''s_per%'' or f.zona ilike ''súper%'' or f.zona ilike ''super%''
                or exists (select 1 from sup where sup.idx = f.idx))');

  if position('where zn = any(v_auto) and not exists (select 1 from ret where ret.idx = f.idx)' in v_new) = 0
    then raise exception 'no encontre pend_auto'; end if;
  v_new := replace(v_new,
    'where zn = any(v_auto) and not exists (select 1 from ret where ret.idx = f.idx)',
    'where zn = any(v_auto) and not exists (select 1 from ret where ret.idx = f.idx)
       and not exists (select 1 from sup where sup.idx = f.idx)');

  execute v_new;
end
$mig$;

-- ── 2) en r_detalle el súper va ANTES que la zona automática ─────────────────
do $mig$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_dia_salida(jsonb,timestamp with time zone)'::regprocedure);
  if position('when f.zn = any(v_auto) then ''Zona automática' in v_def) = 0
    then raise exception 'no encontre la rama de detalle de zona automatica'; end if;
  v_new := replace(v_def, 'when f.zn = any(v_auto) then ''Zona automática',
    'when exists (select 1 from sup where sup.idx = f.idx)
             then ''Súper (padrón GV_Supers): camión propio, lo programa el supervisor''
           when f.zn = any(v_auto) then ''Zona automática');
  execute v_new;
end
$mig$;
