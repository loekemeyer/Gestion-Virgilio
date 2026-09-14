-- =====================================================================
--  fn_canon_cod_art() — v17.44 (2026-09-14)
--
--  OPCION "B" del analisis de por que el sufijo de empresa vuelve sesion tras sesion.
--
--  ── QUE ESTABA MAL ───────────────────────────────────────────────────
--  El codigo llegaba ENTERO a la busqueda de grafia:
--      k := regexp_replace(upper(btrim(NEW.cod_art)), '^0+(?=.)', '');
--  o sea que para un dual el `k` era `437E LK`. Contra `OC_Maximos` eso no matchea
--  nada (ahi el codigo es `437E`), y el `elsif NEW.cod_art ~ '^[0-9]+$'` tampoco
--  aplica porque la cadena tiene letras y un espacio. Resultado: **la funcion no
--  hacia nada**. Para los 4 codigos duales (809E / 437E / 438E / 439E) la
--  resolucion de grafia estaba de hecho APAGADA.
--
--  Andaba de casualidad porque el front manda justo la grafia canonica
--  (`index.html` ~10851 arma el texto del PKC con el codigo crudo: `D67L|437E LK|…`).
--  Cualquier variante entraba cruda y el indice de idempotencia
--  `mov_stock_pipeline_dedup` —que compara por `upper(trim(cod_art))`— la veia como
--  OTRA fila. Ese es exactamente el mecanismo que el 14/09 duplico el picking de la
--  tanda D72C con `66` vs `066`.
--
--  Medido: `0437E LK` terminaba guardado como `0437E`/LK y `437E LK` como `437E`/LK
--  — dos filas distintas para el mismo articulo y la misma empresa.
--
--  ── QUE SE HIZO ──────────────────────────────────────────────────────
--  Se separa el sufijo de empresa ANTES de buscar la grafia y se lo vuelve a pegar,
--  normalizado a UN espacio y en mayuscula. Nada mas.
--
--  ── QUE NO SE HIZO, Y POR QUE ────────────────────────────────────────
--  **No se reordeno ningun trigger.** La idea original era renombrar
--  `trg_canon_cod_art` a `zzz_` para que corriera despues de `zz_normalizar_empresa`
--  (el que saca el sufijo y setea `empresa`). Se descarto al medir:
--
--   • renombrar `trg_canon_cod_art` a `zzz_` mueve TAMBIEN a `trg_validar_mov_insumo`,
--     que pasaria de ver el codigo canonizado a verlo crudo y dejaria de encontrar la
--     categoria del insumo (no falla: deja de validar, que es peor);
--   • adelantar `zz_normalizar_empresa` al principio rompe la conversion MC->Uni:
--     `Insumos_Factores` guarda los factores como **`437E CH`** y **`439E LK`**, CON
--     sufijo (x72 y x24). Sacarselo antes hace que el factor no se encuentre.
--
--  Con el fix adentro de la funcion, `zz_normalizar_empresa` sigue corriendo 4to y ve
--  exactamente lo mismo que veia antes. Orden actual (BEFORE INSERT, alfabetico):
--    1. normalizar_unidad_insumo
--    2. trg_canon_cod_art        <- esta funcion
--    3. trg_validar_mov_insumo
--    4. zz_normalizar_empresa
--
--  ── MEDICION ANTES DE APLICAR ────────────────────────────────────────
--  Sobre los **392 codigos crudos reales** (campo 2 del `texto` de todos los eventos
--  PKC/CP de `Registros_Produccion_Virgilio` + todo `cod_art` distinto de
--  `Movimientos_Stock` con `deposito <> 'insumos'`): **cambian 0**.
--  Es una GARANTIA, no un cambio de comportamiento — por eso se pudo aplicar con el
--  deposito operando.
--
--  ── VERIFICACION DESPUES (transaccion con ROLLBACK, triggers de Telegram
--     deshabilitados dentro de la transaccion para no mandar avisos falsos) ──
--    '437e lk'   -> 437E / LK      \
--    '0437E LK'  -> 437E / LK       |  las 5 variantes sucias del mismo articulo
--    '437E  LK'  -> 437E / LK       |  convergen a UNA sola fila
--    '437E LK'   -> 437E / LK      /
--    '0809e ch'  -> 809E / CH
--    '66'        -> 066  / Mixto   (sin cambio)
--    '599E'      -> 599E / Mixto   (sin cambio)
--    '439EL'     -> 439E / LK      (sin cambio: lo resuelve zz_normalizar_empresa)
--  Post-rollback: 0 filas de prueba, 0 triggers deshabilitados, 0 movimientos con
--  sufijo, `gv_stock_particion_sospechosa` vacia.
--
--  ── LO QUE ESTO **NO** ARREGLA ───────────────────────────────────────
--  Sigue habiendo 5 definiciones distintas de "codigo canonico" repartidas en 25
--  objetos (19 funciones + 6 vistas que copian el regexp a mano; solo 2 de los 25
--  sacan el sufijo). Eso es la opcion "A" y va aparte — ver el problema
--  "No existe UNA definicion de codigo canonico" en `github_repo_problemas`.
--
--  Rollback: sql/fn_canon_cod_art_v1701.sql (ejecutar tal cual).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_canon_cod_art()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  k      text;
  c      text;
  v_raw  text;
  v_emp  text;
  v_base text;
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

  -- v17.44: SE SEPARA EL SUFIJO DE EMPRESA ANTES DE BUSCAR LA GRAFIA y se lo vuelve a
  -- pegar normalizado a UN espacio y en mayuscula. Antes el codigo llegaba entero
  -- ("437E LK") a la busqueda contra OC_Maximos, no matcheaba, y la funcion NO HACIA
  -- NADA: para los 4 duales la resolucion de grafia estaba de hecho apagada.
  -- NO se reordeno ningun trigger a proposito (ver el encabezado del archivo).
  -- Medido antes de aplicar: sobre los 392 codigos crudos reales cambian 0.
  v_raw  := btrim(NEW.cod_art);
  v_emp  := upper(coalesce((regexp_match(v_raw, '\s+(LK|CH|LOKE)$', 'i'))[1], ''));
  v_base := btrim(regexp_replace(v_raw, '\s+(LK|CH|LOKE)$', '', 'i'));

  k := regexp_replace(upper(v_base), '^0+(?=.)', '');
  if k = '' then return NEW; end if;

  select o.cod into c
    from public."OC_Maximos" o
   where o.activo
     and regexp_replace(upper(btrim(o.cod)), '^0+(?=.)', '') = k
   limit 1;

  if c is not null then
    NEW.cod_art := c || case when v_emp = '' then '' else ' ' || v_emp end;
  elsif v_base ~ '^[0-9]+$' then
    NEW.cod_art := (case when length(k) >= 3 then k else lpad(k, 3, '0') end)
                   || case when v_emp = '' then '' else ' ' || v_emp end;
  end if;
  return NEW;
end;
$function$;
