-- v17.72 (Luis, 2026-09-14) — UNA SOLA LISTA DE CLIENTES SÚPER
--
-- Pedido: *"pasá la lista a la base y arreglá lo de Gigot. No puede haber 3 y 1 en el front.
-- Fijate qué cosas lee cada una y cuáles dependen de cada una, y fijate si se puede unificar en
-- una. Después, pasámela."*
--
-- ── LO QUE HABÍA: CINCO definiciones de "es súper", ninguna mandaba ────────────────────────
--
-- | # | Definición | Quién la usaba |
-- |---|---|---|
-- | a | `zona ~* 'super\|coto\|carrefour\|chango\|krikos'` | `gv_ppp_isis_sin_tanda`, `gv_ppp_detalle_dia`, `gv_ppp_prog_arbol`, `gv_ppp_super_mezclado` |
-- | b | `lower(zona) ~ 'super\|súper'` | `gv_viaje_np` (hoja de ruta / En Salida) |
-- | c | `lower(trim(zona)) = 'super'` | `vista_faltante_demanda` |
-- | d | `exists cobranzas_cliente_cadena(empresa, cod)` | `vista_cruce_facturacion`, `gv_vista_cruce_facturacion`, `vista_facturable_anticipado` + 7 funciones (Facturación, Cobranzas, Cuarentena, armado de tandas) |
-- | e | `localStorage vir_ppp_supers` (6 códigos, por dispositivo) | `pppEsSuper()` en el front — el backend no la veía |
--
-- a/b/c son tres formas distintas de mirar la ZONA, y la zona casi nunca dice "Super": de 158 NP
-- de clientes súper en la PPP, la regex marcaba **5**. e comparaba SÓLO por código, así que el
-- 2444 de LK (Relca S.R.L.) se colaba como súper porque el 2444 de Chef es Cencosud.
--
-- ── LO QUE QUEDA: UNA ──────────────────────────────────────────────────────────────────────
--
--   `public."GV_Supers"` (empresa, cod, cuit, super_key, nombre, activo, …) — la única lista,
--   y lo único que se edita. Se escribe SÓLO por `gv_supers_set` / `gv_supers_baja`.
--   `gv_es_super(empresa, cod)` / `gv_es_super_np(np, cod)` — la única pregunta.
--   `gv_supers` — la vista que lee el front.
--
-- ⚠ POR QUÉ `cobranzas_cliente_cadena` SIGUE EXISTIENDO. Lo natural sería dropearla y dejar una
-- vista sobre `GV_Supers`. NO se hizo: tiene **10 vistas de Facturación** colgando
-- (`vista_facturacion_neto_items`, `vista_cruce_facturacion`, `vista_facturable_anticipado`,
-- `vista_facturacion_estado`, `vista_facturacion_faltantes`, `vista_facturacion_neto`,
-- `gv_vista_*`, `gv_lk_np_feed`), y un `DROP … CASCADE` ahí es exactamente el pozo de la v16.20
-- y la v16.33 — encima sobre Facturación. Se dejó como **tabla derivada**: un trigger la rellena
-- desde `GV_Supers` y se le revocó la escritura a `anon`. Para el que la mantiene hay una sola
-- lista; para los 10 consumidores no cambió nada. El centinela `gv_supers_desincronizado` avisa
-- si alguna vez dejaran de coincidir (vacío = todo bien).
--
-- ── GIGOT ──────────────────────────────────────────────────────────────────────────────────
-- La base decía `gigot → LK 5000`. **Ese código no existe en ningún padrón**, así que Gigot nunca
-- fue tratado como súper. Es **Matiz SA, LK 4263** (CUIT 30627435033), que sí está en la PPP con
-- NP de hasta 12,6 m³. Corregido. Ojo: al pasar a súper, sus pedidos **web** dejan de llevar el
-- 2 % (`vista_facturacion_neto_items.factor_web` pasa de 0,98 a 1,0) y le aplican los precios de
-- `precios_super_lk` con `super_key = 'gigot'`. En Facturación hoy toca 1 NP.

-- ── 1) LA TABLA ────────────────────────────────────────────────────────────────────────────
create table if not exists public."GV_Supers" (
  empresa        text not null check (empresa in ('lk','chef')),
  cod            text not null,
  cuit           text,
  super_key      text not null,
  nombre         text not null,
  activo         boolean not null default true,
  nota           text,
  creado_at      timestamptz not null default now(),
  actualizado_at timestamptz not null default now(),
  actualizado_por text,
  primary key (empresa, cod)
);
create index if not exists gv_supers_key_idx  on public."GV_Supers" (super_key);
create index if not exists gv_supers_cuit_idx on public."GV_Supers" (cuit);
alter table public."GV_Supers" enable row level security;
drop policy if exists gv_supers_lectura on public."GV_Supers";
create policy gv_supers_lectura on public."GV_Supers" for select to anon, authenticated using (true);
grant select on public."GV_Supers" to anon, authenticated;
revoke insert, update, delete, truncate on public."GV_Supers" from anon, authenticated;

-- ── 2) LA PREGUNTA, EN UN SOLO LUGAR ───────────────────────────────────────────────────────
create or replace function public.gv_emp_norm(p text)
returns text language sql immutable parallel safe
set search_path to 'public','pg_temp' as $$
  select case when lower(btrim(coalesce(p,''))) in ('ch','chef') then 'chef' else 'lk' end;
$$;

-- la empresa deducida de la NP: 'LK …'/'CH …' por prefijo, y una NP de ISIS por su número
-- (arriba de 90000 es Loekemeyer), que es la regla que ya usaba gv_ppp_detalle_dia.
create or replace function public.gv_emp_de_np(p_np text)
returns text language sql immutable parallel safe
set search_path to 'public','pg_temp' as $$
  select case
    when lower(btrim(coalesce(p_np,''))) like 'ch%' then 'chef'
    when lower(btrim(coalesce(p_np,''))) like 'lk%' then 'lk'
    when coalesce(nullif(regexp_replace(coalesce(p_np,''), '\D', '', 'g'), '')::numeric, 0) > 90000 then 'lk'
    else 'chef' end;
$$;

create or replace function public.gv_es_super(p_empresa text, p_cod text)
returns boolean language sql stable parallel safe
set search_path to 'public','pg_temp' as $$
  select exists (
    select 1 from public."GV_Supers" s
     where s.activo
       and s.empresa = public.gv_emp_norm(p_empresa)
       and s.cod = regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '')
  );
$$;

create or replace function public.gv_es_super_np(p_np text, p_cod text)
returns boolean language sql stable parallel safe
set search_path to 'public','pg_temp' as $$
  select public.gv_es_super(public.gv_emp_de_np(p_np), p_cod);
$$;

create or replace function public.gv_super_key(p_empresa text, p_cod text)
returns text language sql stable parallel safe
set search_path to 'public','pg_temp' as $$
  select s.super_key from public."GV_Supers" s
   where s.activo and s.empresa = public.gv_emp_norm(p_empresa)
     and s.cod = regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '')
   limit 1;
$$;

grant execute on function public.gv_emp_norm(text), public.gv_emp_de_np(text),
  public.gv_es_super(text,text), public.gv_es_super_np(text,text), public.gv_super_key(text,text)
  to anon, authenticated;

-- ── 3) LO QUE LEE EL FRONT ─────────────────────────────────────────────────────────────────
create or replace view public.gv_supers
with (security_invoker = true) as
select empresa, cod, cuit, super_key, nombre, nota, activo, actualizado_at
  from public."GV_Supers" order by nombre, empresa, cod;
grant select on public.gv_supers to anon, authenticated;

-- ── 4) LA ÚNICA PUERTA DE ESCRITURA ────────────────────────────────────────────────────────
create or replace function public.gv_supers_set(
  p_empresa text, p_cod text, p_nombre text, p_super_key text default null,
  p_cuit text default null, p_nota text default null, p_por text default null)
returns public."GV_Supers" language plpgsql security definer
set search_path to 'public','pg_temp' as $$
declare v_emp text; v_cod text; v_key text; out public."GV_Supers";
begin
  v_emp := public.gv_emp_norm(p_empresa);
  v_cod := regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '');
  if v_cod = '' then raise exception 'Falta el código de cliente'; end if;
  if btrim(coalesce(p_nombre,'')) = '' then raise exception 'Falta el nombre del súper'; end if;
  v_key := nullif(lower(regexp_replace(btrim(coalesce(p_super_key,'')), '[^a-z0-9]', '', 'g')), '');
  if v_key is null then v_key := lower(regexp_replace(btrim(p_nombre), '[^A-Za-z0-9]', '', 'g')); end if;
  insert into public."GV_Supers" (empresa, cod, cuit, super_key, nombre, nota, activo, actualizado_por)
  values (v_emp, v_cod, nullif(btrim(coalesce(p_cuit,'')),''), v_key, btrim(p_nombre),
          nullif(btrim(coalesce(p_nota,'')),''), true, p_por)
  on conflict (empresa, cod) do update
     set nombre = excluded.nombre, super_key = excluded.super_key,
         cuit = coalesce(excluded.cuit, public."GV_Supers".cuit),
         nota = coalesce(excluded.nota, public."GV_Supers".nota),
         activo = true, actualizado_at = now(), actualizado_por = excluded.actualizado_por
  returning * into out;
  return out;
end $$;

-- baja LÓGICA: no se borra, se desactiva (la auditoría no se pierde)
create or replace function public.gv_supers_baja(p_empresa text, p_cod text, p_por text default null)
returns public."GV_Supers" language plpgsql security definer
set search_path to 'public','pg_temp' as $$
declare out public."GV_Supers";
begin
  update public."GV_Supers"
     set activo = false, actualizado_at = now(), actualizado_por = p_por
   where empresa = public.gv_emp_norm(p_empresa)
     and cod = regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '')
  returning * into out;
  if out.cod is null then raise exception 'Ese cliente no está en la lista de súper'; end if;
  return out;
end $$;

revoke all on function public.gv_supers_set(text,text,text,text,text,text,text) from public;
revoke all on function public.gv_supers_baja(text,text,text) from public;
grant execute on function public.gv_supers_set(text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.gv_supers_baja(text,text,text) to anon, authenticated;

-- ── 5) LA CARGA (19 filas: 14 cadenas, con el espejo de Chef del mismo CUIT) ────────────────
insert into public."GV_Supers" (empresa, cod, cuit, super_key, nombre, nota, actualizado_por) values
 ('lk'  ,'801' ,'30548083156','coto'       ,'Coto'            ,'Coto C.I.C.S.A.'                    ,'claude v17.72'),
 ('chef','2261','30548083156','coto'       ,'Coto'            ,'espejo Chef del mismo CUIT'         ,'claude v17.72'),
 ('lk'  ,'1651','30687310434','inc'        ,'Carrefour'       ,'Inc Sociedad Anonima'               ,'claude v17.72'),
 ('chef','1087','30687310434','inc'        ,'Carrefour'       ,'espejo Chef (Supermercados Norte)'  ,'claude v17.72'),
 ('lk'  ,'771' ,'30506730038','laanonima'  ,'La Anonima'      ,'S.A.Imp Y Exp De La Patagonia'      ,'claude v17.72'),
 ('chef','1804','30506730038','laanonima'  ,'La Anonima'      ,'espejo Chef del mismo CUIT'         ,'claude v17.72'),
 ('chef','2444','30590360763','cencosud'   ,'Jumbo'           ,'Cencosud S.A. — en LK el 2444 es Relca S.R.L., NO es super','claude v17.72'),
 ('chef','2686','30678138300','dorinka'    ,'Chango Mas'      ,'Dorinka S.R.L (Walmart)'            ,'claude v17.72'),
 ('lk'  ,'4263','30627435033','gigot'      ,'Gigot'           ,'Matiz SA — corrige el cod 5000, que no existe en ningun padron','claude v17.72'),
 ('lk'  ,'4112','30607371799','diarco'     ,'Diarco'          ,'Autoservicio Mayorista Diarco S.A'  ,'claude v17.72'),
 ('lk'  ,'3947','30685849751','dia'        ,'Dia'             ,'Dia Argentina SA'                   ,'claude v17.72'),
 ('lk'  ,'325' ,'30612929455','libertad'   ,'Libertad'        ,'Libertad S.A'                       ,'claude v17.72'),
 ('chef','1093','30612929455','libertad'   ,'Libertad'        ,'espejo Chef del mismo CUIT'         ,'claude v17.72'),
 ('lk'  ,'1947','30551497492','toledo'     ,'Toledo'          ,'Supermercados Toledo S.A'           ,'claude v17.72'),
 ('chef','1888','30551497492','toledo'     ,'Toledo'          ,'espejo Chef del mismo CUIT'         ,'claude v17.72'),
 ('lk'  ,'2320','30578411174','alberdi'    ,'Alberdi'         ,'Alberdi Sociedad Anonima'           ,'claude v17.72'),
 ('lk'  ,'1573','30710393679','messina'    ,'Messina Hnos'    ,'Messina Hnos S.A.'                  ,'claude v17.72'),
 ('lk'  ,'4051','30714956147','abastecedor','El Abastecedor'  ,'Supermercados El Abastecedor (Tecnolar)','claude v17.72'),
 ('lk'  ,'4080','33709267669','gm'         ,'Distribuidora GM','Distribuidora GM S.R.L.'            ,'claude v17.72')
on conflict (empresa, cod) do nothing;

-- ── 6) cobranzas_cliente_cadena PASA A SER DERIVADA ────────────────────────────────────────
create or replace function public.gv_supers_sync()
returns trigger language plpgsql security definer
set search_path to 'public','pg_temp' as $$
begin
  delete from public.cobranzas_cliente_cadena;
  insert into public.cobranzas_cliente_cadena (empresa, cod_cliente, super_key)
  select case when s.empresa = 'chef' then 'ch' else 'lk' end, s.cod, s.super_key
    from public."GV_Supers" s where s.activo;
  return null;
end $$;
drop trigger if exists gv_supers_sync_trg on public."GV_Supers";
create trigger gv_supers_sync_trg
  after insert or update or delete on public."GV_Supers"
  for each statement execute function public.gv_supers_sync();
revoke insert, update, delete, truncate on public.cobranzas_cliente_cadena from anon, authenticated;

-- centinela: vacío = las dos dicen lo mismo
create or replace view public.gv_supers_desincronizado
with (security_invoker = true) as
with g as (select case when empresa='chef' then 'ch' else 'lk' end emp, cod, super_key
             from public."GV_Supers" where activo),
     c as (select empresa, cod_cliente, super_key from public.cobranzas_cliente_cadena)
select coalesce(g.emp, c.empresa) empresa, coalesce(g.cod, c.cod_cliente) cod,
       g.super_key en_gv_supers, c.super_key en_cobranzas,
       case when c.cod_cliente is null then 'falta en cobranzas'
            when g.cod is null then 'sobra en cobranzas'
            else 'super_key distinta' end problema
  from g full join c on c.empresa = g.emp and c.cod_cliente = g.cod
 where g.cod is null or c.cod_cliente is null or g.super_key is distinct from c.super_key;
grant select on public.gv_supers_desincronizado to anon, authenticated;

-- ── 7) LAS 3 VARIANTES DE ZONA PASAN A PREGUNTARLE A LA LISTA ──────────────────────────────
-- En las 6 definiciones queda `gv_es_super_np(np, cod) OR <la señal de zona de siempre>`: la zona
-- deja de ser la definición y queda como red de seguridad para un súper que nadie cargó todavía.
-- Se aplicó como reemplazo de texto sobre `pg_get_viewdef` / `pg_get_functiondef`, con un
-- `raise exception` si el patrón viejo no aparecía (ver el bloque DO del commit v17.72):
--   gv_ppp_isis_sin_tanda   ·  d.zona ~* 'super|coto|carrefour|chango|krikos'
--   gv_ppp_super_mezclado   ·  filas.zona ~* '…'
--   gv_ppp_detalle_dia      ·  p.zona ~* '…'
--   gv_ppp_prog_arbol       ·  e.zona ~* '…'            (ver sql/gv_ppp_prog_arbol_v1766.sql)
--   gv_viaje_np             ·  lower(coalesce(d.zona,'')) ~ 'super|súper'
--   vista_faltante_demanda  ·  lower(trim(coalesce(p.zona,''))) = 'super'

-- ── MEDICIÓN (14/09) ───────────────────────────────────────────────────────────────────────
-- · `GV_Supers` = 19 filas (12 LK + 7 Chef), 14 cadenas · `cobranzas_cliente_cadena` = 19.
-- · `select count(*) from public.gv_supers_desincronizado;` → **0**.
-- · `select * from public.gv_endpoints_rotos;` → vacío.
-- · NP marcadas Súper en la PPP (hoy −180 / +120 días): **de 5 a 162** (157 las trae la lista,
--   5 ya las veía la zona) · 235,22 m³.
-- · Las otras vistas contestan: gv_viaje_np 914 filas / 54 súper · vista_faltante_demanda 551/40 ·
--   vista_facturacion_neto_items 10.772/596 · vista_cruce_facturacion 1.248/40 ·
--   gv_ppp_super_mezclado **0** (ningún camión mezcla súper con clientes: la regla del dueño de
--   la v14.23 se sigue respetando).
-- · Entran 6 códigos (los 5 espejos de Chef + Gigot LK 4263) y sale 1 (el fantasma LK 5000);
--   en `Facturacion_NP` eso toca 1 NP.
-- · Backup previo: `zz_backups."GV_Backup_cobranzas_cliente_cadena_20260914"` (14 filas).

-- ── ROLLBACK ───────────────────────────────────────────────────────────────────────────────
-- 1) drop trigger if exists gv_supers_sync_trg on public."GV_Supers";
-- 2) delete from public.cobranzas_cliente_cadena;
--    insert into public.cobranzas_cliente_cadena
--      select * from zz_backups."GV_Backup_cobranzas_cliente_cadena_20260914";
--    grant insert, update, delete on public.cobranzas_cliente_cadena to anon, authenticated;
-- 3) volver las 6 definiciones a la regla de zona sola (sacar el `gv_es_super_np(...) or ` de
--    cada una con el mismo reemplazo de texto, al revés).
-- 4) drop view if exists public.gv_supers_desincronizado, public.gv_supers;
--    drop function if exists public.gv_supers_set(text,text,text,text,text,text,text),
--      public.gv_supers_baja(text,text), public.gv_supers_sync(),
--      public.gv_es_super_np(text,text), public.gv_es_super(text,text),
--      public.gv_super_key(text,text), public.gv_emp_de_np(text), public.gv_emp_norm(text);
--    drop table if exists public."GV_Supers";
-- 5) en el front, volver `pppEsSuper` a la lista del localStorage (commit anterior a v17.72).
