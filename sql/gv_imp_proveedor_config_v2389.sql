-- ══════════════════════════════════════════════════════════════════════════════
-- v23.89 — IMPORTADOS: la configuración por proveedor vive en TABLAS, no en el front
-- Pedido de Luis, 2026-09-29:
--   "en la parte de OCs se pueden modificar cosas que son pertinentes de importados
--    que estarían mejor en su módulo. Me gustaría que la capacidad de editar cosas
--    como meses objetivo de importados esté editable en cada proveedor de importados
--    (un botón al lado del nombre … 'Configurar parámetros') … así como agregarle/
--    sacarle códigos de los ya existentes"
--   "Fijate que no vivan en el front los datos, sino que modifiquen las tablas pertinentes"
--
-- ── Lo que ESTABA HARDCODEADO en index.html y ahora vive acá ──────────────────
--   _IMPORTADOR_DE      (línea ~21080) → GV_Imp_Proveedor.importador
--   _NTL_PROVEEDORES    (~21085)       → GV_Imp_Proveedor.usa_ntl
--   _DERECHOS_PROV      (~21104)       → GV_Imp_Proveedor.derechos_pct (+ global)
--   _IMPO_MIN_USD_DEFAULT (~21107)     → Importados_Config.min_usd
--   _NAC_DEFAULTS       (~21110)       → Importados_Config.valor_m3 / flete_full
--   _nacEstad tramos    (~21089)       → Importados_Config.estad_*
--   _nacRecup tasas     (~21096)       → Importados_Config.iva_pct / iva_adic_pct / …
--   _PROV_IMP_LISTA     (~20972)       → GV_Imp_Proveedor (las filas activas)
--   meses_objetivo                     → seguía siendo GLOBAL (Importados_Config id=1);
--                                        ahora se puede pisar POR PROVEEDOR.
--
-- ⚠ El front deja fallbacks con estos mismos valores: si el fetch falla, la pantalla
--   sigue calculando igual que hoy. Lo que NO puede es ser la fuente.
--
-- ⚠ "Agregar/sacar códigos" NO crea una tabla nueva: el proveedor de un artículo
--   importado ya vive en Importados.proveedor (lo escribe la pestaña 🏭 Proveedores).
--   Acá se agrega la RPC para hacerlo desde el lado del proveedor, con guard.
-- ══════════════════════════════════════════════════════════════════════════════

-- ═══ 1) Los GLOBALES: columnas nuevas en Importados_Config (una sola fila, id=1) ═══
-- Nullable y sin backfill destructivo: si quedan en null, la vista usa el default de
-- este archivo, que es el número que hoy tiene el front.
alter table public."Importados_Config" add column if not exists derechos_pct   numeric;
alter table public."Importados_Config" add column if not exists ntl_pct        numeric;
alter table public."Importados_Config" add column if not exists iva_pct        numeric;
alter table public."Importados_Config" add column if not exists iva_adic_pct   numeric;
alter table public."Importados_Config" add column if not exists gcias_pct      numeric;
alter table public."Importados_Config" add column if not exists iibb_pct       numeric;
alter table public."Importados_Config" add column if not exists estad_pct      numeric;
alter table public."Importados_Config" add column if not exists estad_fob_desde numeric;
alter table public."Importados_Config" add column if not exists estad_fob_hasta numeric;
alter table public."Importados_Config" add column if not exists estad_fijo     numeric;
alter table public."Importados_Config" add column if not exists valor_m3       numeric;
alter table public."Importados_Config" add column if not exists flete_full     numeric;
alter table public."Importados_Config" add column if not exists min_usd        numeric;

update public."Importados_Config"
   set derechos_pct    = coalesce(derechos_pct,    0.18),     -- v23.78
       ntl_pct         = coalesce(ntl_pct,         0.05),     -- v22.37
       iva_pct         = coalesce(iva_pct,         0.21),     -- v23.80
       iva_adic_pct    = coalesce(iva_adic_pct,    0.20),
       gcias_pct       = coalesce(gcias_pct,       0.06),
       iibb_pct        = coalesce(iibb_pct,        0.0017),   -- v23.81
       estad_pct       = coalesce(estad_pct,       0.03),     -- v23.79
       estad_fob_desde = coalesce(estad_fob_desde, 6000),
       estad_fob_hasta = coalesce(estad_fob_hasta, 10000),
       estad_fijo      = coalesce(estad_fijo,      180),
       valor_m3        = coalesce(valor_m3,        110),      -- _NAC_DEFAULTS
       flete_full      = coalesce(flete_full,      2000),
       min_usd         = coalesce(min_usd,         25000),    -- _IMPO_MIN_USD_DEFAULT
       actualizado     = now()
 where id = 1;

-- ═══ 2) La config POR PROVEEDOR ════════════════════════════════════════════════
create table if not exists public."GV_Imp_Proveedor" (
  proveedor        text primary key,
  importador       text,              -- Chef / Tierra Nativa / …  (era _IMPORTADOR_DE)
  usa_ntl          boolean not null default false,  -- le factura a NTL (era _NTL_PROVEEDORES)
  ntl_pct          numeric,           -- null = el global (0,05)
  derechos_pct     numeric,           -- null = el global (0,18).  Fujian: 0,35
  meses_objetivo   numeric,           -- null = el global de Importados_Config
  min_usd          numeric,           -- null = el global
  valor_m3         numeric,           -- null = el global
  activo           boolean not null default true,
  orden            integer,
  notas            text,
  actualizado      timestamptz default now(),
  actualizado_por  text
);
alter table public."GV_Imp_Proveedor" enable row level security;
drop policy if exists gv_imp_proveedor_sel on public."GV_Imp_Proveedor";
create policy gv_imp_proveedor_sel on public."GV_Imp_Proveedor" for select using (true);
revoke insert, update, delete, truncate on public."GV_Imp_Proveedor" from anon, authenticated;

-- Semilla = exactamente lo que hoy dice el front. Idempotente: no pisa lo ya editado.
insert into public."GV_Imp_Proveedor" (proveedor, importador, usa_ntl, derechos_pct, orden) values
  ('Frontier',  'Chef',          true,  null, 1),
  ('Fujian',    'Chef',          true,  0.35, 2),
  ('Kangli',    'Chef',          true,  null, 3),
  ('Ownland',   'Chef',          false, null, 4),
  ('Becky',     'Tierra Nativa', false, null, 5),
  ('Hugo Wong', 'Tierra Nativa', false, null, 6),
  ('Zhixin',    'Tierra Nativa', true,  null, 7)
on conflict (proveedor) do nothing;

-- Y cualquier proveedor que ya exista en el maestro y no esté acá, entra apagado de NTL
-- (no se le inventa importador: queda null y la pantalla lo muestra para completar).
insert into public."GV_Imp_Proveedor" (proveedor, activo)
select distinct btrim(i.proveedor), true
  from public."Importados" i
 where nullif(btrim(i.proveedor),'') is not null
on conflict (proveedor) do nothing;

-- ═══ 3) La vista que resuelve el EFECTIVO (prov → global → default) ════════════
create or replace view public.gv_imp_proveedor_cfg
with (security_invoker = true) as
with g as (select * from public."Importados_Config" where id = 1)
select p.proveedor,
       p.importador,
       p.usa_ntl,
       coalesce(p.ntl_pct,        g.ntl_pct,        0.05)   as ntl_pct,
       coalesce(p.derechos_pct,   g.derechos_pct,   0.18)   as derechos_pct,
       coalesce(p.meses_objetivo, g.meses_objetivo, 10)     as meses_objetivo,
       (p.meses_objetivo is not null)                       as meses_propio,
       coalesce(p.min_usd,        g.min_usd,        25000)  as min_usd,
       coalesce(p.valor_m3,       g.valor_m3,       110)    as valor_m3,
       p.activo, p.orden, p.notas, p.actualizado, p.actualizado_por,
       -- lo crudo, para que el pop-up sepa qué está heredado y qué está pisado
       p.ntl_pct        as ntl_pct_propio,
       p.derechos_pct   as derechos_pct_propio,
       p.meses_objetivo as meses_objetivo_propio,
       p.min_usd        as min_usd_propio,
       p.valor_m3       as valor_m3_propio,
       (select count(*) from public."Importados" i
         where btrim(i.proveedor) = p.proveedor and i.activo and i.principal) as codigos,
       g.meses_objetivo as g_meses_objetivo, g.derechos_pct as g_derechos_pct,
       g.ntl_pct as g_ntl_pct, g.min_usd as g_min_usd, g.valor_m3 as g_valor_m3
  from public."GV_Imp_Proveedor" p cross join g;

-- Los globales de nacionalización, en una fila, para que el front no los hardcodee.
create or replace view public.gv_imp_nac_config
with (security_invoker = true) as
select coalesce(meses_objetivo, 10)      as meses_objetivo,
       coalesce(derechos_pct, 0.18)      as derechos_pct,
       coalesce(ntl_pct, 0.05)           as ntl_pct,
       coalesce(iva_pct, 0.21)           as iva_pct,
       coalesce(iva_adic_pct, 0.20)      as iva_adic_pct,
       coalesce(gcias_pct, 0.06)         as gcias_pct,
       coalesce(iibb_pct, 0.0017)        as iibb_pct,
       coalesce(estad_pct, 0.03)         as estad_pct,
       coalesce(estad_fob_desde, 6000)   as estad_fob_desde,
       coalesce(estad_fob_hasta, 10000)  as estad_fob_hasta,
       coalesce(estad_fijo, 180)         as estad_fijo,
       coalesce(valor_m3, 110)           as valor_m3,
       coalesce(flete_full, 2000)        as flete_full,
       coalesce(min_usd, 25000)          as min_usd,
       actualizado
  from public."Importados_Config" where id = 1;

-- ═══ 4) Las RPC de escritura (supervisor) ══════════════════════════════════════
create or replace function public.gv_imp_proveedor_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
-- Guarda la config de UN proveedor. Una clave AUSENTE no se toca; una clave presente
-- en null vuelve el campo a "heredado del global" — que es justo lo que el pop-up
-- necesita para el boton "usar el general".
-- Los porcentajes van en TANTO POR UNO: 0,35 = 35%.
declare v_prov text; v_num numeric; k text;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  v_prov := nullif(btrim(p->>'proveedor'), '');
  if v_prov is null then raise exception 'Falta el proveedor'; end if;

  -- validar ANTES de escribir: o entra todo o no entra nada
  foreach k in array array['derechos_pct','ntl_pct'] loop
    if p ? k then
      v_num := nullif(p->>k,'')::numeric;
      if v_num is not null and (v_num < 0 or v_num > 1) then
        raise exception '% va en tanto por uno (0,35 = 35%%), no en porcentaje', k;
      end if;
    end if;
  end loop;
  foreach k in array array['min_usd','valor_m3'] loop
    if p ? k then
      v_num := nullif(p->>k,'')::numeric;
      if v_num is not null and v_num < 0 then raise exception '% no puede ser negativo', k; end if;
    end if;
  end loop;
  if p ? 'meses_objetivo' then
    v_num := nullif(p->>'meses_objetivo','')::numeric;
    if v_num is not null and v_num <= 0 then raise exception 'Los meses objetivo tienen que ser mayores a 0'; end if;
  end if;

  insert into public."GV_Imp_Proveedor" (proveedor) values (v_prov) on conflict (proveedor) do nothing;

  update public."GV_Imp_Proveedor" set
    importador     = case when p ? 'importador'     then nullif(btrim(p->>'importador'),'')            else importador     end,
    usa_ntl        = case when p ? 'usa_ntl'        then coalesce((p->>'usa_ntl')::boolean, false)     else usa_ntl        end,
    ntl_pct        = case when p ? 'ntl_pct'        then nullif(p->>'ntl_pct','')::numeric            else ntl_pct        end,
    derechos_pct   = case when p ? 'derechos_pct'   then nullif(p->>'derechos_pct','')::numeric       else derechos_pct   end,
    meses_objetivo = case when p ? 'meses_objetivo' then nullif(p->>'meses_objetivo','')::numeric     else meses_objetivo end,
    min_usd        = case when p ? 'min_usd'        then nullif(p->>'min_usd','')::numeric            else min_usd        end,
    valor_m3       = case when p ? 'valor_m3'       then nullif(p->>'valor_m3','')::numeric           else valor_m3       end,
    activo         = case when p ? 'activo'         then coalesce((p->>'activo')::boolean, true)       else activo         end,
    notas          = case when p ? 'notas'          then nullif(btrim(p->>'notas'),'')                 else notas          end,
    actualizado     = now(),
    actualizado_por = coalesce(nullif(btrim(p->>'por'),''), auth.jwt() ->> 'email')
   where proveedor = v_prov;

  return (select to_jsonb(c) from public.gv_imp_proveedor_cfg c where c.proveedor = v_prov);
end $fn$;

create or replace function public.gv_imp_nac_config_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
-- Los globales de nacionalización e importados (lo que antes era _NAC_DEFAULTS y las
-- tasas fijas de _nacEstad / _nacRecup). Cada proveedor puede pisar los que lo admiten.
declare k text; v numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  foreach k in array array['meses_objetivo','derechos_pct','ntl_pct','iva_pct','iva_adic_pct',
                           'gcias_pct','iibb_pct','estad_pct','estad_fob_desde','estad_fob_hasta',
                           'estad_fijo','valor_m3','flete_full','min_usd'] loop
    if p ? k then
      v := nullif(p->>k,'')::numeric;
      if v is null or v < 0 then raise exception '% no puede quedar vacío ni negativo', k; end if;
      if k like '%\_pct' and v > 1 then raise exception '% va en tanto por uno (0,21 = 21%%)', k; end if;
      if k = 'meses_objetivo' and v <= 0 then raise exception 'Los meses objetivo tienen que ser mayores a 0'; end if;
      execute format('update public."Importados_Config" set %I = $1, actualizado = now() where id = 1', k) using v;
    end if;
  end loop;
  if (select estad_fob_desde from public."Importados_Config" where id=1)
     > (select estad_fob_hasta from public."Importados_Config" where id=1) then
    raise exception 'El tramo de estadística está al revés: "desde" no puede ser mayor que "hasta"';
  end if;
  return (select to_jsonb(c) from public.gv_imp_nac_config c);
end $fn$;

create or replace function public.gv_imp_codigo_proveedor(p_cod text, p_proveedor text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
-- Agrega o saca un código de un proveedor, desde el lado del PROVEEDOR.
-- p_proveedor null o '' = se lo saca (queda "sin proveedor", no se borra el artículo).
declare v_cod text; v_prov text; v_n int;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  v_cod  := upper(nullif(btrim(p_cod), ''));
  v_prov := nullif(btrim(p_proveedor), '');
  if v_cod is null then raise exception 'Falta el código'; end if;
  if v_prov is not null and not exists (select 1 from public."GV_Imp_Proveedor" where proveedor = v_prov) then
    raise exception 'El proveedor % no está en GV_Imp_Proveedor', v_prov;
  end if;
  -- todas las filas (marcas) de ese código, igual que la pestaña 🏭 Proveedores
  update public."Importados" set proveedor = v_prov, actualizado = now()
   where upper(btrim(cod_art)) = v_cod;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'El código % no está en el maestro Importados', v_cod; end if;
  return jsonb_build_object('cod', v_cod, 'proveedor', v_prov, 'filas', v_n);
end $fn$;

revoke all on function public.gv_imp_proveedor_guardar(jsonb)   from public, anon;
revoke all on function public.gv_imp_nac_config_guardar(jsonb)  from public, anon;
revoke all on function public.gv_imp_codigo_proveedor(text,text) from public, anon;
grant execute on function public.gv_imp_proveedor_guardar(jsonb)    to authenticated, service_role;
grant execute on function public.gv_imp_nac_config_guardar(jsonb)   to authenticated, service_role;
grant execute on function public.gv_imp_codigo_proveedor(text,text) to authenticated, service_role;

-- ═══ 5) Rollback ═══════════════════════════════════════════════════════════════
-- drop view if exists public.gv_imp_proveedor_cfg;
-- drop view if exists public.gv_imp_nac_config;
-- drop function if exists public.gv_imp_proveedor_guardar(jsonb);
-- drop function if exists public.gv_imp_nac_config_guardar(jsonb);
-- drop function if exists public.gv_imp_codigo_proveedor(text,text);
-- drop table if exists public."GV_Imp_Proveedor";
-- (las columnas de Importados_Config quedan: son nullable y nadie más las mira)
