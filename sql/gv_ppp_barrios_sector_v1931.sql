-- =====================================================================================
-- gv_ppp_barrios_sector_v1931.sql — v19.31 · 2026-09-17 · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- Pedido de Thomas: "en la PPP hay siete zonas, pero ya las habíamos separado más, porque
-- por ejemplo Liniers y Núñez comparten una zona y eso estaría mal."
--
-- Lo que estaba: los 14 sectores de la v13.07 SÍ están activos (sectores_activos = 1) y
-- Núñez (H) con Liniers (C) daba `false`. Pero `gv_ppp_web_sector` devuelve
-- '~' || gv_ppp_web_grupo_zona(zona) cuando el barrio NO está en `GV_Barrios_Sector`, y
-- `gv_ppp_web_compat` comparaba ese GRUPO. El grupo 'Zonas 2+3' mete CABA Centro y CABA
-- Oeste en la misma bolsa, o sea que un barrio sin sector volvía a la regla vieja de 7
-- zonas. Medido el 17/09 ANTES del cambio:
--
--   compat(Núñez [H],  Floresta     [~Zonas 2+3]) = true
--   compat(Núñez [H],  Monte Castro [~Zonas 2+3]) = true
--   compat(Saavedra [~Zonas 2+3], Liniers  [C])   = true
--   compat(Saavedra [~Zonas 2+3], Mataderos[C])   = true
--   compat(Villa Maipú [~Zonas 6+7], Del Viso [~Zonas 6+7]) = true   -- 50 km
--
-- Eran 35 barrios de `Zonas_Barrios` (145) sin fila en `GV_Barrios_Sector` (109). En la
-- programación viva no había mordido todavía (los únicos sin sector programados son
-- Retira y Súper, que van solos), pero cualquier pedido de Saavedra, San Telmo, Floresta,
-- Monte Castro, Wilde, Haedo o Boulogne lo destapaba.
--
-- Qué hace este archivo:
--   1. Carga los 30 barrios con zona numérica que faltaban (los 5 restantes son Retira,
--      Súper y Expo: no tienen zona numérica, así que el sector no los mira).
--   2. Endurece el fallback: un barrio sin sector ahora se compara por la ZONA EXACTA,
--      no por el grupo. Sin esto, mañana entra un barrio nuevo y vuelve el mismo agujero.
--   3. Centinela `gv_ppp_barrios_sin_sector`: vacía = todo bien.
--
-- Impacto sobre Producción: ninguno. `GV_Barrios_Sector` y los `gv_*` son de Gestión;
-- Producción no los nombra. Backups: zz_backups."GV_Backup_BarriosSector_20260917" (109
-- filas, la tabla completa) y zz_backups."GV_Backup_FnSectorCompat_20260917" (el
-- CREATE de las dos funciones tal como estaban).
--
-- Rollback:
--   delete from public."GV_Barrios_Sector" where nota like 'v19.31:%';
--   -- y re-ejecutar los dos `def` guardados en GV_Backup_FnSectorCompat_20260917.
-- =====================================================================================

-- ── 1. Los 30 barrios que no tenían sector ───────────────────────────────────────────
insert into public."GV_Barrios_Sector" (barrio_norm, sector, nota) values
  ('abasto',            'F', 'v19.31: Abasto es Balvanera/Almagro'),
  ('chacarita',         'G', 'v19.31: pega con Colegiales y Villa Ortuzar'),
  ('congreso',          'F', 'v19.31: Balvanera/Monserrat'),
  ('saavedra',          'H', 'v19.31: pega con Nunez y Villa Urquiza'),
  ('san nicolas',       'F', 'v19.31: Microcentro'),
  ('san telmo',         'A', 'v19.31: pega con Constitucion y La Boca'),
  ('tribunales',        'F', 'v19.31: Microcentro/Retiro'),
  ('floresta',          'D', 'v19.31: pega con Flores'),
  ('monte castro',      'C', 'v19.31: pega con Liniers/Villa Luro/Versalles; en C no alcanza Nunez (C-H no son vecinos)'),
  ('villa santa rita',  'D', 'v19.31: pega con Flores; en D no alcanza Nunez (D-H no son vecinos)'),
  ('villa sta rita',    'D', 'v19.31: alias de Villa Santa Rita'),
  ('ezeiza',            'L', 'v19.31: pega con Monte Grande'),
  ('sarandi',           'J', 'v19.31: partido de Avellaneda'),
  ('wilde',             'J', 'v19.31: partido de Avellaneda'),
  ('haedo',             'M', 'v19.31: Zona 5 entera es el sector M'),
  ('isidro casanova',   'M', 'v19.31: Zona 5 entera es el sector M'),
  ('lomas del mirador', 'M', 'v19.31: Zona 5 entera es el sector M'),
  ('rafael castillo',   'M', 'v19.31: Zona 5 entera es el sector M'),
  ('santos lugares',    'M', 'v19.31: Zona 5 entera es el sector M'),
  ('virrey del pino',   'M', 'v19.31: Zona 5 entera es el sector M'),
  ('adolfo sordeaux',   'N', 'v19.31: Malvinas Argentinas, con Grand Bourg'),
  ('boulogne',          'P', 'v19.31: partido de San Isidro'),
  ('villa maipu',       'N', 'v19.31: partido de San Martin'),
  ('del viso',          'P', 'v19.31: partido de Pilar'),
  ('don torcuato',      'P', 'v19.31: partido de Tigre'),
  ('el triangulo',      'N', 'v19.31: Malvinas Argentinas, con Grand Bourg'),
  ('florida',           'P', 'v19.31: partido de Vicente Lopez'),
  ('grand bourg',       'N', 'v19.31: Malvinas Argentinas, con San Miguel/Jose C. Paz'),
  ('san fernando',      'P', 'v19.31: ribera norte'),
  ('virreyes',          'P', 'v19.31: partido de San Fernando')
on conflict (barrio_norm) do nothing;

-- ── 2. El fallback ya no usa el GRUPO de zona, usa la zona exacta ────────────────────
create or replace function public.gv_ppp_web_sector(p_zona text, p_barrio text, p_direccion text default null)
 returns text language sql stable set search_path to 'public','pg_temp'
as $function$
  -- v19.31: el fallback de un barrio sin sector ya NO es el grupo de zona ('Zonas 2+3'),
  -- que juntaba CABA Centro con CABA Oeste (Nunez con Floresta). Ahora es la zona EXACTA.
  select coalesce(
    case when coalesce(p_zona, '') ~ '^\s*Zona\s*[0-9]' then
      (select s.sector
         from public."GV_Barrios_Sector" s
         join public."GV_Sectores" g on g.sector = s.sector and g.activo
        where s.barrio_norm = public.gv_ppp_web_barrio_norm(p_barrio, p_direccion))
    end,
    '~' || coalesce(nullif(btrim(coalesce(p_zona,'')),''), '(sin zona)'));
$function$;

create or replace function public.gv_ppp_web_compat(p_zona_a text, p_sector_a text, p_barrio_a text,
                                                    p_zona_b text, p_sector_b text, p_barrio_b text)
 returns boolean language plpgsql stable set search_path to 'public','pg_temp'
as $function$
declare
  v_on  boolean := coalesce((select valor from public."PPP_Web_Config" where clave = 'sectores_activos'), 1) <> 0;
  v_ga  text := public.gv_ppp_web_grupo_zona(p_zona_a);
  v_gb  text := public.gv_ppp_web_grupo_zona(p_zona_b);
  v_par boolean;
begin
  if not v_on then
    return v_ga is not distinct from v_gb;
  end if;
  -- Los pares explicitos del dueno mandan sobre todo lo demas (incluso sobre el camion).
  if p_barrio_a is not null and p_barrio_b is not null and p_barrio_a <> p_barrio_b then
    select permitido into v_par from public."GV_Barrios_Pares"
     where barrio_a = least(p_barrio_a, p_barrio_b) and barrio_b = greatest(p_barrio_a, p_barrio_b);
    if found then return v_par; end if;
  end if;
  -- v18.28 (Luis): una tanda es de UN camion.
  if public.gv_ppp_web_camion(p_zona_a, p_sector_a)
     is distinct from public.gv_ppp_web_camion(p_zona_b, p_sector_b) then
    return false;
  end if;
  if p_sector_a is not distinct from p_sector_b then return true; end if;
  -- v19.31: barrio sin sector -> se compara la ZONA EXACTA, no el grupo. El grupo 'Zonas 2+3'
  -- dejaba pasar Nunez (CABA Centro) con Floresta/Monte Castro (CABA Oeste), que era justo
  -- lo que la tabla de sectores vino a impedir.
  if p_sector_a is null or p_sector_b is null or p_sector_a like '~%' or p_sector_b like '~%' then
    return btrim(coalesce(p_zona_a,'')) is not distinct from btrim(coalesce(p_zona_b,''));
  end if;
  return coalesce((select v.permitido from public."GV_Sectores_Vecinos" v
                    where v.sector_a = least(p_sector_a, p_sector_b)
                      and v.sector_b = greatest(p_sector_a, p_sector_b)), false);
end
$function$;

-- ── 3. Centinela: barrio con zona numerica y sin sector ──────────────────────────────
create or replace view public.gv_ppp_barrios_sin_sector as
select z.barrio_norm,
       z.zona,
       public.gv_ppp_web_camion(z.zona, null) camion_por_zona,
       (select count(*) from public."PPP_Web_Programacion" p
         where public.gv_ppp_web_barrio_norm(p.barrio, p.direccion) = z.barrio_norm
           and p.fecha_entrega >= current_date - 90) np_ultimos_90d
  from public."Zonas_Barrios" z
  left join public."GV_Barrios_Sector" s on s.barrio_norm = z.barrio_norm
 where z.zona ~ '^\s*Zona\s*[0-9]'
   and s.barrio_norm is null;
alter view public.gv_ppp_barrios_sin_sector set (security_invoker = true);
comment on view public.gv_ppp_barrios_sin_sector is 'v19.31 (centinela): barrio con zona numerica que NO tiene sector en GV_Barrios_Sector. Vacia = todo bien. Un barrio aca cae al fallback por zona exacta y no aprovecha los vecinos.';
grant select on public.gv_ppp_barrios_sin_sector to anon, authenticated;

-- ── 4. Verificacion (correr despues) ─────────────────────────────────────────────────
-- select * from public.gv_ppp_barrios_sin_sector;   -- vacia = todo bien
-- Medido el 17/09 DESPUES del cambio:
--   Nunez + Liniers      = false      Nunez + Floresta     = false
--   Nunez + Monte Castro = false      Nunez + Villa Lugano = false
--   Saavedra + Nunez     = true       Monte Castro + Liniers = true
--   Monte Castro + Devoto= true       Villa Santa Rita + Flores = true
--   Wilde + Avellaneda   = true       Grand Bourg + San Miguel  = true
