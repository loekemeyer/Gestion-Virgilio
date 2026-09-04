-- ══════════════════════════════════════════════════════════════════════════
-- Overrides de Gestión Virgilio — la fuente canónica PROPIA · 2026-09-04
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ══════════════════════════════════════════════════════════════════════════
-- POR QUÉ EXISTEN ESTAS TABLAS
-- ──────────────────────────────────────────────────────────────────────────
-- Gestión Virgilio y Producción Virgilio comparten proyecto Supabase y anon key.
-- Regla del dueño (2026-09-04): **sobre una tabla compartida se AGREGA, nunca se
-- MODIFICA lo que ya está.** Cuando Gestión necesita un valor DISTINTO al que ve
-- Producción, no se pisa la fila: va a una tabla `GV_*` y una vista la superpone.
--
-- Producción sigue leyendo su tabla original, intacta, y ni se entera.
--
-- Estas dos nacieron para DESHACER cuatro updates hechos el 2026-09-04 antes de
-- que la regla existiera (docs/SUPABASE-GESTION-VIRGILIO.md §3, A y B).
--
-- ── QUÉ HAY ADENTRO ───────────────────────────────────────────────────────
-- `GV_Volumen_Articulos` — 157 filas:
--   · 156 códigos con "L" con el m³ de su artículo base. Un código con L es el
--     MISMO artículo que su base (438EL es el 438E de Loekemeyer vendido por
--     Chef): misma caja, misma góndola, mismo lugar en el camión. La fila de
--     `Volumen_Articulos` dice otra cosa en 54 casos, y ocho de esos son la coma
--     corrida diez lugares justos (523L 0,0510 contra 523 0,0051 · 531L 0,0240
--     contra 531 0,0024 · 521L 0,0024 contra 521 0,0240 · 366EL 0,0016 contra
--     366E 0,0160). Son cargas mal tipeadas, pero corregirlas es de Producción.
--   · `727E` = 0,0023, **estimado por similitud y no medido**: 727EN "Sac Doble
--     Imp Reenv" (LK, 12 u/caja) equivale por descripción a 529E "Sacacorcho
--     Doble Impulso" y a 106E "Sac Doble Impluso Loke", los dos LK, los dos 12
--     u/caja y los dos 0,0023. Era el único código con L que quedaba sin m³.
--     ⚠ Reemplazar cuando se mida de verdad.
--
-- `GV_Zonas_Barrios` — 1 fila:
--   · `v.devoto` → Zona 2 - CABA Centro. Las tres grafías del mismo barrio
--     (`devoto`, `villa devoto`, `v.devoto`) se cargaron en el mismo momento y
--     v.devoto quedó en Oeste mientras las otras dos decían Centro. El dueño
--     confirmó Centro. Producción sigue viendo Oeste.
--
-- ── CÓMO SE CONSUMEN ──────────────────────────────────────────────────────
--   m³   → `vista_volumen_articulo_resuelto` (abajo): compartida + override.
--   zona → `gv_zona_de_barrio(barrio)`: override primero, después la compartida.
--
-- ── VERIFICADO ────────────────────────────────────────────────────────────
--   Gestión ve 439EL = 0,0185   ·  Producción ve 0,0561   (el original)
--   Gestión ve Devoto = Centro  ·  Producción ve Oeste    (el original)
--   Vista: 1.482 filas, 0 duplicados, 0 códigos con L que no sigan a su base.
--   LK lee las 1.482 por el FDW y el pipeline da 355 NP con 0 m³ incompleto.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public."GV_Volumen_Articulos" (
  codigo   text primary key,
  m3       numeric not null check (m3 > 0),
  motivo   text,
  creado   timestamptz not null default now()
);

create table if not exists public."GV_Zonas_Barrios" (
  barrio_norm text primary key,
  zona        text not null,
  motivo      text,
  creado      timestamptz not null default now()
);

alter table public."GV_Volumen_Articulos" enable row level security;
alter table public."GV_Zonas_Barrios"     enable row level security;

-- Lectura para todos (la app las necesita); escritura sólo supervisores, igual
-- reja que `PPP_Web_Programacion`. Ojo: la anon key es la MISMA que la de
-- Producción, así que sin RLS esto quedaría abierto a cualquiera.
create policy gv_vol_select on public."GV_Volumen_Articulos"
  for select to anon, authenticated using (true);
create policy gv_vol_write_sup on public."GV_Volumen_Articulos"
  for all to authenticated
  using      ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
  with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));
-- El lector del FDW de LK necesita su propia policy: la vista va con
-- security_invoker, así que lee como él y no como el dueño.
create policy gv_vol_select_lk_reader on public."GV_Volumen_Articulos"
  for select to lk_ppp_reader using (true);

create policy gv_zb_select on public."GV_Zonas_Barrios"
  for select to anon, authenticated using (true);
create policy gv_zb_write_sup on public."GV_Zonas_Barrios"
  for all to authenticated
  using      ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
  with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));

grant select on public."GV_Volumen_Articulos", public."GV_Zonas_Barrios" to anon, authenticated;
grant insert, update, delete on public."GV_Volumen_Articulos", public."GV_Zonas_Barrios" to authenticated;
grant select on public."GV_Volumen_Articulos" to lk_ppp_reader;

-- ──────────────────────────────────────────────────────────────────────────
create or replace function public.gv_zona_de_barrio(p_barrio text)
returns text language sql stable as $function$
  select coalesce(
    (select g.zona from public."GV_Zonas_Barrios" g
      where public._norm_barrio(g.barrio_norm) = public._norm_barrio(p_barrio) limit 1),
    (select z.zona from public."Zonas_Barrios" z
      where public._norm_barrio(z.barrio_norm) = public._norm_barrio(p_barrio) limit 1)
  );
$function$;
grant execute on function public.gv_zona_de_barrio(text) to anon, authenticated;

-- ── Controles ─────────────────────────────────────────────────────────────
--   -- Las dos apps ven cosas distintas, a propósito:
--   select (select m3 from public.vista_volumen_articulo_resuelto where codigo='439EL') as gestion,
--          (select m3 from public."Volumen_Articulos" where upper(trim(codigo))='439EL') as produccion;
--   select public.gv_zona_de_barrio('V.Devoto') as gestion,
--          (select zona from public."Zonas_Barrios" where barrio_norm='v.devoto') as produccion;
--
--   -- Qué está pisando Gestión y por qué:
--   select codigo, m3, motivo from public."GV_Volumen_Articulos" order by codigo;
--   select barrio_norm, zona, motivo from public."GV_Zonas_Barrios";
-- ══════════════════════════════════════════════════════════════════════════
