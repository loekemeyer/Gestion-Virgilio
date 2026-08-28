-- canon_cod_art_extendido.sql — TOP-2 de la auditoría de datos duplicados (idea 7411)
--
-- Extiende la canonicalización de cod_art (que hoy solo vive en el trigger de
-- Movimientos_Stock) a TODAS las tablas que guardan códigos de artículo.
--
-- Regla del dueño: el código ES con cero adelante (026, 029, 034…).
-- La canonización va HACIA la forma con cero, nunca sacándolo.
-- OC_Maximos es la fuente de verdad del código canónico.
--
-- NO toca: Movimientos_Stock (ya tiene su trigger fn_canon_cod_art),
-- Planimetria/Racks_Planimetria (llevan sufijo " LK"/" CH" — van en TOP-3),
-- precios_venta/cob_uxb_lk/precios_venta_chef (synced desde LK, códigos vienen de products.cod).
--
-- APLICADO 2026-08-28.

-- =========================================================================
-- 0) Índice funcional en OC_Maximos para lookup rápido
-- =========================================================================
-- Sin esto, cada INSERT con trigger hace un seq scan de OC_Maximos (~500 filas).
-- Con el índice, es un index scan O(log n).
create index if not exists idx_oc_maximos_norm_key
  on public."OC_Maximos" (regexp_replace(upper(btrim(cod)), '^0+(?=.)', ''))
  where activo;

-- =========================================================================
-- 1) Función standalone: canon_cod_art_val(text) → text
-- =========================================================================
-- Devuelve la forma canónica del código de artículo:
--   1. upper + btrim
--   2. Busca en OC_Maximos (la fuente de verdad) por clave normalizada
--   3. Fallback numérico: lpad a 3 dígitos (027, no 27)
--   4. Fallback alfanumérico: upper+btrim tal cual
--
-- STABLE (lee OC_Maximos). PARALLEL SAFE.
-- No confundir con norm_cod/canon_cod/cob_norm_cod, que QUITAN ceros (solo para comparar).
create or replace function public.canon_cod_art_val(p_cod text)
returns text
language plpgsql
stable
parallel safe
as $$
declare
  trimmed text;
  k text;
  c text;
begin
  if p_cod is null then return null; end if;

  trimmed := upper(btrim(p_cod));
  if trimmed = '' then return ''; end if;

  k := regexp_replace(trimmed, '^0+(?=.)', '');

  select o.cod into c
    from public."OC_Maximos" o
   where o.activo
     and regexp_replace(upper(btrim(o.cod)), '^0+(?=.)', '') = k
   limit 1;

  if c is not null then
    return c;
  elsif trimmed ~ '^[0-9]+$' then
    return case when length(k) >= 3 then k else lpad(k, 3, '0') end;
  else
    return trimmed;
  end if;
end;
$$;

comment on function public.canon_cod_art_val(text) is
$c$Forma canónica de un código de artículo (con cero adelante: 026, no 26).
Busca en OC_Maximos; fallback: pad numéricos a 3 dígitos, alfanuméricos upper+trim.
STABLE (lee OC_Maximos). Solo para comparar/normalizar, usar norm_cod/canon_cod.$c$;

revoke execute on function public.canon_cod_art_val(text) from public, anon, authenticated;
grant execute on function public.canon_cod_art_val(text) to service_role;

-- =========================================================================
-- 2) Trigger functions — una por nombre de columna distinto
-- =========================================================================

-- 2a) Para columnas llamadas "cod_art"
create or replace function public.fn_canon_col_cod_art()
returns trigger language plpgsql as $$
begin
  NEW.cod_art := public.canon_cod_art_val(NEW.cod_art);
  return NEW;
end;
$$;

-- 2b) Para columnas llamadas "cod"
create or replace function public.fn_canon_col_cod()
returns trigger language plpgsql as $$
begin
  NEW.cod := public.canon_cod_art_val(NEW.cod);
  return NEW;
end;
$$;

-- 2c) Para columnas llamadas "Cod_Art" (quoted, mixed case — Articulos_Cajas)
create or replace function public.fn_canon_col_cod_art_quoted()
returns trigger language plpgsql as $$
begin
  NEW."Cod_Art" := public.canon_cod_art_val(NEW."Cod_Art");
  return NEW;
end;
$$;

-- 2d) Para columnas llamadas "codigo"
create or replace function public.fn_canon_col_codigo()
returns trigger language plpgsql as $$
begin
  NEW.codigo := public.canon_cod_art_val(NEW.codigo);
  return NEW;
end;
$$;

-- 2e) Para columnas llamadas "articulo" (PPP_Base_Pedidos — opcional, volumen alto)
create or replace function public.fn_canon_col_articulo()
returns trigger language plpgsql as $$
begin
  NEW.articulo := public.canon_cod_art_val(NEW.articulo);
  return NEW;
end;
$$;

-- =========================================================================
-- 3) Triggers en las tablas target
-- =========================================================================

-- Entregas_Virgilio (cod_art) — 21 non-canonical encontrados
create or replace trigger trg_canon_entregas_cod_art
  before insert or update of cod_art on public."Entregas_Virgilio"
  for each row execute function public.fn_canon_col_cod_art();

-- Faltantes_Notas (cod) — 2 non-canonical
create or replace trigger trg_canon_faltantes_notas_cod
  before insert or update of cod on public."Faltantes_Notas"
  for each row execute function public.fn_canon_col_cod();

-- Articulos_Cajas ("Cod_Art") — 19 non-canonical (todos zeros faltantes)
create or replace trigger trg_canon_articulos_cajas_cod
  before insert or update of "Cod_Art" on public."Articulos_Cajas"
  for each row execute function public.fn_canon_col_cod_art_quoted();

-- Capacidad_Sector (cod) — 1 non-canonical
create or replace trigger trg_canon_capacidad_sector_cod
  before insert or update of cod on public."Capacidad_Sector"
  for each row execute function public.fn_canon_col_cod();

-- Volumen_Articulos (codigo) — 0 non-canonical pero previene futuros
create or replace trigger trg_canon_volumen_articulos_cod
  before insert or update of codigo on public."Volumen_Articulos"
  for each row execute function public.fn_canon_col_codigo();

-- Importados (cod_art)
create or replace trigger trg_canon_importados_cod
  before insert or update of cod_art on public."Importados"
  for each row execute function public.fn_canon_col_cod_art();

-- Importados_Volumen (cod)
create or replace trigger trg_canon_importados_vol_cod
  before insert or update of cod on public."Importados_Volumen"
  for each row execute function public.fn_canon_col_cod();

-- Envasar_Ubicaciones (cod_art)
create or replace trigger trg_canon_envasar_ubicaciones_cod
  before insert or update of cod_art on public."Envasar_Ubicaciones"
  for each row execute function public.fn_canon_col_cod_art();

-- Articulos_Discontinuados (cod)
create or replace trigger trg_canon_articulos_disc_cod
  before insert or update of cod on public."Articulos_Discontinuados"
  for each row execute function public.fn_canon_col_cod();

-- Codigos_Duales (cod)
create or replace trigger trg_canon_codigos_duales_cod
  before insert or update of cod on public."Codigos_Duales"
  for each row execute function public.fn_canon_col_cod();

-- =========================================================================
-- 4) Backfill: corregir los registros existentes no canónicos
-- =========================================================================
-- Total: 143 filas en 4 tablas.
-- Entregas_Virgilio 21, Faltantes_Notas 2, Articulos_Cajas 64, Capacidad_Sector 56.

-- 4a) Entregas_Virgilio — 21 filas (lowercase 943e→943E, zeros 66→066)
update public."Entregas_Virgilio"
   set cod_art = public.canon_cod_art_val(cod_art)
 where cod_art is not null
   and cod_art <> public.canon_cod_art_val(cod_art);

-- 4b) Faltantes_Notas — 2 filas
update public."Faltantes_Notas"
   set cod = public.canon_cod_art_val(cod)
 where cod is not null
   and cod <> public.canon_cod_art_val(cod);

-- 4c) Articulos_Cajas — 64 filas (zeros: 26→026, 43→043, 1→001, etc.)
update public."Articulos_Cajas"
   set "Cod_Art" = public.canon_cod_art_val("Cod_Art")
 where "Cod_Art" is not null
   and "Cod_Art" <> public.canon_cod_art_val("Cod_Art");

-- 4d) Capacidad_Sector — 56 filas (55× Libre→LIBRE, 1× 538e→538E)
update public."Capacidad_Sector"
   set cod = public.canon_cod_art_val(cod)
 where cod is not null
   and cod <> public.canon_cod_art_val(cod);

-- 4e) PPP_Base_Pedidos — 1 fila
-- Se omite: la tabla se reemplaza por completo cada 5 min (TRUNCATE+INSERT
-- del sync server-side). El trigger existente ya hace upper+btrim; la única
-- fila non-canonical se corrige en el próximo ciclo.
