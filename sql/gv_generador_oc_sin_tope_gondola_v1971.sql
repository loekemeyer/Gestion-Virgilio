-- ============================================================================
-- v19.71 — El MAXIMO de la OC ya NO se topea por la capacidad de góndola
--
-- Thomas, 2026-09-18: *"no contemples el maximo de gondola para pedidos.
-- Tenemos que tener la mercadería que hace falta, despues vemos como la guardamos"*.
--
-- ANTES:  Máximo = LEAST(ceil(proyección × índice), capacidad de góndola)
-- AHORA:  Máximo = ceil(proyección × índice)
--
-- La capacidad SIGUE valiendo en las otras dos ramas del CASE, y eso es a propósito:
--   · `llenar_gondola = true` → Máximo = capacidad. Ahí la capacidad es el OBJETIVO
--     del código (llenar la góndola), no un techo que recorta la compra.
--   · código con proveedor real pero SIN proyección → Máximo = capacidad. Es la única
--     referencia que queda; sin eso pediría 0 y no se compraría nunca.
--
-- MEDIDO el 18/09, antes de aplicar:
--
--   | | |
--   |---|---|
--   | códigos que suben el Máximo   | **49** |
--   | códigos que pasan a pedir más | **33** |
--   | cajas de más a pedir          | **2.178** |
--   | total a pedir: antes → ahora  | 7.324 → **9.502** |
--
--   Peores: 501 365→888 · 31 0→223 · 315 0→211 · 505 594→768 · 583E 72→203 ·
--   321 320→425 · 207 0→101.
--
--   El 321, que es el que abrió el tema: proyección 366 × 1,5 = **550** de Máximo
--   (antes quedaba en 445, la capacidad), con 321 de stock y 196 pedidas → **425**.
--
-- ⚠ CONSECUENCIA ESPERADA, no un bug: al comprar por encima de la góndola, el aviso
-- de recepción *"no entra en góndola"* (`_opGondExceso`, GOND_EXCESO_FACTOR 1.20) va a
-- saltar más seguido, y el excedente va a racks. Es exactamente lo que Thomas aceptó
-- con *"después vemos cómo la guardamos"*.
--
-- ⚠ `vista_generador_oc` la lee TAMBIÉN el front de Producción Virgilio
-- (`index.html`, `sw.js`) → la nota va en `docs/ROLLBACK-PRODUCCION.md`.
--
-- Respaldo de la definición previa + opciones:
-- `zz_backups."GV_Backup_Def_GeneradorOC_20260918b"`.
-- ============================================================================

do $do$
declare
  v_def text;
  v_viejo text := 'LEAST(ceil(b.proy * b.indice), COALESCE(NULLIF(b.cap, 0::numeric), 1000000000::numeric))';
  v_nuevo text := 'ceil(b.proy * b.indice)';
begin
  -- se parte de la definicion VIVA, nunca de una copia del repo
  v_def := pg_get_viewdef('public.vista_generador_oc'::regclass, true);
  if position(v_viejo in v_def) = 0 then
    raise exception 'el ancla del reemplazo NO esta en la definicion viva (ya aplicado, o la vista cambio)';
  end if;
  if (length(v_def) - length(replace(v_def, v_viejo, ''))) / length(v_viejo) <> 1 then
    raise exception 'el ancla aparece mas de una vez: reemplazo ambiguo';
  end if;
  execute 'create or replace view public.vista_generador_oc as ' || replace(v_def, v_viejo, v_nuevo);
  -- CREATE OR REPLACE VIEW borra las reloptions: se repone SIEMPRE
  execute 'alter view public.vista_generador_oc set (security_invoker = true)';
end $do$;

comment on view public.vista_generador_oc is
  'v19.66 - A pedir = max(0, ceil(Maximo + Pedidos - Stock)). Maximo = proyeccion x indice, SIN topear por la capacidad de gondola (Thomas 18/09). La capacidad sigue valiendo en llenar_gondola y en un codigo con proveedor pero sin proyeccion. Pedidos = NP no facturadas cuya tanda no tiene TP, de ISIS y de la WEB.';

-- El centinela, para que el tope no vuelva de contrabando en un CREATE OR REPLACE:
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
-- values ('vista_generador_oc','vista','THEN ceil\(b\.proy \* b\.indice\)', '<la regla>', 'Thomas','v19.66');

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- select codn, proy::int, cap::int, maximo::int, stock::int, pedidos::int, total
--   from public.vista_generador_oc where codn = '321';
--   -> maximo 550 (NO 445, que es la capacidad), a pedir 425
--
-- select relname, array_to_string(reloptions,',') opciones,
--        (pg_get_viewdef(oid, true) like '%LEAST(ceil(b.proy%') as sigue_topeando
--   from pg_class where oid='public.vista_generador_oc'::regclass;
--   -> security_invoker=true · sigue_topeando = false
--
-- select count(*) from public.gv_reglas_perdidas;   -- 0
-- select count(*) from public.gv_endpoints_rotos;   -- 0
--
-- ============================================================================
-- ROLLBACK  (vuelve a topear por góndola: 2.178 cajas menos)
-- ============================================================================
-- do $$ declare d text; begin
--   select definicion into d from zz_backups."GV_Backup_Def_GeneradorOC_20260918b";
--   execute 'create or replace view public.vista_generador_oc as ' || d;
--   execute 'alter view public.vista_generador_oc set (security_invoker = true)';
-- end $$;
-- delete from public."GV_Reglas_Centinela" where version = 'v19.66';
