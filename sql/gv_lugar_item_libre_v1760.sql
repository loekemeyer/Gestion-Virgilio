-- =====================================================================
--  `LIBRE`: `gv_lugar_item_guardar` limpia la marca al ocupar la celda — v17.60 (2026-09-14)
--
--  Pedido del dueño: *"dale con el fix, que guardar saque la marca LIBRE y que vaciar la
--  aplique, ¿no?"*. **Se hizo la primera mitad y NO la segunda.** El porqué está medido abajo.
--
-- ─────────────────────────────────────────────────────────────────────
--  ⚠⚠ ESTE ARCHIVO CORRIGE LO QUE DIJO LA v17.58. LEER ESTO, NO AQUELLO.
-- ─────────────────────────────────────────────────────────────────────
--  La v17.55 dijo *"hay 54 filas `LIBRE` de más, conviene limpiarlas"*.
--  La v17.58 lo corrigió con *"`LIBRE` está VIVO en cinco lugares, no tocar"*.
--  **Las dos estaban mal, y la segunda por leer el código al revés**: esos
--  `if (k === "LIBRE") return` no son consumidores usándola, son **guardas para
--  ESQUIVARLA**. Medido:
--
--    • `gv_planimetria_celda` **no devuelve ni una fila `cod='LIBRE'`** (0 de 54) y calcula
--      `estado = 'libre'` como **`p.k IS NULL`** — o sea por AUSENCIA de artículo en el mapa,
--      sin mirar la marca para nada;
--    • el badge de libres del mapa usa `r.estado === "libre"`, no la fila;
--    • el badge "posiciones LIBRES" que se citó como prueba **es el de RACKS**
--      (`stkRacksCapCompute`), y usa `p.ocupado`;
--    • `vista_generador_oc` la **excluye** explícitamente dos veces (`<> 'LIBRE'`);
--    • `_ocgNorm(...) === "LIBRE"` y `pmapVieja` la **saltean**;
--    • `gvFetchLugares` declara `libres: new Set()` **y nunca lo llena** (lee `GV_Lugar`,
--      no `Capacidad_Sector`): es código muerto;
--    • el "LIBRE" del modal Mover es una palabra en prosa del comentario, no el pseudo-código.
--
--  **Conclusión: `cod='LIBRE'` es residuo de la planimetría vieja que todos los consumidores
--  tienen que esquivar. No aporta ninguna señal.** "Celda vacía" se resuelve por ausencia de
--  artículo, que es lo que ya hace la vista.
--
--  Y la alarma de la v17.58 ("5 celdas marcadas LIBRE con artículo → el mapa las ofrece como
--  vacías") **también era infundada**: de esos 54 sectores la vista reporta 49 `libre`,
--  4 `solo_mapa` y 1 `ok` — **ninguno de los ocupados sale como libre**. El mapa ya los
--  muestra bien.
--
-- ─────────────────────────────────────────────────────────────────────
--  QUÉ SE HIZO
-- ─────────────────────────────────────────────────────────────────────
--  (1) `gv_lugar_item_guardar` **borra la fila `LIBRE` del sector** al cargar un artículo.
--      Una celda ocupada no debería llevar marca de vacía. Es limpieza gradual: se van
--      yendo a medida que se usan las celdas. Hoy 5 de las 54 están sobre una celda con
--      artículo; las otras 49 son celdas realmente vacías y se quedan como están.
--  (2) Guard: **`LIBRE` no se puede cargar como código de artículo**. Si entrara a
--      `GV_Lugar_Item` la celda quedaría "ocupada por LIBRE". Hoy hay 0 y así se queda.
--      El guard compara en mayúscula porque `canon_cod_art_val('libre')` devuelve `'LIBRE'`.
--
-- ─────────────────────────────────────────────────────────────────────
--  QUÉ **NO** SE HIZO, Y POR QUÉ: reponer `LIBRE` al vaciar
-- ─────────────────────────────────────────────────────────────────────
--  Sería fabricar filas que **todos los consumidores tienen que esquivar** y que no le dicen
--  nada a nadie, porque "vacía" ya se calcula por ausencia de artículo.
--  Y el dato dice que la convención ni siquiera existe: **88 celdas vacías SIN marca** contra
--  54 con marca. Las 54 no son una regla, son lo que quedó.
--  Verificado en la prueba de abajo: sacar los dos artículos de A60 deja el sector sin marca
--  y **`gv_planimetria_celda` igual lo reporta `estado = 'libre'`**.
--
-- ─────────────────────────────────────────────────────────────────────
--  VERIFICACIÓN (transacción con ROLLBACK, sector A60 — el caso testigo)
-- ─────────────────────────────────────────────────────────────────────
--    0. estado inicial ........ mapa `989E,992E`  ·  cap **`LIBRE`**
--    1. guardar `989E` cap=4 ... cap pasa a `989E`  ← **la marca se fue**
--    2. guardar `'libre'` ...... rechazado: "LIBRE no es un código de artículo…"
--    3. sacar los dos ......... mapa `-` · cap `-`  ← **NO repuso LIBRE**
--    4. y la vista dice ....... **`estado = libre`**  ← sin necesidad de la marca
--
--  No se tocó ningún dato: las 5 filas `LIBRE` que hoy están sobre celdas ocupadas se van
--  solas la próxima vez que alguien guarde ahí.
--
--  Rollback: sql/gv_lugar_item_rpc_alineadas_v1755.sql (el cuerpo sin el guard ni el delete).
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
  -- v17.60: LIBRE no es un artículo, es el marcador de posición vacía. Si entrara a
  -- GV_Lugar_Item la celda quedaría "ocupada por LIBRE". Hoy hay 0 y así se queda.
  if upper(btrim(v_cod)) = 'LIBRE' then
    raise exception 'LIBRE no es un código de artículo: es la marca de posición vacía.';
  end if;
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

  -- v17.60: la celda pasa a estar OCUPADA, así que se va la marca de posición vacía.
  -- `LIBRE` es residuo de la planimetría vieja: NINGÚN consumidor la usa como señal —
  -- `gv_planimetria_celda` no la devuelve y calcula `estado='libre'` por AUSENCIA de
  -- artículo (`p.k is null`), `vista_generador_oc` la excluye dos veces, y el front la
  -- saltea (`if (k === "LIBRE") return`). Dejarla en una celda ocupada es una fila que
  -- todos tienen que esquivar y que no le dice nada a nadie.
  -- NO se repone al vaciar (ver el encabezado): fabricaría más residuo, y la convención ni
  -- siquiera existe — hay 88 celdas vacías SIN marca contra 54 con marca.
  delete from public."Capacidad_Sector"
   where upper(btrim(sector)) = v_key and upper(btrim(cod)) = 'LIBRE';

  -- El espejo existe SI HAY capacidad. Sin número no se escribe una fila vacía: la celda
  -- tiene que quedar en `solo_mapa` (ámbar, "sin capacidad cargada") y no en verde.
  -- v17.55: el DELETE y el INSERT usan la MISMA regla (estricta, la del on conflict).
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

-- `gv_lugar_item_sacar` NO SE TOCA: sigue como quedó en la v17.55. No repone `LIBRE`.
