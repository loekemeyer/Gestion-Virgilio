-- =====================================================================
--  fn_canon_cod_art() — v17.01 (2026-09-14)
--
--  Trigger BEFORE INSERT sobre "Movimientos_Stock" que canoniza el código de
--  artículo. Existía desde antes; lo que cambia acá son las dos ramas que dejaban
--  pasar grafías distintas del mismo artículo.
--
--  ── (1) Se SACÓ la autoexclusión del pipeline ────────────────────────────
--  Tenía esta línea:
--      if NEW.tipo in ('picking','separado','facturado') then return NEW; end if;
--  o sea que el trigger que canoniza el código NO corría justo para los
--  movimientos que escribe el operario. Consecuencia real, no teórica:
--
--    • el front del operario escribía el código crudo (ej. `66`);
--    • el cron sí canoniza (resuelve contra `Equivalencias_Codigos`) y escribe `066`;
--    • el índice de idempotencia `mov_stock_pipeline_dedup` compara por
--      `upper(trim(cod_art))`, así que ve `66` y `066` como DOS filas distintas
--      → el `ON CONFLICT` no dispara y **el picking se duplica**.
--
--  Pasó el 14/09 a las 09:00:01: al normalizar las 6 filas de `66` a `066` (v16.96),
--  la corrida siguiente del cron 68 reinsertó el picking de la tanda `D72C` como
--  `66`, y la góndola del 066 quedó descontada dos veces (188 → 159). Se borraron
--  las 3 filas espurias (backup `zz_backups."GV_Backup_Stock_Dup_D72C_20260914"`).
--
--  Medido ANTES de sacar la exclusión, para acotar el riesgo:
--    • de los 313 códigos que hoy pasan por el pipeline, **solo 1 cambia** (el `66`);
--    • de los 5 `cod_real` que usa el cron (`Equivalencias_Codigos`), **no cambia
--      ninguno** → front y cron convergen a la misma grafía en vez de divergir.
--  Y verificado DESPUÉS: con el trigger nuevo, correr el cron a mano ya no
--  reinserta nada (0 filas con grafía `66`, saldos intactos).
--
--  ── (2) Insumos: se deja de hacer upper() ciego ──────────────────────────
--  Hacía `NEW.cod_art := upper(btrim(NEW.cod_art))`, pero el catálogo `Insumos`
--  guarda **`H201Part`** en CamelCase. O sea que el propio trigger fabricaba la
--  grafía (`H201PART`) que después no matcheaba con su catálogo — fue el que creó
--  la segunda grafía del insumo. Ahora resuelve contra `Insumos` y respeta SU
--  grafía; si el insumo no está catalogado, cae al `upper()` de siempre para que
--  al menos la regla siga siendo determinista.
--
--  Rollback: sql/backups/fn_canon_cod_art_pre_v1701_20260914.sql
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_canon_cod_art()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  k text;
  c text;
begin
  if NEW.cod_art is null then return NEW; end if;

  -- INSUMOS. v17.01: antes hacia upper() ciego, pero el catalogo "Insumos" guarda
  -- CamelCase (H201Part), asi que el propio trigger fabricaba la grafia que despues
  -- no matcheaba con su catalogo. Ahora resuelve contra el catalogo y respeta SU
  -- grafia; si el insumo no esta catalogado, cae al upper() de siempre.
  if NEW.deposito = 'insumos' then
    select i.cod into c from public."Insumos" i
     where upper(btrim(i.cod)) = upper(btrim(NEW.cod_art)) limit 1;
    NEW.cod_art := coalesce(c, upper(btrim(NEW.cod_art)));
    return NEW;
  end if;

  -- v17.01: SE SACO la linea "if NEW.tipo in ('picking','separado','facturado') then
  -- return NEW; end if;". Esa exclusion dejaba sin canonizar justamente lo que escribe
  -- el operario, y como el indice mov_stock_pipeline_dedup compara por
  -- upper(trim(cod_art)), el front podia escribir '66' y el cron '066' -> el indice los
  -- veia distintos y el picking se duplicaba (paso el 14/09 con la tanda D72C).
  -- Medido antes de sacarla: de 313 codigos del pipeline solo 1 cambia, y de los 5
  -- cod_real que usa el cron (Equivalencias_Codigos) no cambia ninguno, asi que front y
  -- cron convergen a la misma grafia en vez de divergir.
  k := regexp_replace(upper(btrim(NEW.cod_art)), '^0+(?=.)', '');
  if k = '' then return NEW; end if;
  select o.cod into c
    from public."OC_Maximos" o
   where o.activo
     and regexp_replace(upper(btrim(o.cod)), '^0+(?=.)', '') = k
   limit 1;
  if c is not null then
    NEW.cod_art := c;
  elsif NEW.cod_art ~ '^[0-9]+$' then
    NEW.cod_art := case when length(k) >= 3 then k else lpad(k, 3, '0') end;
  end if;
  return NEW;
end;
$function$;
