-- =====================================================================
--  PROPUESTA — NO APLICADA. Requiere tu OK (apply_migration está en deny).
--  Normalización AL ENTRAR de las tablas espejo del Sheet PPP.
--  Items 4.3 / 4.4 de docs/AUDITORIA-DATOS-DUPLICADOS.md (idea 7411).
--  Relevado contra datos reales el 2026-08-28.
--
--  SOLO DDL: no toca ni una fila de datos. Las 3 tablas son full-replace
--  (Apps Script DELETE+INSERT, cron TRUNCATE+INSERT, importador del
--  supervisor DELETE+INSERT), así que el próximo sync deja todo
--  normalizado sin backfill ni UPDATE. Cumple el protocolo de CLAUDE.md.
--
--  QUÉ CAMBIÓ RESPECTO DE LO QUE DECÍA LA AUDITORÍA:
--   · El problema del ".0" YA NO EXISTE: 0 de 11.954 filas. Lo arreglaron
--     upstream el Apps Script y el importador del front. El doble-query de
--     index.html:14022 (`pedido=in.(np, np+'.0')`) es CÓDIGO MUERTO probado.
--   · Ya existía un trigger de tanda (`fn_norm_tanda` en Programacion_Diaria
--     y Entregados_Meta) que recorta bordes pero NO hace upper().
--   · La auditoría decía "toda vista hace upper(btrim(tanda))": FALSO, solo
--     vista_tanda_m3. `ppp_etapa_tanda` compara case-sensitive.
--
--  EL HALLAZGO QUE JUSTIFICA APLICARLO (bug real, medible):
--   19 filas de PPP_Base_Pedidos tienen `articulo` en MINÚSCULA — 943e(7),
--   948e(6), 942e(2), 838e(2), 580e(1), 574e(1). El front consulta
--   `articulo=eq.` + codBase(cod), que uppercasea (index.html:14855 y 14992),
--   así que esas 19 NPs / 36 cajas NO SE VEN en "Cajas pedidas". No es un
--   dato nuevo: es un dato escondido. Al aplicar esto, las cajas pedidas de
--   943E, 948E, 942E, 838E, 580E y 574E SUBEN un poco — avisar a quien mira
--   las OCs para que no lo tome por un error.
-- =====================================================================

-- (1) TANDA — la función YA EXISTE y ya recorta bordes; solo se le suma UPPER().
--     CREATE OR REPLACE: los triggers que la usan (trg_norm_tanda_prog,
--     trg_norm_tanda_meta) siguen colgados, no se tocan.
--     Impacto hoy: 7 filas 'Retira' -> 'RETIRA' en PPP_Entregados_Meta.
CREATE OR REPLACE FUNCTION public.fn_norm_tanda()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.tanda is not null then
    new.tanda := upper(
                   regexp_replace(
                     regexp_replace(btrim(new.tanda), '^[^A-Za-z0-9]+', ''),
                     '[^A-Za-z0-9]+$', ''));
  end if;
  return new;
end $function$;

-- (2) PPP_Base_Pedidos — pedido (NP), articulo, cliente.
--     El ".0" se saca SOLO si toda la cadena es "dígitos.ceros" (mismo criterio
--     que pickNormNp()), para no mutilar un código que termine en '.0'.
--     articulo -> upper: arregla las 19 filas invisibles.
--     NO se sacan ceros a la izquierda: el front consulta con codBase(), que NO
--     los saca; sacarlos acá rompería esos =eq.
CREATE OR REPLACE FUNCTION public.fn_norm_ppp_base_pedidos()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.pedido is not null then
    new.pedido := btrim(new.pedido);
    if new.pedido ~ '^\d+\.0+$' then
      new.pedido := regexp_replace(new.pedido, '\.0+$', '');
    end if;
  end if;
  if new.articulo is not null then
    new.articulo := upper(btrim(new.articulo));
  end if;
  if new.cliente is not null then
    new.cliente := btrim(new.cliente);
  end if;
  return new;
end $function$;

DROP TRIGGER IF EXISTS trg_norm_ppp_base ON public."PPP_Base_Pedidos";
CREATE TRIGGER trg_norm_ppp_base
  BEFORE INSERT OR UPDATE ON public."PPP_Base_Pedidos"
  FOR EACH ROW EXECUTE FUNCTION public.fn_norm_ppp_base_pedidos();

-- (3) PPP_Programacion_Diaria — np y cod. tanda ya la cubre el punto (1).
CREATE OR REPLACE FUNCTION public.fn_norm_ppp_prog()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.np is not null then
    new.np := btrim(new.np);
    if new.np ~ '^\d+\.0+$' then
      new.np := regexp_replace(new.np, '\.0+$', '');
    end if;
  end if;
  if new.cod is not null then
    new.cod := btrim(new.cod);
    if new.cod ~ '^\d+\.0+$' then
      new.cod := regexp_replace(new.cod, '\.0+$', '');
    end if;
  end if;
  return new;
end $function$;

DROP TRIGGER IF EXISTS trg_norm_ppp_prog_np ON public."PPP_Programacion_Diaria";
CREATE TRIGGER trg_norm_ppp_prog_np
  BEFORE INSERT OR UPDATE ON public."PPP_Programacion_Diaria"
  FOR EACH ROW EXECUTE FUNCTION public.fn_norm_ppp_prog();

-- (4) PPP_Entregados_Meta — np (que es la PK) y cod.
--     OJO: np es PRIMARY KEY. Es seguro porque sync_ppp_entregados_meta() ya
--     filtra `trim(np) ~ '^[0-9]{2,7}$'` y deduplica con `distinct on (np)`,
--     así que btrim/'.0' son no-op (0 filas afectadas). Por eso NO se agrega
--     quita de ceros a la izquierda: podría colapsar dos np distintos en uno y
--     abortar el INSERT completo del cron.
CREATE OR REPLACE FUNCTION public.fn_norm_ppp_entregados_meta()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.np is not null then
    new.np := btrim(new.np);
    if new.np ~ '^\d+\.0+$' then
      new.np := regexp_replace(new.np, '\.0+$', '');
    end if;
  end if;
  if new.cod is not null then
    new.cod := btrim(new.cod);
    if new.cod ~ '^\d+\.0+$' then
      new.cod := regexp_replace(new.cod, '\.0+$', '');
    end if;
  end if;
  return new;
end $function$;

DROP TRIGGER IF EXISTS trg_norm_ppp_meta_np ON public."PPP_Entregados_Meta";
CREATE TRIGGER trg_norm_ppp_meta_np
  BEFORE INSERT OR UPDATE ON public."PPP_Entregados_Meta"
  FOR EACH ROW EXECUTE FUNCTION public.fn_norm_ppp_entregados_meta();

-- =====================================================================
--  VERIFICACIÓN (resumen; el detalle largo está en el informe del agente)
--   0. Baseline ANTES: hoy da 11954 base / 19 articulo sucio / 148 prog /
--      2728 meta / 7 tanda sucia.
--   1. Que entró el DDL: los 3 triggers nuevos + fn_norm_tanda con upper().
--   2. Esperar el cron de Entregados_Meta (:07 y :37). Debe quedar ~2728
--      filas (NO 0 — si da 0 el INSERT abortó por PK: rollback ya) y 0 sucias.
--   3. Base_Pedidos y Programacion_Diaria se normalizan recién en el próximo
--      sync del Apps Script / próxima importación del Excel.
--   4. `select count(*) from vista_tanda_m3` debe dar EXACTAMENTE lo mismo.
--      `v_cajas_pedidas` SÍ baja ~6 filas (deja de emitir '943e' y '943E').
--   5. Smoke: Stock -> 943E -> "Cajas pedidas" debe listar 37 NPs / 77 cajas
--      donde antes listaba 30 / 67.
--
--  ROLLBACK: no hay datos que restaurar (las 3 tablas se reescriben enteras).
--   DROP TRIGGER IF EXISTS trg_norm_ppp_base    ON public."PPP_Base_Pedidos";
--   DROP TRIGGER IF EXISTS trg_norm_ppp_prog_np ON public."PPP_Programacion_Diaria";
--   DROP TRIGGER IF EXISTS trg_norm_ppp_meta_np ON public."PPP_Entregados_Meta";
--   DROP FUNCTION IF EXISTS public.fn_norm_ppp_base_pedidos();
--   DROP FUNCTION IF EXISTS public.fn_norm_ppp_prog();
--   DROP FUNCTION IF EXISTS public.fn_norm_ppp_entregados_meta();
--   -- y volver fn_norm_tanda a su versión sin upper().
-- =====================================================================
