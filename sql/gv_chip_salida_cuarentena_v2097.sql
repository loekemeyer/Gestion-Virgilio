-- ============================================================================
-- v20.97 (Thomas, 2026-09-22) — EL CHIP "SE ARMA SOLO" MIRA LA CUARENTENA
--
-- Thomas, textual: "QUE el chip «se arma solo» mire la cuarentena y clientes nuevos por el
-- amor de dios".
--
-- SEXTA PUERTA DEL MISMO BUG. `gv_ppp_web_dia_salida` ya miraba el retenido a mano (v18.77)
-- y el súper del padrón (v19.12), pero no la cuarentena. Medido el 22/09, los tres que el
-- chip mandaba a armarse solos el jueves 1/10:
--
--   CH 0004  Ierakuin Srl (1665)        deuda      $2.062.528,58
--   LK 0201  Romagessi Antonio (2191)   deuda      $2.216.125
--   LK 0018  Bazar Monica (4045)        deuda      $1.080.583
--   LK 1465  Ramirez Santiago (4123)    SUSPENDIDO  ← apareció al probarlo
--
-- Desde la v20.95 el armador no los toca, así que el chip decía exactamente lo contrario de
-- lo que iba a pasar, y con fecha: el supervisor esperaba una tanda que no iba a salir.
--
-- ⚠ SE RESUELVE EN EL BACKEND, no marcando el chip desde el front. Son dos razones:
--   1. una sola fuente: `gv_cuarentena_retiene_lote` es la MISMA que usa el armado, así que
--      el chip no puede decir una cosa y el armador hacer otra;
--   2. el chip sigue diciendo la verdad aunque la marcación del front se caiga por timeout,
--      que es justo cuando más mentía (v20.96).
--
-- ⚠ UNA llamada POR EMPRESA, no una por fila: la función no se inlinea (`SET search_path`) y
--   por fila costaría ~300 ms cada una. Costo medido, estable con el tamaño del lote porque
--   es fijo: 1.789 ms con 5 pedidos y 1.683 ms con 40. Contra el statement_timeout de 8 s.
--
-- ⚠ `gv_cuarentena_retiene_lote` pasó a devolver también los MOTIVOS (columna agregada AL
--   FINAL: el armador lee order_id y no se entera). Hizo falta DROP + CREATE porque cambia el
--   tipo de retorno.
--
-- ⚠ Y el pozo que mordió en el primer intento: `(array_agg(c.motivos))[1]` sobre un array DE
--   ARRAYS devuelve un TEXT, no un text[] — el subíndice entra al array aplanado. El CREATE
--   sale limpio y explota AL EJECUTAR con 42883 `array_to_string(text, unknown)`. Otra vez:
--   lo cazó la prueba, no la lectura. Se desarma con unnest y se vuelve a armar.
--
-- El front acompaña con dos chips nuevos en `aprSalidaChip`:
--   🚧 retenido en cuarentena · no se arma solo
--   🆕 cliente nuevo sin aprobar · no se arma solo
--
-- Chequeo:
--   select r_idx, r_dia, r_motivo, r_detalle from public.gv_ppp_web_dia_salida(
--     jsonb_build_array(jsonb_build_object('zona','Zona 1 - CABA Sur','m3',0.6,
--       'empresa','chef','order_id',218,'cod','1665')));
--   -- r_dia null · r_motivo 'cuarentena'
-- ============================================================================

-- ── 1) el guard devuelve tambien los motivos ────────────────────────────────
drop function if exists public.gv_cuarentena_retiene_lote(text, jsonb);

create or replace function public.gv_cuarentena_retiene_lote(p_empresa text, p_filas jsonb)
returns table(order_id bigint, motivos text[])
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
-- v20.97: devuelve tambien los MOTIVOS, para que el chip de "A Programar" pueda decir si es
--   cuarentena o cliente nuevo. La columna se agrego AL FINAL: el armador sigue leyendo
--   order_id y no se entera.
-- ⚠ FAIL-CLOSED, a proposito y al reves del patron habitual: si no se puede evaluar (sin
--   permiso, o la marcacion explota) devuelve TODO el lote, o sea que no se programa nada.
declare
  v_ped jsonb;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    return query select distinct (x->>'order_id')::bigint, array['sin_permiso']::text[]
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
    select m.order_id::bigint, coalesce(m.motivos, array[]::text[])
      from public.gv_cuarentena_marcar_calc(v_ped) m
     where m.order_id ~ '^[0-9]+$';
exception when others then
  raise warning 'gv_cuarentena_retiene_lote fallo (%): se retiene TODO el lote', sqlerrm;
  return query select distinct (x->>'order_id')::bigint, array['no_se_pudo_evaluar']::text[]
    from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) x
   where coalesce(x->>'order_id','') ~ '^[0-9]+$';
end $fn$;

revoke execute on function public.gv_cuarentena_retiene_lote(text, jsonb) from public, anon;
grant  execute on function public.gv_cuarentena_retiene_lote(text, jsonb) to authenticated, service_role;

-- ── 2) el CTE `cuar` dentro de gv_ppp_web_dia_salida ────────────────────────
-- Sobre la definicion VIVA, idempotente, con raise si el texto no matchea.
-- (El bloque aplicado esta en el historial de esta version; para reaplicarlo, traer
--  pg_get_functiondef('public.gv_ppp_web_dia_salida(jsonb,timestamptz)'::regprocedure) y
--  agregarle el CTE de abajo antes de `pend_auto as (`, mas las tres ramas del CASE.)
--
--   cuar_in  -> una fila por EMPRESA con sus pedidos
--   cuar_out -> lateral gv_cuarentena_retiene_lote(empresa, filas)
--   cuar     -> idx + motivos (desarmados con unnest) + tiene_otro
--
-- y en los tres CASE, ANTES de todo lo demas:
--   r_dia     : when exists (select 1 from cuar where cuar.idx = f.idx) then null
--   r_motivo  : 'cuarentena' si tiene_otro, si no 'cliente_nuevo'
--   r_detalle : el texto con los motivos
-- ademas `pend_auto` deja de sumar los m3 de lo retenido (el umbral del intradia no puede
-- contar m3 que el automatico no va a armar).
