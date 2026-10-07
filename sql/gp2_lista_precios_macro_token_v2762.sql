-- ============================================================================
-- v27.62 · Idea 7358 REABIERTA (Luis, 07/10: D3 sí · D4 token · D5 deducido)
-- Planilla «A Costos VIGENTES» → Supabase por macro + aviso a Telegram de cada
-- cambio de la hoja «Lista de Precios ». Pedido de Thomas (02/10).
--
-- Base: el SQL de la sesión del 06/10 (repo GP2, commit a7e40a9, revertido en
-- dc6add4 cuando se descartó). Cambios contra esa versión:
--   • la macro entra con TOKEN ("GP2".planilla_token), como la de conciliación
--     (GV_Conc_Token): sin cuenta de compras ni password en el Excel;
--   • el aviso va explícito al grupo -1004379879565 (el default de tg_enqueue,
--     que recibe los avisos de gerencia: cobranzas, pedidos anómalos, clientes).
--     6282395816 es un chat PRIVADO con el bot (Thomas: diario, plata, salud) y
--     -5397417174 es el de GT (Cervantes).
--
-- Reglas del diff (medidas el 02/10 sobre A_Costos_VIGENTES.xlsx):
--   • clave = col A (ID del VLOOKUP), nunca el nº de fila;
--   • se compara G (Último $ proveedor), NUNCA H ni L (fórmulas con dólar / IPC);
--   • misma A con E y K cambiados a la vez = filas corridas: se avisa aparte;
--   • proveedor por cod_prov (col B) contra public."Proveedores";
--   • dólar ($H$3) como línea aparte.
--
-- La función lista_precios_diff YA ESTABA aplicada (06/10); se repite idéntica.
--
-- ⚠ CORRERLO EN EL SQL EDITOR de Supabase (proyecto hrxfctzncixxqmpfhskv): desde la
-- sesión de Claude se cuelga (07/10, apply_migration 60 s sin llegar a la base).
-- Verificación después:
--   select to_regclass('"GP2".planilla_token'), count(*) from pg_proc where proname = 'lista_precios_subir';
--   select token from "GP2".planilla_token;   -- el token que va en la macro
--
-- Rollback:
--   drop function if exists "GP2".lista_precios_subir(jsonb,text,numeric,int,boolean,text);
--   drop table if exists "GP2".planilla_token;
-- ============================================================================

-- token de la macro (secreto: NO va al repo; se lee con select * from "GP2".planilla_token)
create table if not exists "GP2".planilla_token (
  token      text primary key default gen_random_uuid()::text,
  creado_en  timestamptz not null default now(),
  nota       text
);
alter table "GP2".planilla_token enable row level security;
revoke all on "GP2".planilla_token from anon, authenticated;
insert into "GP2".planilla_token (nota)
select 'macro A Costos VIGENTES (v27.62)'
 where not exists (select 1 from "GP2".planilla_token);

alter table "GP2".planilla_snapshot add column if not exists dolar numeric;

-- ----------------------------------------------------------------------------
-- 1) Diff puro (STABLE, no escribe) — testeable solo.
-- ----------------------------------------------------------------------------
create or replace function "GP2".lista_precios_diff(p_prev integer, p_new integer)
 returns table(
   clase text, id_a text, cod_prov text, proveedor text, cod_isis text, producto text,
   moneda_ant text, moneda_new text, g_ant numeric, g_new numeric, pct numeric )
 language sql
 stable security definer
 set search_path to 'GP2','public','pg_temp'
as $function$
  with lp as (
    select snapshot_id,
           nullif(btrim(datos->>'A'),'')        as id_a,
           nullif(btrim(datos->>'B'),'')        as cod_prov,
           nullif(btrim(datos->>'E'),'')        as cod_isis,
           upper(nullif(btrim(datos->>'F'),'')) as moneda,
           "GP2".planilla_num(datos->>'G')      as g,
           nullif(btrim(datos->>'K'),'')        as producto
      from "GP2".planilla_fila
     where hoja = 'Lista de Precios '
       and (datos->>'A') ~ '^[0-9]+$'
       and snapshot_id in (p_prev, p_new)
  ),
  lpd as (   -- A 1506 viene repetida: nos quedamos con la de G no nulo
    select distinct on (snapshot_id, id_a)
           snapshot_id, id_a, cod_prov, cod_isis, moneda, g, producto
      from lp
     order by snapshot_id, id_a, (g is null), producto
  ),
  a as (select * from lpd where snapshot_id = p_prev),
  b as (select * from lpd where snapshot_id = p_new),
  j as (
    select coalesce(b.id_a, a.id_a) as id_a,
           a.cod_prov a_cp, a.cod_isis a_e, a.moneda a_m, a.g a_g, a.producto a_k,
           b.cod_prov b_cp, b.cod_isis b_e, b.moneda b_m, b.g b_g, b.producto b_k
      from a full join b on a.id_a = b.id_a
  ),
  cl as (
    select j.*,
      case
        when a_cp is null then 'alta'
        when b_cp is null then 'baja'
        when coalesce(a_e,'') is distinct from coalesce(b_e,'')
         and coalesce(a_k,'') is distinct from coalesce(b_k,'') then 'corrimiento'
        when coalesce(a_m,'') is distinct from coalesce(b_m,'') then 'moneda'
        when coalesce(a_g,-1) is distinct from coalesce(b_g,-1)
         and coalesce(b_g,0) >= coalesce(a_g,0) then 'aumento'
        when coalesce(a_g,-1) is distinct from coalesce(b_g,-1) then 'baja_precio'
        else null
      end as clase
      from j
  )
  select cl.clase, cl.id_a,
         coalesce(cl.b_cp, cl.a_cp) as cod_prov,
         coalesce(pr.razon_social, 'Prov ' || coalesce(cl.b_cp, cl.a_cp)) as proveedor,
         coalesce(cl.b_e, cl.a_e) as cod_isis,
         coalesce(cl.b_k, cl.a_k) as producto,
         cl.a_m as moneda_ant, cl.b_m as moneda_new,
         cl.a_g as g_ant, cl.b_g as g_new,
         case when cl.a_g is not null and cl.a_g <> 0 and cl.b_g is not null
              then round((cl.b_g - cl.a_g) / cl.a_g * 100, 1) end as pct
    from cl
    left join public."Proveedores" pr
      on regexp_replace(pr.codigo,'^0+','') = regexp_replace(coalesce(cl.b_cp, cl.a_cp),'^0+','')
   where cl.clase is not null;
$function$;

comment on function "GP2".lista_precios_diff(integer,integer) is
  'Diff de la hoja "Lista de Precios " entre dos snapshots por col A (ID VLOOKUP). Compara G (no H/L). Clases: alta|baja|aumento|baja_precio|moneda|corrimiento. Idea 7358.';

-- ----------------------------------------------------------------------------
-- 2) Subida por macro: snapshot + herencia + carga + diff + aviso + poda.
-- ----------------------------------------------------------------------------
create or replace function "GP2".lista_precios_subir(
    p_filas         jsonb,                    -- { "Lista de Precios ": [[fila,{celdas},bloque?,{formulas}?], ...] }
    p_subido_por    text    default null,
    p_dolar         numeric default null,     -- valor de $H$3 al guardar; aviso aparte
    p_umbral_detalle int    default 60,       -- arriba de esto no detalla uno por uno
    p_avisar        boolean default true,
    p_token         text    default null)     -- token de la macro (GP2.planilla_token); sin token exige sesión GP2
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'GP2','public','pg_temp'
as $function$
declare
  v_prev int; v_new int; v_prev_dolar numeric;
  v_alta int; v_baja int; v_aum int; v_bajp int; v_mon int; v_corr int; v_tot int;
  v_msg text; v_blk text; v_part text;
begin
  -- v27.62: la macro entra con TOKEN (Luis D4, 07/10), como la de conciliación.
  -- Sin token válido, exige una sesión autorizada de GP2 (como antes).
  if p_token is null or not exists (select 1 from "GP2".planilla_token t where t.token = p_token) then
    perform "GP2"._exigir_autorizado();
  end if;

  if p_filas is null or not (p_filas ? 'Lista de Precios ') then
    raise exception 'p_filas debe traer la hoja "Lista de Precios "';
  end if;

  select id, dolar into v_prev, v_prev_dolar
    from "GP2".planilla_snapshot where vigente order by id desc limit 1;

  v_new := "GP2".planilla_snapshot_nuevo('A_Costos_VIGENTES.xlsx',
             'macro ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI'),
             p_subido_por);
  update "GP2".planilla_snapshot set dolar = p_dolar where id = v_new;

  -- heredar todas las hojas MENOS la Lista de Precios
  if v_prev is not null then
    insert into "GP2".planilla_fila (snapshot_id, hoja, fila, bloque, datos, formulas)
    select v_new, hoja, fila, bloque, datos, formulas
      from "GP2".planilla_fila
     where snapshot_id = v_prev and hoja <> 'Lista de Precios '
    on conflict on constraint planilla_fila_uk do nothing;
  end if;

  perform "GP2".planilla_cargar(v_new, p_filas);

  drop table if exists _lpd;
  create temp table _lpd on commit drop as
    select * from "GP2".lista_precios_diff(v_prev, v_new);

  select count(*) filter (where clase='alta'),
         count(*) filter (where clase='baja'),
         count(*) filter (where clase='aumento'),
         count(*) filter (where clase='baja_precio'),
         count(*) filter (where clase='moneda'),
         count(*) filter (where clase='corrimiento')
    into v_alta, v_baja, v_aum, v_bajp, v_mon, v_corr
    from _lpd;
  v_tot := coalesce(v_alta,0)+coalesce(v_baja,0)+coalesce(v_aum,0)+coalesce(v_bajp,0)+coalesce(v_mon,0);

  if p_avisar and v_prev is not null
     and (v_tot > 0 or coalesce(v_corr,0) > 0
          or (p_dolar is not null and p_dolar is distinct from v_prev_dolar)) then

    v_msg := '📋 Lista de Precios actualizada (A Costos VIGENTES)' || E'\n' ||
             to_char(now() at time zone 'America/Argentina/Buenos_Aires','DD/MM HH24:MI') ||
             coalesce(' · ' || p_subido_por, '');

    if p_dolar is not null and p_dolar is distinct from v_prev_dolar then
      v_msg := v_msg || E'\n\n💵 Dólar: ' || coalesce(v_prev_dolar::text,'—') || ' → ' || p_dolar::text;
    end if;

    if coalesce(v_corr,0) > 0 then
      select string_agg(distinct proveedor, ', ') into v_blk from _lpd where clase='corrimiento';
      v_msg := v_msg || E'\n\n⚠️ Posible CORRIMIENTO de filas en: ' || coalesce(v_blk,'?') ||
               E'\n(insertaron filas sin la col A; no confiar en los aumentos de esos bloques, revisar a mano).';
    end if;

    if v_tot > p_umbral_detalle then
      v_msg := v_msg || E'\n\n' || v_tot || ' cambios en total (planilla muy modificada o primera sincronización):' ||
               E'\n🔺 ' || coalesce(v_aum,0) || ' aumentos · 🔻 ' || coalesce(v_bajp,0) || ' bajas · 🆕 ' ||
               coalesce(v_alta,0) || ' nuevos · ❌ ' || coalesce(v_baja,0) || ' sacados · 💱 ' || coalesce(v_mon,0) || ' moneda.' ||
               E'\nNo se detallan uno por uno.';
    else
      if coalesce(v_aum,0) > 0 then
        select string_agg(E'\n  • ' || proveedor || ' · ' || coalesce(producto,'?') ||
                 coalesce(' (' || cod_isis || ')','') || ': $' || trim(to_char(g_ant,'FM999999990.00')) ||
                 ' → $' || trim(to_char(g_new,'FM999999990.00')) ||
                 coalesce('  (' || case when pct>=0 then '+' else '' end || trim(to_char(pct,'FM990.0')) || '%)',''),
                 '' order by pct desc nulls last)
          into v_part from _lpd where clase='aumento';
        v_msg := v_msg || E'\n\n🔺 AUMENTOS (' || v_aum || '):' || v_part;
      end if;

      if coalesce(v_bajp,0) > 0 then
        select string_agg(E'\n  • ' || proveedor || ' · ' || coalesce(producto,'?') ||
                 ': $' || trim(to_char(g_ant,'FM999999990.00')) || ' → $' || trim(to_char(g_new,'FM999999990.00')) ||
                 coalesce('  (' || trim(to_char(pct,'FM990.0')) || '%)',''),
                 '' order by pct asc nulls last)
          into v_part from _lpd where clase='baja_precio';
        v_msg := v_msg || E'\n\n🔻 BAJAS (' || v_bajp || '):' || v_part;
      end if;

      if coalesce(v_mon,0) > 0 then
        select string_agg(E'\n  • ' || proveedor || ' · ' || coalesce(producto,'?') ||
                 ': ' || coalesce(moneda_ant,'—') || ' → ' || coalesce(moneda_new,'—'), '' order by proveedor)
          into v_part from _lpd where clase='moneda';
        v_msg := v_msg || E'\n\n💱 MONEDA (' || v_mon || '):' || v_part;
      end if;

      if coalesce(v_alta,0) > 0 then
        select string_agg(E'\n  • ' || proveedor || ' · ' || coalesce(producto,'?') ||
                 coalesce(': $' || trim(to_char(g_new,'FM999999990.00')),''), '' order by proveedor)
          into v_part from _lpd where clase='alta';
        v_msg := v_msg || E'\n\n🆕 NUEVOS (' || v_alta || '):' || v_part;
      end if;

      if coalesce(v_baja,0) > 0 then
        select string_agg(E'\n  • ' || proveedor || ' · ' || coalesce(producto,'?'), '' order by proveedor)
          into v_part from _lpd where clase='baja';
        v_msg := v_msg || E'\n\n❌ SACADOS (' || v_baja || '):' || v_part;
      end if;
    end if;

    perform public.tg_enqueue(v_msg, 'listaprec_' || v_new, '-1004379879565');
  end if;

  delete from "GP2".planilla_snapshot
   where id in (select id from "GP2".planilla_snapshot order by id desc offset 20);

  return jsonb_build_object(
    'ok', true, 'snapshot_prev', v_prev, 'snapshot_new', v_new,
    'altas', coalesce(v_alta,0), 'bajas', coalesce(v_baja,0),
    'aumentos', coalesce(v_aum,0), 'baja_precio', coalesce(v_bajp,0),
    'moneda', coalesce(v_mon,0), 'corrimientos', coalesce(v_corr,0),
    'aviso', (p_avisar and v_prev is not null and (v_tot > 0 or coalesce(v_corr,0) > 0
             or (p_dolar is not null and p_dolar is distinct from v_prev_dolar))));
end $function$;

comment on function "GP2".lista_precios_subir(jsonb,text,numeric,int,boolean,text) is
  'Sube la hoja "Lista de Precios " desde la macro del Excel (token GP2.planilla_token), hereda el resto de hojas del snapshot anterior, calcula el diff y avisa a Telegram (-1004379879565). Idea 7358, v27.62.';

-- La macro llama con la clave pública (anon) + p_token. Sin token válido la función
-- exige sesión GP2, así que anon sin token se rechaza adentro.
revoke all on function "GP2".lista_precios_subir(jsonb,text,numeric,int,boolean,text) from public;
grant execute on function "GP2".lista_precios_subir(jsonb,text,numeric,int,boolean,text) to anon, authenticated;
grant execute on function "GP2".lista_precios_diff(integer,integer) to authenticated;
