-- =====================================================================================
-- gv_sectores.sql — TANDAS POR CERCANÍA REAL: sectores + vecinos (idea 7317, v13.07)
-- 2026-09-05 sábado · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- Pedido del dueño: "Zonas pueden ir agrupadas también zona 1 y 2 … pero hay cosas que no
-- son parejas: Núñez con Villa Lugano estaría dentro de 1 y 2 y no debe ir junto."
-- Decisiones (AskUserQuestion, 2026-09-05): sectores + vecinos en tablas (backend);
-- Boedo va con Once/Almagro (Centro); Capital Sur puede compartir con Avellaneda/Lanús;
-- las zonas 1, 2 y 3 son automáticas.
--
-- Cómo funciona:
--   · `GV_Sectores`          — sector chico (A…P) con su etiqueta de camión (Capital, GBA
--                              Sur, GBA Oeste, GBA Norte). El camión decide el NÚMERO de la
--                              tanda (E01A = camión 01), no quién puede ir con quién.
--   · `GV_Barrios_Sector`    — barrio_norm (el mismo de `Zonas_Barrios`) → sector.
--   · `GV_Sectores_Vecinos`  — pares de sectores que pueden compartir tanda.
--   · `GV_Barrios_Pares`     — excepciones por barrio: `permitido=false` prohíbe aunque los
--                              sectores sean vecinos; `permitido=true` permite aunque no.
--   · `gv_ppp_web_compat(...)` decide si DOS paradas pueden ir en la misma tanda:
--       1. `sectores_activos = 0` → regla vieja (mismo grupo de zona: 'Zonas 2+3', 'Zonas 6+7').
--       2. par explícito de barrios → manda.
--       3. mismo sector → sí.
--       4. barrio desconocido (sector '~…') → regla vieja (mismo grupo de zona).
--       5. sectores vecinos con permitido → sí; si no → no.
--     Una tanda es una CLIQUE: el cliente entra sólo si es compatible con TODAS las
--     paradas que ya tiene la tanda.
--   · `ppp_web_armar_tandas` v4 (sql/ppp_web_tandas.sql) recorre los clientes por camión →
--     sector → m³ y los mete en la primera tanda abierta compatible (first-fit, prefiere
--     la que ya tiene una parada del mismo sector). Súper, `solo` y ≥ tope siguen solos.
--   · `gv_ppp_web_armar_simular(...)` = la misma función pero NO persiste nada (corre y
--     hace rollback): sirve para probar con filas sintéticas.
--
-- Interruptor (todo reversible en el momento, sin redeploy):
--   update public."PPP_Web_Config" set valor = 0 where clave = 'sectores_activos';  -- vuelve a la regla vieja
--   update public."PPP_Web_Config" set valor_texto = '1,2' where clave = 'zonas_automaticas'; -- zona 3 a mano otra vez
--
-- Impacto sobre Producción: ninguno. Tablas/funciones nuevas con prefijo GV_/gv_; la única
-- función que cambia (`ppp_web_armar_tandas`) es de Gestión (Producción no la llama).
-- =====================================================================================

-- ── 1. Tablas ─────────────────────────────────────────────────────────────────────────
create table if not exists public."GV_Sectores" (
  sector  text primary key,
  nombre  text not null,
  camion  text not null,            -- 'Capital' · 'GBA Sur' · 'GBA Oeste' · 'GBA Norte'
  orden   int  not null default 0,
  activo  boolean not null default true,
  creado  timestamptz not null default now()
);
comment on table public."GV_Sectores" is 'v13.07 (idea 7317): sectores chicos para armar tandas por cercanía. camion = etiqueta que numera la tanda.';

create table if not exists public."GV_Barrios_Sector" (
  barrio_norm text primary key,     -- public._norm_barrio(...) del barrio (misma clave que Zonas_Barrios)
  sector      text not null references public."GV_Sectores"(sector),
  nota        text,
  creado      timestamptz not null default now()
);
comment on table public."GV_Barrios_Sector" is 'v13.07: barrio (normalizado con _norm_barrio) → sector de GV_Sectores.';

create table if not exists public."GV_Sectores_Vecinos" (
  sector_a  text not null references public."GV_Sectores"(sector),
  sector_b  text not null references public."GV_Sectores"(sector),
  permitido boolean not null default true,
  nota      text,
  primary key (sector_a, sector_b),
  check (sector_a < sector_b)
);
comment on table public."GV_Sectores_Vecinos" is 'v13.07: pares de sectores que pueden compartir tanda (sector_a < sector_b).';

create table if not exists public."GV_Barrios_Pares" (
  barrio_a  text not null,
  barrio_b  text not null,
  permitido boolean not null default false,
  motivo    text,
  creado    timestamptz not null default now(),
  primary key (barrio_a, barrio_b),
  check (barrio_a < barrio_b)
);
comment on table public."GV_Barrios_Pares" is 'v13.07: excepciones por barrio (barrio_a < barrio_b, normalizados): false = nunca juntos aunque los sectores sean vecinos; true = juntos aunque no lo sean.';

-- RLS: mismo patrón que PPP_Web_Base — todos leen, escriben los tres mails de supervisor.
do $rls$
declare t text;
begin
  foreach t in array array['GV_Sectores','GV_Barrios_Sector','GV_Sectores_Vecinos','GV_Barrios_Pares'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', lower(t) || '_select', t);
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', lower(t) || '_select', t);
    execute format('drop policy if exists %I on public.%I', lower(t) || '_write_sup', t);
    execute format($p$create policy %I on public.%I for all to authenticated
      using ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
      with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))$p$,
      lower(t) || '_write_sup', t);
    execute format('grant select on public.%I to anon, authenticated', t);
    execute format('grant insert, update, delete on public.%I to authenticated', t);
  end loop;
end
$rls$;

-- ── 2. Semilla ────────────────────────────────────────────────────────────────────────
-- Sectores. Letras sin I ni O (se confunden con 1 y 0). `orden` = barrido geográfico:
-- Capital de sur a norte, después GBA Sur, Oeste, Norte.
insert into public."GV_Sectores" (sector, nombre, camion, orden) values
  ('A', 'Capital Sur-Este · Barracas, Constitución, La Boca, Parque Patricios, San Cristóbal', 'Capital',   1),
  ('B', 'Capital Sur · Lugano, Soldati, Pompeya, Villa Riachuelo',                              'Capital',   2),
  ('C', 'Capital Oeste-Sur · Mataderos, Parque Avellaneda, Liniers, Villa Luro',               'Capital',   3),
  ('D', 'Capital Centro-Oeste · Flores, Parque Chacabuco, Caballito',                          'Capital',   4),
  ('E', 'Capital Oeste-Norte · Villa del Parque, Devoto, Villa Gral. Mitre, Paternal',         'Capital',   5),
  ('F', 'Capital Centro · Once, Balvanera, Almagro, Boedo, Monserrat, Microcentro, Puerto Madero, Retiro, Recoleta', 'Capital', 6),
  ('G', 'Capital Norte Palermo · Palermo, Villa Crespo, Colegiales, Villa Ortúzar',            'Capital',   7),
  ('H', 'Capital Norte Belgrano · Belgrano, Núñez, Villa Urquiza, Villa Pueyrredón',           'Capital',   8),
  ('J', 'GBA Sur cercano · Avellaneda, Lanús, Valentín Alsina, Remedios de Escalada',          'GBA Sur',   9),
  ('K', 'GBA Sur Quilmes · Bernal, Quilmes, Berazategui, Florencio Varela, Plátanos',          'GBA Sur',  10),
  ('L', 'GBA Sur Lomas · Lomas de Zamora, Banfield, Temperley, Adrogué, Burzaco, Monte Grande, Longchamps, R. Calzada, Guernica', 'GBA Sur', 11),
  ('M', 'GBA Oeste · toda la Zona 5',                                                          'GBA Oeste', 12),
  ('N', 'GBA Norte San Martín · San Martín, V. Ballester, Munro, V. Adelina, San Miguel, José C. Paz, Bella Vista', 'GBA Norte', 13),
  ('P', 'GBA Norte Ribera · Vicente López, Olivos, Martínez, San Isidro, Tigre, Pilar, Garín', 'GBA Norte', 14)
on conflict (sector) do nothing;

-- Barrio → sector. Las claves son las de `Zonas_Barrios.barrio_norm` (incluidas las
-- variantes 'p. patricios', 'v.devoto', 'mataderos (8:30 a 14)', …). Pasan por
-- _norm_barrio para que coincidan con lo que resuelve `gv_ppp_web_barrio_norm`.
insert into public."GV_Barrios_Sector" (barrio_norm, sector)
select public._norm_barrio(b), s from (values
  ('barracas','A'), ('constitucion','A'), ('la boca','A'), ('p. patricios','A'), ('p.patricios','A'), ('parque patricios','A'), ('san cristobal','A'),
  ('lugano','B'), ('nueva pompeya','B'), ('pompeya','B'), ('soldati','B'), ('villa lugano','B'), ('villa riachuelo','B'), ('villa soldati','B'),
  ('mataderos','C'), ('mataderos (8:30 a 14)','C'), ('parque avellaneda','C'), ('liniers','C'), ('villa luro','C'),
  ('flores','D'), ('parque chacabuco','D'), ('caballito','D'),
  ('villa del parque','E'), ('devoto','E'), ('v.devoto','E'), ('villa devoto','E'), ('villa general mitre','E'), ('paternal','E'),
  ('once','F'), ('balvanera','F'), ('almagro','F'), ('boedo','F'), ('monserrat','F'), ('micro centro','F'), ('microcentro','F'), ('puerto madero','F'), ('retiro','F'), ('recoleta','F'),
  ('palermo','G'), ('villa crespo','G'), ('colegiales','G'), ('villa ortuzar','G'),
  ('belgrano','H'), ('nuñez','H'), ('villa urquiza','H'), ('villa pueyrredon','H'),
  ('avellaneda','J'), ('lanus','J'), ('lanus este','J'), ('lanus oeste','J'), ('v.alsina','J'), ('valentin alsina','J'), ('remedios de escalada','J'),
  ('bernal','K'), ('quilmes','K'), ('quilmes oeste','K'), ('berazategui','K'), ('f.varela','K'), ('florencio varela','K'), ('platanos','K'),
  ('lomas de zamora','L'), ('banfield','L'), ('temperley','L'), ('adrogue','L'), ('burzaco','L'), ('monte grande','L'), ('longchamps','L'), ('rafael calzada','L'), ('guernica','L'),
  ('caseros','M'), ('castelar','M'), ('ciudadela','M'), ('gonzalez catan','M'), ('gregorio de laferrere','M'), ('hurlingham','M'), ('ituzaingo','M'), ('laferrere','M'), ('lujan','M'), ('mercado central','M'), ('merlo','M'), ('moreno','M'), ('moron','M'), ('palomar','M'), ('ramos mejia','M'), ('san antonio de padua','M'), ('san justo','M'), ('v.bosch','M'), ('villa sarmiento','M'),
  ('bella vista','N'), ('chilavert','N'), ('jose c paz','N'), ('jose c. paz','N'), ('jose leon suarez','N'), ('muñiz','N'), ('munro','N'), ('san martin','N'), ('san miguel','N'), ('v. maipu - san martin','N'), ('villa adelina','N'), ('villa ballester','N'), ('villa bosch','N'), ('villa lynch','N'),
  ('martinez','P'), ('olivos','P'), ('vicente lopez','P'), ('san isidro','P'), ('tigre','P'), ('pilar','P'), ('garin','P')
) v(b, s)
on conflict (barrio_norm) do nothing;

-- Vecinos (sector_a < sector_b). Lo que NO está acá no comparte tanda.
insert into public."GV_Sectores_Vecinos" (sector_a, sector_b, nota) values
  ('A','B', 'Barracas/P. Patricios pegan con Pompeya'),
  ('A','D', 'P. Patricios – P. Chacabuco/Caballito'),
  ('A','F', 'Constitución/San Cristóbal – Monserrat/Once/Boedo'),
  ('A','J', 'Capital Sur – Avellaneda/Lanús por el puente (dueño 2026-09-05)'),
  ('B','C', 'Lugano/Soldati – Mataderos/P. Avellaneda'),
  ('B','D', 'Pompeya – P. Chacabuco/Flores'),
  ('B','J', 'Lugano/Pompeya – V. Alsina/Lanús por el Riachuelo (dueño 2026-09-05)'),
  ('C','D', 'Mataderos/Liniers – Flores'),
  ('C','E', 'Liniers/V. Luro – V. del Parque/Devoto'),
  ('C','M', 'Liniers/Mataderos – Ciudadela/Ramos Mejía'),
  ('D','E', 'Flores/Caballito – Paternal/V. Gral. Mitre'),
  ('D','F', 'Caballito – Almagro/Boedo'),
  ('D','G', 'Caballito – Villa Crespo'),
  ('E','G', 'Paternal – Villa Crespo/Colegiales'),
  ('E','H', 'V. del Parque/Devoto – V. Pueyrredón/V. Urquiza'),
  ('E','M', 'Devoto – Ciudadela/Caseros'),
  ('E','N', 'Devoto – Villa Lynch/San Martín'),
  ('F','G', 'Almagro/Recoleta – Palermo/Villa Crespo'),
  ('F','H', 'Recoleta/Retiro – Belgrano por Libertador'),
  ('G','H', 'Palermo/Colegiales – Belgrano/Núñez'),
  ('H','N', 'V. Pueyrredón/V. Urquiza – San Martín/V. Ballester'),
  ('H','P', 'Belgrano/Núñez – Vicente López/Olivos'),
  ('J','K', 'Avellaneda/Lanús – Bernal/Quilmes'),
  ('J','L', 'Lanús/R. de Escalada – Banfield/Lomas'),
  ('K','L', 'Quilmes – Alte. Brown'),
  ('M','N', 'Caseros/Hurlingham – San Martín/San Miguel'),
  ('N','P', 'Munro/V. Adelina – Vicente López/San Isidro')
on conflict (sector_a, sector_b) do nothing;

-- Excepciones por barrio. Los NO de Núñez/Belgrano/Colegiales con Lugano/Soldati/Pompeya
-- ya salen de los sectores (H/G no son vecinos de B); quedan explícitos para que un cambio
-- de vecinos no los vuelva a juntar (dueño: "Núñez con Villa Lugano no debe ir junto").
insert into public."GV_Barrios_Pares" (barrio_a, barrio_b, permitido, motivo)
select least(public._norm_barrio(a), public._norm_barrio(b)), greatest(public._norm_barrio(a), public._norm_barrio(b)), false,
       'Norte y Sur de Capital nunca juntos (dueño 2026-09-05)'
  from (values ('nuñez'), ('belgrano'), ('colegiales')) n(a)
 cross join (values ('lugano'), ('villa lugano'), ('soldati'), ('villa soldati'), ('pompeya'), ('nueva pompeya')) s(b)
on conflict (barrio_a, barrio_b) do nothing;
-- Boedo quedó en Centro por decisión del dueño, pero pega con Pompeya por Sáenz: se
-- permite ese par (la tanda Boedo+Pompeya no admite después Once, porque Once–Pompeya no).
insert into public."GV_Barrios_Pares" (barrio_a, barrio_b, permitido, motivo)
select least(public._norm_barrio(a), public._norm_barrio(b)), greatest(public._norm_barrio(a), public._norm_barrio(b)), true,
       'Boedo pega con Pompeya (Av. Sáenz) aunque el sector sea Centro'
  from (values ('boedo','pompeya'), ('boedo','nueva pompeya'), ('boedo','parque patricios'), ('boedo','p. patricios'), ('boedo','p.patricios')) v(a, b)
on conflict (barrio_a, barrio_b) do nothing;

-- Config: interruptor y zona 3 al automático (dueño 2026-09-05: "Sí, 1, 2 y 3 automáticas").
insert into public."PPP_Web_Config" (clave, valor, descripcion)
values ('sectores_activos', 1, 'v13.07 (idea 7317): 1 = las tandas se arman por sectores + vecinos (GV_Sectores*); 0 = regla vieja por grupo de zona (1 / 2+3 / 4 / 5 / 6+7).')
on conflict (clave) do nothing;
update public."PPP_Web_Config"
   set valor_texto = '1,2,3', actualizado = now(),
       descripcion = coalesce(descripcion, '') || ' · v13.07: zona 3 automática (dueño 2026-09-05).'
 where clave = 'zonas_automaticas' and coalesce(valor_texto, '') = '1,2';

-- ── 3. Funciones ──────────────────────────────────────────────────────────────────────
-- Barrio normalizado con el que se busca en GV_Barrios_Sector / GV_Barrios_Pares.
-- El `barrio` que manda la Edge Function es crudo: zona_expreso, o la localidad, o la
-- DIRECCIÓN entera cuando no hay otra cosa (`barrioCrudo()`), así que se prueba el texto
-- tal cual, después el barrio parseado de ese texto y por último el de la dirección.
create or replace function public.gv_ppp_web_barrio_norm(p_barrio text, p_direccion text default null)
returns text
language sql
stable
set search_path = public, pg_temp
as $function$
  with c as (
    select 1 as ord, public._norm_barrio(p_barrio) as b
    union all select 2, public._norm_barrio(public.gv_ppp_web_barrio_de(p_barrio))
    union all select 3, public._norm_barrio(public.gv_ppp_web_barrio_de(p_direccion))
  )
  select coalesce(
    (select c.b from c
      where c.b <> '' and exists (select 1 from public."GV_Barrios_Sector" s where s.barrio_norm = c.b)
      order by c.ord limit 1),
    nullif(public._norm_barrio(p_barrio), ''));
$function$;

-- Sector de una parada. Si la zona no es 'Zona N' (Retira, Super, Expo, sin zona) o el
-- barrio no está en la tabla, devuelve un pseudo-sector '~<grupo de zona>' para que
-- `gv_ppp_web_compat` caiga en la regla vieja.
create or replace function public.gv_ppp_web_sector(p_zona text, p_barrio text, p_direccion text default null)
returns text
language sql
stable
set search_path = public, pg_temp
as $function$
  select coalesce(
    case when coalesce(p_zona, '') ~ '^\s*Zona\s*[0-9]' then
      (select s.sector
         from public."GV_Barrios_Sector" s
         join public."GV_Sectores" g on g.sector = s.sector and g.activo
        where s.barrio_norm = public.gv_ppp_web_barrio_norm(p_barrio, p_direccion))
    end,
    '~' || coalesce(public.gv_ppp_web_grupo_zona(p_zona), '(sin zona)'));
$function$;

-- Etiqueta de camión (numera la tanda): la del sector; si no hay sector, por zona.
create or replace function public.gv_ppp_web_camion(p_zona text, p_sector text)
returns text
language sql
stable
set search_path = public, pg_temp
as $function$
  select coalesce(
    (select g.camion from public."GV_Sectores" g where g.sector = p_sector),
    case (regexp_match(coalesce(p_zona, ''), '^\s*Zona\s*([0-9]+)'))[1]
      when '1' then 'Capital' when '2' then 'Capital' when '3' then 'Capital'
      when '4' then 'GBA Sur' when '5' then 'GBA Oeste'
      when '6' then 'GBA Norte' when '7' then 'GBA Norte'
      else coalesce(public.gv_ppp_web_grupo_zona(p_zona), '(sin zona)')
    end);
$function$;

-- ¿Pueden ir dos paradas en la misma tanda? (núcleo; recibe sector y barrio ya resueltos)
create or replace function public.gv_ppp_web_compat(
  p_zona_a text, p_sector_a text, p_barrio_a text,
  p_zona_b text, p_sector_b text, p_barrio_b text)
returns boolean
language plpgsql
stable
set search_path = public, pg_temp
as $function$
declare
  v_on  boolean := coalesce((select valor from public."PPP_Web_Config" where clave = 'sectores_activos'), 1) <> 0;
  v_ga  text := public.gv_ppp_web_grupo_zona(p_zona_a);
  v_gb  text := public.gv_ppp_web_grupo_zona(p_zona_b);
  v_par boolean;
begin
  -- 1. interruptor apagado → regla vieja: mismo grupo de zona
  if not v_on then
    return v_ga is not distinct from v_gb;
  end if;
  -- 2. par explícito de barrios manda
  if p_barrio_a is not null and p_barrio_b is not null and p_barrio_a <> p_barrio_b then
    select permitido into v_par from public."GV_Barrios_Pares"
     where barrio_a = least(p_barrio_a, p_barrio_b) and barrio_b = greatest(p_barrio_a, p_barrio_b);
    if found then return v_par; end if;
  end if;
  -- 3. mismo sector
  if p_sector_a is not distinct from p_sector_b then return true; end if;
  -- 4. alguno sin sector (barrio desconocido, Retira, Super…) → regla vieja
  if p_sector_a is null or p_sector_b is null or p_sector_a like '~%' or p_sector_b like '~%' then
    return v_ga is not distinct from v_gb;
  end if;
  -- 5. vecinos
  return coalesce((select v.permitido from public."GV_Sectores_Vecinos" v
                    where v.sector_a = least(p_sector_a, p_sector_b)
                      and v.sector_b = greatest(p_sector_a, p_sector_b)), false);
end
$function$;

-- Versión cómoda: resuelve sector y barrio y llama al núcleo.
create or replace function public.gv_ppp_web_pueden_compartir(
  p_zona_a text, p_barrio_a text, p_zona_b text, p_barrio_b text,
  p_dir_a text default null, p_dir_b text default null)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $function$
  select public.gv_ppp_web_compat(
    p_zona_a, public.gv_ppp_web_sector(p_zona_a, p_barrio_a, p_dir_a), public.gv_ppp_web_barrio_norm(p_barrio_a, p_dir_a),
    p_zona_b, public.gv_ppp_web_sector(p_zona_b, p_barrio_b, p_dir_b), public.gv_ppp_web_barrio_norm(p_barrio_b, p_dir_b));
$function$;

grant execute on function public.gv_ppp_web_barrio_norm(text, text) to anon, authenticated;
grant execute on function public.gv_ppp_web_sector(text, text, text) to anon, authenticated;
grant execute on function public.gv_ppp_web_camion(text, text) to anon, authenticated;
grant execute on function public.gv_ppp_web_compat(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.gv_ppp_web_pueden_compartir(text, text, text, text, text, text) to anon, authenticated;

-- ── 4. `ppp_web_armar_tandas` v4 ──────────────────────────────────────────────────────
-- Vive en sql/ppp_web_tandas.sql (misma firma; con `sectores_activos = 1` usa el bucle
-- por sectores, con 0 el bucle viejo, línea por línea). Aplicar ese archivo después de éste.

-- ── 5. Simulador: corre el armado y lo deshace ────────────────────────────────────────
-- Devuelve {sectores_activos, tandas:[{tanda,zona,np,m3,clientes}], detalle:[{tanda,np,
-- cliente,zona,barrio,sector,m3}]} sin dejar nada en PPP_Web_Programacion. El truco es
-- un bloque con excepción propia (GVS01): las variables plpgsql sobreviven al rollback
-- del bloque, las tablas no.
create or replace function public.gv_ppp_web_armar_simular(
  p_empresa text,
  p_fecha date default current_date,
  p_filas jsonb default '[]'::jsonb,
  p_forzar_cods text[] default '{}')
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  v_out jsonb := '{}'::jsonb;
begin
  begin
    select jsonb_build_object(
             'sectores_activos', coalesce((select valor from public."PPP_Web_Config" where clave = 'sectores_activos'), 1) <> 0,
             'tandas', coalesce((
               select jsonb_agg(jsonb_build_object('tanda', t.r_tanda, 'zona', t.r_zona, 'np', t.r_np_count,
                                                   'm3', t.r_m3, 'clientes', t.r_clientes) order by t.r_tanda)
                 from public.ppp_web_armar_tandas(p_empresa, p_fecha, p_filas, p_forzar_cods) t), '[]'::jsonb))
      into v_out;
    v_out := v_out || jsonb_build_object('detalle', coalesce((
      select jsonb_agg(jsonb_build_object('tanda', a.tanda, 'np', s.np, 'cliente', s.cliente,
                                          'razon_social', s.razon_social, 'zona', s.zona, 'barrio', s.barrio,
                                          'sector', s.sector, 'm3', s.m3) order by a.tanda, s.cliente, s.np_idx)
        from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx), '[]'::jsonb));
    raise exception using errcode = 'GVS01', message = 'GV_SIMULACION';
  exception
    when sqlstate 'GVS01' then return v_out;
  end;
end
$function$;
grant execute on function public.gv_ppp_web_armar_simular(text, date, jsonb, text[]) to authenticated;

-- ── Rollback completo ─────────────────────────────────────────────────────────────────
--   update public."PPP_Web_Config" set valor = 0 where clave = 'sectores_activos';
--   update public."PPP_Web_Config" set valor_texto = '1,2' where clave = 'zonas_automaticas';
--   -- (y si se quiere sacar todo:)
--   drop function if exists public.gv_ppp_web_armar_simular(text, date, jsonb, text[]);
--   -- restaurar ppp_web_armar_tandas desde sql/backups/ppp_web_armar_tandas_20260905_pre_sectores.sql
--   drop function if exists public.gv_ppp_web_pueden_compartir(text, text, text, text, text, text);
--   drop function if exists public.gv_ppp_web_compat(text, text, text, text, text, text);
--   drop function if exists public.gv_ppp_web_camion(text, text);
--   drop function if exists public.gv_ppp_web_sector(text, text, text);
--   drop function if exists public.gv_ppp_web_barrio_norm(text, text);
--   drop table if exists public."GV_Barrios_Pares", public."GV_Sectores_Vecinos", public."GV_Barrios_Sector", public."GV_Sectores";
--   delete from public."PPP_Web_Config" where clave = 'sectores_activos';
