-- v21.22 (2026-09-22, Luis) — LAS TRES CAPAS DEL CIRCUITO "FABRICA CON MATERIAL DE LOG/ FABR".
-- Aplica lo que la v21.20 dejó escrito y pendiente; Luis lo autorizó ("1 si") acotado a los
-- tres fabricantes de GV_OC_Fabrica_Para ("2 no necesariamente, tengo que ver caso x caso").
--
-- Luis, textual, las dos frases que definen el circuito:
--   "a blistpack/oscar/pedernera no se le manda OC, porque ellos fabrican acorde a lo que le
--    mandamos desde log/fabr"
--   "Cuando pedernera entrega, el operario de GV debe poner pedernera y anotar ahi lo que
--    reciben. En el celular del operario de GV debe figurar la OC de las cajas a entregar"
--
-- | capa            | a nombre de quien      | donde                           |
-- |-----------------|------------------------|---------------------------------|
-- | se EMITE la OC  | Log/ Fabr              | gv_oc_generar_pendientes        |
-- | se ENTREGA      | el fabricante          | Entregas Tallerista Virgilio    |
-- | el BOTON del    | **el fabricante**      | oc_vigentes_por_proveedor       |
-- |   operario      |                        |                                 |
--
-- ⚠ OC_Maximos NO se toca: su `proveedor` sigue diciendo quien fabrica (regla del dueno, 15/09,
--   "dejalo ahi"). Lo que se agrego es la pieza que faltaba, GV_OC_Fabrica_Para (v21.20).

-- ── 1. al EMITIR: la orden sale a nombre de quien le manda el material ──────────────────────
create or replace function public.gv_oc_emite_a(p_prov text)
 returns text language sql stable set search_path to 'public' as $$
  select coalesce((select f.recibe_la_oc from public."GV_OC_Fabrica_Para" f
                    where gv_norm_prov_key(f.fabricante) = gv_norm_prov_key(p_prov)
                    limit 1), p_prov);
$$;
-- y en gv_oc_generar_pendientes, justo despues de leer el proveedor del row:
--     v_prov := public.gv_oc_emite_a(v_prov);
-- ⚠ Es el UNICO lugar por donde escriben el generador manual Y el automatico (cron 50).
-- Probado en transaccion abortada: Pedernera -> "Log/ Fabr", Garcia -> "Garcia".

-- ── 2. al IMPUTAR: la entrega del fabricante cierra la OC de Log/ Fabr ──────────────────────
-- El mecanismo YA existia y no habia que inventarlo: gv_norm_prov_keys devuelve un ARRAY de
-- claves y gv_prov_match las compara todas contra todas (asi estaba resuelto pettofrezza ->
-- rafael). En gv_oc_recompute_recibido, el CTE `oc` suma las claves de los fabricantes:
--     gv_norm_prov_keys(o.proveedor)
--       || coalesce((select array_agg(gv_norm_prov_key(f.fabricante))
--                      from "GV_OC_Fabrica_Para" f
--                     where gv_norm_prov_key(f.recibe_la_oc) = gv_norm_prov_key(o.proveedor)),
--                   '{}'::text[]) as pkeys
--
-- ⚠ Solo las OC emitidas a Log/ Fabr ganan claves; la OC de Oscar no matchea entregas de
--   Pedernera. Impacto medido antes de aplicar (en transaccion abortada) y despues: **6 filas**,
--   todas de 544 y 560, ninguna OC de otro proveedor se movio —
--     544 · 5 OC anuladas · 0 -> 776 cajas imputadas
--     560 · 1 OC          · 0 ->  57 · estado pendiente -> **recibida**
--   Backup previo: zz_backups."GV_Backup_OrdenesCompra_20260922" (721 filas).

-- ── 3. en el CELULAR del operario: la OC figura bajo el boton del fabricante ────────────────
-- Que codigos entrega cada fabricante. DOS fuentes unidas, y las dos hacen falta:
--   (a) OC_Maximos.proveedor  -> cuando la config ya dice el fabricante (115, 800..802, Blistpack)
--   (b) lo que VIENE entregando -> cuando la config guardo al que recibe la OC (544, 560)
-- ⚠ Por que la union y no solo (a): OC_Maximos.proveedor esta MEZCLADO. De los 4 codigos que
--   Pedernera entrego desde el 01/06 (115, 544, 560, 802 · 2.355 cajas) la config dice Pedernera
--   en 2 y Log/ Fabr en los otros 2. Derivar el boton solo de ese campo moveria **11 lineas de
--   OC** que son config vieja y no esta regla (515/615/635 Basconia->Carlos E con 1.800 cajas,
--   222 y 910 Maspoli->Pintos, 234, 618, 725). Por eso va acotado a GV_OC_Fabrica_Para.
create or replace view public.gv_oc_codigo_del_fabricante as
  select gv_norm_prov_key(f.fabricante) as fab_key, f.fabricante,
         norm_cod(m.cod) as cod_n, 'config'::text as fuente
    from public."GV_OC_Fabrica_Para" f
    join public."OC_Maximos" m on gv_norm_prov_key(m.proveedor) = gv_norm_prov_key(f.fabricante)
   where nullif(btrim(m.cod),'') is not null
  union
  select gv_norm_prov_key(f.fabricante), f.fabricante,
         norm_cod(e."Cod"), 'entrega'
    from public."GV_OC_Fabrica_Para" f
    join public."Entregas Tallerista Virgilio" e
      on gv_norm_prov_key(e."Nombre_Tall") = gv_norm_prov_key(f.fabricante)
   where e."Fecha" >= to_char(current_date - 180, 'YYYY-MM-DD')
     and nullif(btrim(e."Cod"),'') is not null;
alter view public.gv_oc_codigo_del_fabricante set (security_invoker = true);

-- En oc_vigentes_por_proveedor se agregaron dos CTE entre oc_match y max_fecha:
--   oc_mas  -> (+) el fabricante ve la OC emitida a su nombre-de-orden, SOLO para SUS codigos
--   oc_todo -> (-) el que recibe la orden deja de verla: no es el que las trae
-- y max_fecha + el join final leen oc_todo en vez de oc_match.

-- ⚠⚠ LA TRAMPA DE LA v20.45, y mordio: GV_OC_Fabrica_Para nacio con RLS sin policy, y
--    oc_vigentes_por_proveedor es INVOKER. Medido: **postgres veia 1 codigo y el operario 0**.
--    No da error — da menos filas. Probar desde el MCP no prueba nada: el MCP entra como postgres.
create policy fabrica_para_select on public."GV_OC_Fabrica_Para" for select using (true);
-- (lectura para todos; la escritura sigue revocada para anon/authenticated)

-- ── La prueba que vale, corrida como `anon` en transaccion abortada ─────────────────────────
-- Se emite la OC del 561 (lo fabrica Pedernera) y se mira que ve cada boton:
--     boton PEDERNERA: 561 (pend 41)      <- la OC aparece donde el operario la necesita
--     boton LOG/ FABR: 255                <- sigue con lo suyo, sin el 561
--     Garcia (control): 113, 323, 439E, 839  <- sin cambios
--
-- Chequeo: select * from public.gv_reglas_perdidas;                     -- vacia = todo bien
--          select * from public.gv_oc_proveedor_no_recibe_oc;           -- que sigue saliendo mal
--          select * from public.gv_oc_codigo_del_fabricante order by 2,3;
--
-- Rollback: restaurar cantidad_recibida/estado desde el backup y sacar los tres parches
--           (los patrones estan en GV_Reglas_Centinela version v21.22).
