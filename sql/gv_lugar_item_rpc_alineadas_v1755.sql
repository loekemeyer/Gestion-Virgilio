-- =====================================================================
--  gv_lugar_item_guardar / _sacar — las dos mitades alineadas a UNA regla — v17.55 (2026-09-14)
--
--  Cierra la mitad que quedó pendiente del problema
--  "gv_lugar_item_guardar borra el espejo con una regla laxa y escribe con una estricta"
--  (la otra mitad —el candado de canonización en `GV_Lugar_Item`— fue la v17.51).
--
-- ─────────────────────────────────────────────────────────────────────
--  QUÉ ESTABA MAL
-- ─────────────────────────────────────────────────────────────────────
--  Las dos mitades de la MISMA función usaban canonizadoras distintas:
--
--    • escribía  →  `on conflict (sector, cod)` sobre el TEXTO CRUDO  ...... ESTRICTO
--    • borraba   →  `gv_cod_stock(cod) = gv_cod_stock(v_cod)`  ............. LAXO
--
--  `gv_cod_stock` no sólo pela ceros: **además pela el sufijo de empresa, la variante `L`
--  y trunca en el punto medio**. O sea que la asimetría cortaba para los dos lados:
--
--   (a) borrar SÍ encontraba una grafía vieja, pero escribir NO la pisaba → creaba una
--       SEGUNDA fila en `Capacidad_Sector` para el mismo artículo y sector. Es la
--       divergencia del problema 84 que esta RPC debería evitar, y el mismo mecanismo que
--       duplicó el picking de la tanda `D72C` con `66`/`066`.
--   (b) el delete laxo podía llevarse la capacidad de OTRO artículo que colapsara en la
--       misma clave: `437E` vs `437E CH`, o dos flejes que sólo se distinguen después del
--       punto medio.
--
--  En `gv_lugar_item_sacar` era **peor**: ahí el delete laxo borra de `GV_Lugar_Item`, o sea
--  del mapa vivo que lee el picking. Sacar `437E` de un sector se habría llevado también
--  `437E CH` si convivieran.
--
-- ─────────────────────────────────────────────────────────────────────
--  A CUÁL SE ALINEÓ, Y POR QUÉ
-- ─────────────────────────────────────────────────────────────────────
--  A la **ESTRICTA** (`cod = v_cod`), que es exactamente la del `on conflict`.
--  Se puede porque desde la v17.51 las DOS tablas están canonizadas por trigger
--  (`trg_canon_capacidad_sector_cod` y `trg_canon_gv_lugar_item_cod`, las dos vía
--  `canon_cod_art_val`), así que **el código canónico ES la identidad de la fila** y no hace
--  falta una regla laxa para encontrar grafías viejas: ya no pueden entrar.
--
-- ─────────────────────────────────────────────────────────────────────
--  MEDICIÓN ANTES DE APLICAR
-- ─────────────────────────────────────────────────────────────────────
--  Fila por fila sobre las **1.522 filas** de las dos tablas, contando cuántas encuentra
--  cada regla:
--    `Capacidad_Sector` 732 filas → **0 difieren**, 0 que la estricta no encuentre,
--                                   0 que la laxa agarre de más
--    `GV_Lugar_Item`    790 filas → **0 difieren**, 0 y 0
--  Y 0 pares de códigos que colapsen bajo `gv_cod_stock` dentro de un mismo sector, y
--  0 grafías no canónicas. O sea: equivalente hoy, y sin la asimetría estructural.
--
-- ─────────────────────────────────────────────────────────────────────
--  VERIFICACIÓN DESPUÉS (transacción con ROLLBACK, sector A80)
-- ─────────────────────────────────────────────────────────────────────
--    A. guardar `'66'` cap=5        → mapa `066`      · cap `066=5`
--    B. re-guardar `'  066 '` cap=9 → mapa `066`      · cap `066=9`   ← UNA fila, no duplicó
--    C. sacar `'66'`                → borró mapa=1 cap=1, las dos vacías
--  El paso B es el que antes fabricaba la segunda fila.
--
--  Y se confirmó que ninguna de las dos usa ya `gv_cod_stock` **en código real** (aparece
--  sólo en los comentarios de acá; medido con `regexp_replace(prosrc,'--[^\n]*','','g')` —
--  medir sobre el texto crudo da un falso positivo, error que ya se cometió antes).
--
-- ─────────────────────────────────────────────────────────────────────
--  ⚠ HALLAZGO AL COSTADO: `LIBRE` NO ES BASURA — y 6 filas que sí están mal
-- ─────────────────────────────────────────────────────────────────────
--  ⚠⚠ **CORRECCIÓN de lo que decía este bloque antes: NO hay que "limpiar" las 54 filas
--  `cod = 'LIBRE'`.** Se escribió que contradecían la regla 2 del handoff ("sin número no
--  hay fila de capacidad") y que convenía borrarlas. **Está mal, y borrarlas rompe cosas.**
--
--  `LIBRE` es el marcador de **"esta posición está vacía y disponible"**, y está VIVO:
--    • `vista_generador_oc` lo excluye explícitamente dos veces (`<> 'LIBRE'`);
--    • el badge **"posiciones LIBRES"** del mapa lo cuenta y lo muestra;
--    • el autocompletado de la ubicación del excedente **lo prioriza a propósito**
--      ("se prioriza lo que está LIBRE, que es donde suele ir un excedente");
--    • el modal **Mover** valida con él ("el destino tiene que estar LIBRE o con el MISMO código");
--    • `pmapVieja` y el armado de código→sectores lo saltean.
--  Y la "contradicción" con la regla 2 no existe: esa regla es para artículos reales. Una
--  posición vacía con `cajas_max` NULL es exactamente lo correcto.
--
--  Son 54 filas en 54 sectores, **todos existentes en `GV_Lugar`** (39 de la góndola P entera
--  con empresa CH, 8 LK, 6 LOKE).
--
--  **LO QUE SÍ ESTÁ MAL SON 6**, marcadas `LIBRE` pero con algo adentro:
--    A60 → tiene `989E` y `992E`   ·  A65 → `396` y `556`   ·  C01 → `547`
--    C15 → `510T` y `581T`          ·  Ñ55 → `838E`
--    A83 → `LIBRE` con `cajas_max = 72` y sin artículo (inconsistente pero inocuo)
--  Las 5 primeras importan: el badge cuenta libres de más y el autocompletado puede mandar a
--  un operario a dejar un excedente en una celda ocupada — justo lo que el handoff advierte
--  ("que una celda ACEPTE otro código no significa que ESTÉ libre").
--
--  **Causa raíz, con caso testigo:** A60 es la celda que la sesión de Thomas ocupó el 14/09
--  con `989E` y `992E`. Le pusieron el artículo y **la marca `LIBRE` quedó**: o sea que
--  `gv_lugar_item_guardar` no saca la fila `LIBRE` del sector al cargar un artículo. Ése es
--  el bug de fondo; las 6 filas son el síntoma acumulado. Registrado como problema aparte,
--  **sin tocar ningún dato** (protocolo: no modificar sin permiso explícito).
--
--  Ojo al medir: con `cajas_max` NULL, un `string_agg(cod || '=' || cajas_max::text)` las
--  **esconde** (el `||` con NULL da NULL). Eso hizo que una prueba pareciera dejar una fila
--  huérfana cuando en realidad la fila era preexistente y ajena.
--
--  Rollback: el cuerpo anterior de las dos funciones está en el historial de git; la única
--  diferencia es volver `cod = v_cod` a
--  `public.gv_cod_stock(cod) = public.gv_cod_stock(v_cod)` en los tres DELETE.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.gv_lugar_item_guardar(p_sector text, p_cod text, p_clase text DEFAULT 'articulo'::text, p_cajas_max numeric DEFAULT NULL::numeric)
 RETURNS TABLE(sector text, cod text, clase text, cajas_max numeric, empresa text)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
declare
  v_key text := upper(btrim(coalesce(p_sector, '')));
  v_sec text;
  v_emp text;
  v_cod text := public.canon_cod_art_val(p_cod);
begin
  if v_key = '' then raise exception 'Falta el lugar.'; end if;
  if coalesce(btrim(v_cod), '') = '' then raise exception 'Falta el código.'; end if;
  if coalesce(p_clase, '') not in ('articulo', 'insumo') then
    raise exception 'Clase inválida: % (va articulo o insumo)', p_clase;
  end if;
  if p_cajas_max is not null and p_cajas_max < 0 then
    raise exception 'La capacidad no puede ser negativa (%).', p_cajas_max;
  end if;

  select l.sector, l.empresa into v_sec, v_emp
    from public."GV_Lugar" l where upper(btrim(l.sector)) = v_key;
  if v_sec is null then
    raise exception 'El lugar % no existe. Los lugares se dan de alta en GV_Lugar.', p_sector;
  end if;

  insert into public."GV_Lugar_Item" (sector, cod, clase, cajas_max, activo, created_at, updated_at)
  values (v_sec, v_cod, p_clase, p_cajas_max, true, now(), now())
  on conflict (sector, cod, clase) do update
    set cajas_max = excluded.cajas_max, activo = true, updated_at = now();

  -- El espejo existe SI HAY capacidad. Sin número no se escribe una fila vacía: la celda
  -- tiene que quedar en `solo_mapa` (ámbar, "sin capacidad cargada") y no en verde, que es
  -- justamente el aviso de que al depósito le falta cargarla.
  --
  -- v17.55: EL DELETE Y EL INSERT USAN LA MISMA REGLA. Antes el delete comparaba
  -- `gv_cod_stock(cod) = gv_cod_stock(v_cod)` (LAXO: además de pelar ceros, pela el sufijo de
  -- empresa, la variante L y trunca en el punto medio) mientras el insert usa
  -- `on conflict (sector, cod)` sobre el texto CRUDO (ESTRICTO). O sea que borrar SÍ
  -- encontraba una grafía vieja pero escribir NO la pisaba: creaba una SEGUNDA fila para el
  -- mismo artículo y sector — la divergencia del problema 84 que esta RPC debería evitar, y
  -- el mismo mecanismo que duplicó el picking de D72C. Y al revés, el delete laxo podía
  -- llevarse la capacidad de OTRO artículo que colapsara en la misma clave (437E vs 437E CH,
  -- o dos flejes que sólo se distinguen después del punto medio).
  -- Se alinea a la ESTRICTA porque las dos tablas están canonizadas por trigger
  -- (Capacidad_Sector con trg_canon_capacidad_sector_cod y GV_Lugar_Item con
  -- trg_canon_gv_lugar_item_cod desde la v17.51), así que el código canónico ES la identidad.
  -- Medido antes: sobre las 1.522 filas de las dos tablas, laxa y estricta encuentran
  -- exactamente lo mismo (0 difieren, 0 que la estricta no encuentre, 0 que la laxa agarre de más).
  if p_cajas_max is null then
    delete from public."Capacidad_Sector"
     where upper(btrim(sector)) = v_key and cod = v_cod;
  else
    insert into public."Capacidad_Sector" (sector, cod, cajas_max, empresa)
    values (v_sec, v_cod, p_cajas_max, v_emp)
    on conflict (sector, cod) do update
      set cajas_max = excluded.cajas_max,
          empresa   = coalesce(excluded.empresa, public."Capacidad_Sector".empresa);
  end if;

  return query select v_sec, v_cod, p_clase, p_cajas_max, v_emp;
end $function$;


CREATE OR REPLACE FUNCTION public.gv_lugar_item_sacar(p_sector text, p_cod text, p_clase text DEFAULT 'articulo'::text)
 RETURNS TABLE(sacados_mapa integer, sacados_capacidad integer)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
declare
  v_key text := upper(btrim(coalesce(p_sector, '')));
  v_cod text := public.canon_cod_art_val(p_cod);
  v_m int := 0;
  v_c int := 0;
begin
  if v_key = '' or coalesce(btrim(v_cod), '') = '' then
    raise exception 'Falta el lugar o el código.';
  end if;
  -- v17.55: misma alineación que en gv_lugar_item_guardar, y acá importaba más: el delete
  -- laxo borraba de GV_Lugar_Item, o sea del mapa vivo que lee el picking. Sacar `437E` se
  -- habría llevado también `437E CH` si convivieran en el sector.
  delete from public."GV_Lugar_Item"
   where upper(btrim(sector)) = v_key
     and cod = v_cod
     and clase = coalesce(p_clase, 'articulo');
  get diagnostics v_m = row_count;
  delete from public."Capacidad_Sector"
   where upper(btrim(sector)) = v_key
     and cod = v_cod;
  get diagnostics v_c = row_count;
  return query select v_m, v_c;
end $function$;
