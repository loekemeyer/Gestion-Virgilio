-- ============================================================================
-- RELEVAMIENTO GP2 (nativo) — registro de las migraciones aplicadas el 2026-09-04
-- ============================================================================
-- Migraciones (en orden):
--   1) relevamiento_gp2_esquema_y_cronograma
--   2) relevamiento_gp2_factor_y_bundle
--   3) relevamiento_gp2_abrir_detalle_guardar
--
-- POR QUE ES UN MODULO NUEVO Y NO UN AJUSTE:
-- El Relevamiento que ya existia (Relevamiento/relevamiento.js) lee del schema VIEJO
-- (relevamiento_cervantes via public.rc_*) y esta armado sobre "plantas"
-- (Cervantes/Virgilio). GP2 esta armado sobre SECTOR + ubicacion. No es el mismo
-- modelo: se mira la LOGICA del vecino (como cuenta cada tipo, como compone
-- envases+sueltas) pero no se copia su casa.
--
-- EL CIRCUITO [usuario 2026-09-04]:
--   relevar -> comparar conteo vs programa (default: conteo) -> actualizar stock
--   -> recien ahi generar la OC.
--
-- LOS 7 TIPOS DEL VIEJO MAPEAN 1:1 A SECTORES GP2:
--   Cajas->11, Flejes->5, Cartones->10, Plasticos->6, Remaches->8,
--   Bombillas->7, Garage->9.
--   "Bolsa Plast" (que aparece en el Excel del usuario) NO es uno de los 7 y NO
--   tiene sector: queda con sector_id NULL hasta que el usuario diga que es.
-- ============================================================================

-- ---------------------------------------------------------------- 1) TABLAS --

create table if not exists "GP2".relevamiento_cronograma (
  id          bigserial primary key,
  tipo        text   not null,
  sector_id   bigint references "GP2".sector(id),
  fecha       date   not null,
  nota        text,
  creado_en   timestamptz not null default now(),
  unique (tipo, fecha)
);
comment on table "GP2".relevamiento_cronograma is
  'Fechas programadas de conteo por tipo. Origen: Excel "conteo" del usuario (2026-09-04).';
comment on column "GP2".relevamiento_cronograma.sector_id is
  'Sector GP2 que se cuenta. NULL cuando el tipo del Excel todavia no tiene sector (caso "Bolsa Plast").';

create table if not exists "GP2".relevamiento (
  id              bigserial primary key,
  sector_id       bigint not null references "GP2".sector(id),
  fecha           date   not null default current_date,
  encargado       text,
  estado          text   not null default 'en_curso',   -- en_curso | contado | aplicado | anulado
  cronograma_id   bigint references "GP2".relevamiento_cronograma(id),
  creado_en       timestamptz not null default now(),
  cerrado_en      timestamptz,
  aplicado_en     timestamptz,
  constraint relevamiento_estado_ck
    check (estado in ('en_curso','contado','aplicado','anulado'))
);

-- envases = paquetes/bolsas/cajones segun el sector; sueltas = unidades sueltas;
-- kg = para flejes. total_uni es LO CONTADO ya convertido; stock_programa es la foto
-- de lo que decia el sistema al cerrar. decision dice cual gana (default: conteo).
create table if not exists "GP2".relevamiento_item (
  id               bigserial primary key,
  relevamiento_id  bigint not null references "GP2".relevamiento(id) on delete cascade,
  componente_id    bigint not null references "GP2".componente(id),
  envases          numeric,
  sueltas          numeric,
  kg               numeric,
  total_uni        numeric,
  stock_programa   numeric,
  decision         text,
  contado          boolean not null default false,
  constraint relevamiento_item_decision_ck check (decision in ('conteo','programa')),
  unique (relevamiento_id, componente_id)
);

create index if not exists ix_relev_item_relev  on "GP2".relevamiento_item(relevamiento_id);
create index if not exists ix_relev_sector_fecha on "GP2".relevamiento(sector_id, fecha desc);
create index if not exists ix_crono_fecha        on "GP2".relevamiento_cronograma(fecha);

-- El paquete de CAJAS (25 uni) estaba hardcodeado en control-cajas.js; baja a parametro
-- para que el relevamiento y el control usen el MISMO numero.
insert into "GP2".parametro (clave, valor, descripcion)
values ('caja_uni_x_paquete','25',
        'Unidades por paquete en Sector Caja. Estaba hardcodeado en control-cajas.js (uni_x_paq=25).')
on conflict (clave) do nothing;

-- ------------------------------------------------------------- 2) FUNCIONES --

-- Cuantas UNIDADES entran en un envase, y como se llama ese envase en cada sector.
-- Devuelve factor NULL cuando el dato NO esta cargado: la pantalla lo marca y NO inventa
-- un total (regla de la casa: si falta un dato, se marca pendiente, no se rellena).
create or replace function "GP2".relev_factor(p_componente_id bigint)
returns table (factor numeric, envase text, cuenta_kg boolean)
language sql stable as $$
  select
    case
      when c.sector_id = 10 and coalesce(c.es_pliego,false)
        then (select valor::numeric from "GP2".parametro where clave='pliego_uni_x_paquete')
      when c.sector_id = 10
        -- PAQUETON, no paquete: carton_formato.uni_x_bolsa (C 1.000, LOKE 1.000, Huevo
        -- 2.000, "8" 3.000). NO se usa carton_uni_x_paquete=250: ese es el paquete de
        -- PEDIDO que usa la OC. Se PIDE por paquete de 250 y se CUENTA por paqueton.
        then (select nullif(cf.uni_x_bolsa,0)
              from "GP2".carton_formato cf where cf.nombre = c.carton_formato)
      when c.sector_id = 11
        then (select valor::numeric from "GP2".parametro where clave='caja_uni_x_paquete')
      when c.sector_id = 5 then null                      -- fleje se cuenta en kg
      else nullif(c.uni_x_cajon, 0)
    end,
    case c.sector_id
      when 10 then case when coalesce(c.es_pliego,false) then 'Paq. de pliegos' else 'Paquetones' end
      when 11 then 'Paquetes'
      when  6 then 'Bolsas'
      when  7 then 'Bolsas'          -- antes 'Bolsa/Caj/Rollo' (migracion relev_factor_bombillas_en_bolsas)
      when  9 then 'Cajones'
      when  8 then 'Bolsas'
      else 'Cajones'
    end,
    (c.sector_id = 5)
  from "GP2".componente c
  where c.id = p_componente_id;
$$;

-- El total contado, calculado SIEMPRE en la base (el JS solo muestra).
create or replace function "GP2".relev_total_uni(
  p_componente_id bigint, p_envases numeric, p_sueltas numeric, p_kg numeric)
returns numeric
language plpgsql stable as $$
DECLARE f numeric; es_kg boolean; um text; kxu numeric;
BEGIN
  SELECT rf.factor, rf.cuenta_kg INTO f, es_kg FROM "GP2".relev_factor(p_componente_id) rf;
  SELECT c.unidad_medida, nullif(c.kg_x_uni,0) INTO um, kxu FROM "GP2".componente c WHERE c.id=p_componente_id;

  IF es_kg THEN
    IF p_kg IS NULL THEN RETURN NULL; END IF;
    IF um = 'kg' THEN RETURN p_kg; END IF;
    IF kxu IS NULL THEN RETURN NULL; END IF;
    RETURN round(p_kg / kxu);
  END IF;

  IF coalesce(p_envases,0) = 0 THEN RETURN coalesce(p_sueltas,0); END IF;
  IF f IS NULL THEN RETURN NULL; END IF;
  RETURN p_envases * f + coalesce(p_sueltas,0);
END $$;

-- Cronograma con el MAS PROXIMO POR SECTOR [usuario 2026-09-04: "en el cronograma aparecen
-- varias veces garage porque se hace mas de una vez por mes, pero quiero el mas proximo"].
-- Correcciones del mismo dia [usuario]:
--  (a) "me tendrian que aparecer todos a realizar, porque son todos futuros relevamientos"
--  (b) "el de garage no me pongas el de hoy, poneme el proximo" -> la fecha tiene que ser
--      ESTRICTAMENTE FUTURA (fecha > hoy). Antes era >= y Garage mostraba el de hoy.
--  (c) "me tendria que aparecer solo uno por sector, acordate" -> la clave de deduplicacion
--      es el SECTOR, no la etiqueta del Excel. Los tipos sin sector (hoy "Bolsa Plast") se
--      agrupan por su propio nombre para que no se fusionen entre si ni con ningun sector.
-- Si un sector ya no tiene fechas futuras, muestra la ultima pasada (vencida).
create or replace function "GP2".relevamiento_bundle()
returns jsonb
language sql stable security definer set search_path = "GP2", public as $$
  with base as (
    select k.*, k.sector_id::text as clave
    from "GP2".relevamiento_cronograma k
    where k.sector_id is not null                 -- sin sector no se muestra (Bolsa Plast)
      and not exists (                            -- ya validado: fuera, que pase el siguiente
        select 1 from "GP2".relevamiento r
        where r.cronograma_id = k.id and r.estado = 'aplicado'
      )
  ),
  prox as (
    select distinct on (b.clave) b.clave, b.tipo, b.sector_id, b.fecha, b.id crono_id
    from base b
    where b.fecha > current_date
    order by b.clave, b.fecha
  ),
  ult as (
    select distinct on (b.clave) b.clave, b.tipo, b.sector_id, b.fecha, b.id crono_id
    from base b
    where not exists (select 1 from prox p where p.clave = b.clave)
    order by b.clave, b.fecha desc
  ),
  fila as (select * from prox union all select * from ult)
  select jsonb_build_object(
    'hoy', current_date,
    'cronograma', coalesce(jsonb_agg(x order by x->>'fecha'), '[]'::jsonb)
  )
  from (
    select jsonb_build_object(
      'tipo', f.tipo, 'sector_id', f.sector_id, 'sector', s.nombre,
      'crono_id', f.crono_id, 'fecha', f.fecha, 'dias', (f.fecha - current_date),
      'vencido', (f.fecha < current_date),
      'componentes', (select count(*) from "GP2".componente c where c.sector_id = f.sector_id),
      'mapeado', (f.sector_id is not null),
      'relevamiento', (
        select jsonb_build_object('id', r.id, 'estado', r.estado,
                 'contados', (select count(*) from "GP2".relevamiento_item ri
                              where ri.relevamiento_id = r.id and ri.contado),
                 'items', (select count(*) from "GP2".relevamiento_item ri
                           where ri.relevamiento_id = r.id))
        from "GP2".relevamiento r
        where r.cronograma_id = f.crono_id and r.estado <> 'anulado'
        order by r.id desc limit 1
      )
    ) x
    from fila f left join "GP2".sector s on s.id = f.sector_id
  ) t;
$$;

-- Abrir: crea la cabecera y UNA FILA POR CADA COMPONENTE del sector [usuario 2026-09-04:
-- "cuando entro quiero que me aparezca a completar todos los componentes que haya por sector"].
create or replace function "GP2".relevamiento_abrir(
  p_sector_id bigint, p_crono_id bigint default null, p_encargado text default null)
returns bigint
language plpgsql security definer set search_path = "GP2", public as $$
DECLARE v_id bigint; v_fecha date;
BEGIN
  IF p_sector_id IS NULL THEN
    RAISE EXCEPTION 'Este tipo de conteo todavia no tiene sector asignado';
  END IF;

  SELECT r.id INTO v_id FROM "GP2".relevamiento r
  WHERE r.sector_id = p_sector_id AND r.estado IN ('en_curso','contado')
    AND (p_crono_id IS NULL OR r.cronograma_id IS NOT DISTINCT FROM p_crono_id)
  ORDER BY r.id DESC LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  SELECT k.fecha INTO v_fecha FROM "GP2".relevamiento_cronograma k WHERE k.id = p_crono_id;

  INSERT INTO "GP2".relevamiento (sector_id, fecha, encargado, cronograma_id)
  VALUES (p_sector_id, coalesce(v_fecha, current_date), nullif(trim(p_encargado),''), p_crono_id)
  RETURNING id INTO v_id;

  INSERT INTO "GP2".relevamiento_item (relevamiento_id, componente_id)
  SELECT v_id, c.id FROM "GP2".componente c WHERE c.sector_id = p_sector_id
  ON CONFLICT DO NOTHING;

  RETURN v_id;
END $$;

-- Detalle para la pantalla de carga: cada componente con su envase, su factor y el stock
-- que hoy dice el PROGRAMA (para poder comparar despues).
create or replace function "GP2".relevamiento_detalle(p_id bigint)
returns jsonb
language sql stable security definer set search_path = "GP2", public as $$
  select jsonb_build_object(
    'relevamiento', to_jsonb(r) - 'creado_en',
    'sector', s.nombre,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', ri.id, 'comp_id', c.id, 'codigo', c.codigo,
        'descripcion', c.descripcion, 'unidad', c.unidad_medida,
        'factor', rf.factor, 'envase', rf.envase, 'cuenta_kg', rf.cuenta_kg,
        'kg_x_uni', c.kg_x_uni,
        'envases', ri.envases, 'sueltas', ri.sueltas, 'kg', ri.kg,
        'total_uni', ri.total_uni, 'contado', ri.contado,
        'stock_programa', coalesce((
          select i.cantidad from "GP2".inventario i
          join "GP2".ubicacion u on u.id = i.ubicacion_id
          where i.componente_id = c.id and u.tipo='sector' and u.ref_id = r.sector_id
          limit 1), 0)
      ) order by c.codigo)
      from "GP2".relevamiento_item ri
      join "GP2".componente c on c.id = ri.componente_id
      cross join lateral "GP2".relev_factor(c.id) rf
      where ri.relevamiento_id = r.id
    ), '[]'::jsonb)
  )
  from "GP2".relevamiento r join "GP2".sector s on s.id = r.sector_id
  where r.id = p_id;
$$;

-- Guardar lo cargado. El TOTAL lo calcula la base, no el JS.
-- p_items: [{"item_id":1,"envases":3,"sueltas":10,"kg":null}, ...]
create or replace function "GP2".relevamiento_guardar(p_id bigint, p_items jsonb)
returns integer
language plpgsql security definer set search_path = "GP2", public as $$
DECLARE n integer := 0;
BEGIN
  IF (SELECT estado FROM "GP2".relevamiento WHERE id = p_id) <> 'en_curso' THEN
    RAISE EXCEPTION 'El relevamiento % no esta en curso', p_id;
  END IF;

  WITH d AS (
    SELECT (x->>'item_id')::bigint item_id,
           nullif(x->>'envases','')::numeric envases,
           nullif(x->>'sueltas','')::numeric sueltas,
           nullif(x->>'kg','')::numeric kg
    FROM jsonb_array_elements(p_items) x
  ), upd AS (
    UPDATE "GP2".relevamiento_item ri
    SET envases = d.envases, sueltas = d.sueltas, kg = d.kg,
        total_uni = "GP2".relev_total_uni(ri.componente_id, d.envases, d.sueltas, d.kg),
        contado = (d.envases IS NOT NULL OR d.sueltas IS NOT NULL OR d.kg IS NOT NULL)
    FROM d WHERE ri.id = d.item_id AND ri.relevamiento_id = p_id
    RETURNING 1
  ) SELECT count(*) INTO n FROM upd;

  RETURN n;
END $$;

grant execute on function "GP2".relevamiento_bundle()                          to anon, authenticated;
grant execute on function "GP2".relev_factor(bigint)                           to anon, authenticated;
grant execute on function "GP2".relev_total_uni(bigint,numeric,numeric,numeric) to anon, authenticated;
grant execute on function "GP2".relevamiento_abrir(bigint,bigint,text)         to anon, authenticated;
grant execute on function "GP2".relevamiento_detalle(bigint)                   to anon, authenticated;
grant execute on function "GP2".relevamiento_guardar(bigint,jsonb)             to anon, authenticated;

-- ------------------------------------- 3) CIERRE, COMPARACION Y AJUSTE ------
-- Migracion: relevamiento_gp2_cerrar_comparar_aplicar
-- [usuario 2026-09-04]: "cuando termino de cargar el conteo quiero poder poner completar
-- relevamiento, y que me mande a un modulo que me compare lo que hay en stock segun el
-- programa y lo que hay segun el conteo, en que yo tenga que seleccionar cual es el
-- correcto, que me tire por default que el correcto es el del conteo."

-- CERRAR: saca la foto de lo que dice el programa y propone la decision.
-- REGLA DE SEGURIDAD: lo que NO se conto queda en 'programa' (no se toca). Contar es
-- afirmar; NO contar no significa "hay cero". Poner 0 a lo no contado borraria stock real.
create or replace function "GP2".relevamiento_cerrar(p_id bigint)
returns jsonb
language plpgsql security definer set search_path = "GP2", public as $$
DECLARE v_sector bigint; v_estado text; n_cont int; n_sin int;
BEGIN
  SELECT r.sector_id, r.estado INTO v_sector, v_estado FROM "GP2".relevamiento r WHERE r.id = p_id;
  IF v_sector IS NULL THEN RAISE EXCEPTION 'No existe el relevamiento %', p_id; END IF;
  IF v_estado <> 'en_curso' THEN RAISE EXCEPTION 'El relevamiento % ya esta %', p_id, v_estado; END IF;

  UPDATE "GP2".relevamiento_item ri
  SET stock_programa = coalesce((
        SELECT i.cantidad FROM "GP2".inventario i
        JOIN "GP2".ubicacion u ON u.id = i.ubicacion_id
        WHERE i.componente_id = ri.componente_id AND u.tipo='sector' AND u.ref_id = v_sector
        LIMIT 1), 0),
      decision = CASE WHEN ri.contado AND ri.total_uni IS NOT NULL THEN 'conteo' ELSE 'programa' END
  WHERE ri.relevamiento_id = p_id;

  UPDATE "GP2".relevamiento SET estado='contado', cerrado_en=now() WHERE id = p_id;

  SELECT count(*) FILTER (WHERE decision='conteo'), count(*) FILTER (WHERE decision='programa')
    INTO n_cont, n_sin FROM "GP2".relevamiento_item WHERE relevamiento_id = p_id;

  RETURN jsonb_build_object('id',p_id,'estado','contado','con_conteo',n_cont,'sin_conteo',n_sin);
END $$;

-- COMPARACION: programa vs conteo, con la diferencia. Ordena primero lo que NO coincide.
create or replace function "GP2".relevamiento_comparar(p_id bigint)
returns jsonb
language sql stable security definer set search_path = "GP2", public as $$
  select jsonb_build_object(
    'relevamiento', jsonb_build_object('id', r.id, 'estado', r.estado, 'fecha', r.fecha,
                                       'encargado', r.encargado, 'sector', s.nombre),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', ri.id, 'codigo', c.codigo, 'descripcion', c.descripcion,
        'unidad', c.unidad_medida,
        'conteo', ri.total_uni, 'programa', ri.stock_programa,
        'diferencia', (coalesce(ri.total_uni,0) - coalesce(ri.stock_programa,0)),
        'contado', ri.contado, 'decision', ri.decision,
        'coincide', (ri.total_uni IS NOT NULL AND ri.total_uni = ri.stock_programa)
      ) order by
          (case when ri.contado and ri.total_uni is distinct from ri.stock_programa then 0 else 1 end),
          abs(coalesce(ri.total_uni,0) - coalesce(ri.stock_programa,0)) desc,
          c.codigo)
      from "GP2".relevamiento_item ri
      join "GP2".componente c on c.id = ri.componente_id
      where ri.relevamiento_id = r.id
    ), '[]'::jsonb)
  )
  from "GP2".relevamiento r join "GP2".sector s on s.id = r.sector_id
  where r.id = p_id;
$$;

-- El usuario cambia quien gana en las filas que quiera.
-- p_items: [{"item_id":1,"decision":"programa"}, ...]
create or replace function "GP2".relevamiento_decidir(p_id bigint, p_items jsonb)
returns integer
language plpgsql security definer set search_path = "GP2", public as $$
DECLARE n int := 0;
BEGIN
  IF (SELECT estado FROM "GP2".relevamiento WHERE id=p_id) <> 'contado' THEN
    RAISE EXCEPTION 'El relevamiento % no esta en estado contado', p_id;
  END IF;
  WITH d AS (
    SELECT (x->>'item_id')::bigint item_id, x->>'decision' decision
    FROM jsonb_array_elements(p_items) x
  ), upd AS (
    UPDATE "GP2".relevamiento_item ri SET decision = d.decision
    FROM d WHERE ri.id = d.item_id AND ri.relevamiento_id = p_id
      AND d.decision IN ('conteo','programa')
      AND (d.decision = 'programa' OR (ri.contado AND ri.total_uni IS NOT NULL))
    RETURNING 1
  ) SELECT count(*) INTO n FROM upd;
  RETURN n;
END $$;

-- APLICAR: donde gana el conteo, deja el stock IGUAL al conteo.
-- El ajuste entra por GP2.movimiento (tipo 'ajuste', ubic_destino = la del sector, cantidad
-- CON SIGNO) y NO pisando inventario.cantidad: el motor vive en la BD (triggers
-- fn_movimiento_calc / fn_movimiento_aplicar) y asi el ajuste queda TRAZADO.
-- El delta se calcula contra el stock DE AHORA, no contra la foto: si algo se movio entre
-- el cierre y el aplicar, el resultado final sigue siendo exactamente lo contado.
create or replace function "GP2".relevamiento_aplicar(p_id bigint)
returns jsonb
language plpgsql security definer set search_path = "GP2", public as $$
DECLARE v_sector bigint; v_ubic bigint; v_estado text; n_mov int := 0;
BEGIN
  SELECT r.sector_id, r.estado INTO v_sector, v_estado FROM "GP2".relevamiento r WHERE r.id=p_id;
  IF v_sector IS NULL THEN RAISE EXCEPTION 'No existe el relevamiento %', p_id; END IF;
  IF v_estado <> 'contado' THEN RAISE EXCEPTION 'El relevamiento % esta %, no contado', p_id, v_estado; END IF;

  SELECT u.id INTO v_ubic FROM "GP2".ubicacion u
  WHERE u.tipo='sector' AND u.ref_id = v_sector LIMIT 1;
  IF v_ubic IS NULL THEN RAISE EXCEPTION 'El sector % no tiene ubicacion', v_sector; END IF;

  WITH cand AS (
    SELECT ri.componente_id, ri.total_uni,
           coalesce((SELECT i.cantidad FROM "GP2".inventario i
                     WHERE i.componente_id = ri.componente_id AND i.ubicacion_id = v_ubic
                     LIMIT 1), 0) AS stock_hoy,
           c.unidad_medida
    FROM "GP2".relevamiento_item ri
    JOIN "GP2".componente c ON c.id = ri.componente_id
    WHERE ri.relevamiento_id = p_id AND ri.decision = 'conteo' AND ri.total_uni IS NOT NULL
  ), ins AS (
    INSERT INTO "GP2".movimiento
      (fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad,
       unidad_origen, unidad_destino)
    SELECT now(), 'ajuste', cand.componente_id, NULL, v_ubic,
           (cand.total_uni - cand.stock_hoy), cand.unidad_medida, cand.unidad_medida
    FROM cand
    WHERE cand.total_uni <> cand.stock_hoy      -- si ya coincide, no se genera movimiento
    RETURNING 1
  ) SELECT count(*) INTO n_mov FROM ins;

  UPDATE "GP2".relevamiento SET estado='aplicado', aplicado_en=now() WHERE id=p_id;

  RETURN jsonb_build_object('id',p_id,'estado','aplicado','ajustes',n_mov);
END $$;

grant execute on function "GP2".relevamiento_cerrar(bigint)        to anon, authenticated;
grant execute on function "GP2".relevamiento_comparar(bigint)      to anon, authenticated;
grant execute on function "GP2".relevamiento_decidir(bigint,jsonb) to anon, authenticated;
grant execute on function "GP2".relevamiento_aplicar(bigint)       to anon, authenticated;

-- ============================================================================
-- VERIFICADO END-TO-END (2026-09-04, Sector Caja; datos de prueba BORRADOS):
--   abrir -> guardar (A1: 3 paq x25 + 10 = 85; A9: 2 x25 + 30 = 80) -> cerrar
--   -> comparar (A1 programa 1.120 vs conteo 85, dif -1.035, decision 'conteo' por default)
--   -> aplicar  -> A1 quedo en 85 con un ajuste de -1.035; A9 coincidia y NO genero
--                  movimiento; los 7 sin contar quedaron INTACTOS.
--   Restaurado despues: borrar el movimiento de ajuste revierte el inventario solo, porque
--   trg_movimiento_aplicar corre AFTER INSERT OR DELETE OR UPDATE. A1 volvio a 1.120.
--
-- FALTA: la pantalla (Relevamiento GP2 nativo). El backend esta completo.
-- ============================================================================

-- ============================================================================
-- DATOS QUE FALTAN (medido el 2026-09-04, NO se invento ninguno)
--   uni_x_cajon por sector:  Carton 0/110 y Caja 0/9  -> se resuelven por PARAMETRO
--     (carton_uni_x_paquete=250, pliego_uni_x_paquete=100, caja_uni_x_paquete=25).
--   Bombilla 8/12, Remache 14/33, Garage 9/10, Plastico 34/37 -> los que faltan quedan
--     con factor NULL y la pantalla los marca; NO se calcula un total inventado.
--   Fleje: 51/54 con kg_x_uni.
-- ============================================================================
