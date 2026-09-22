-- v21.05 — El refresco de vista_stock_procesada se hace SOLO si algo cambio.
--
-- ANTES: cron 55 = "REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada",
--        cada 2 minutos, siempre. Medido sobre una ventana de 26,4 h:
--          1.770 s de ejecucion = 7,4 % del tiempo total de la base
--          media 2.239 ms · maximo 33.795 ms
--        Y sobre 7 dias: solo 277 de los 5.040 bloques de 2 minutos tuvieron
--        movimiento de stock, o sea que el 94,5 % de los refrescos no cambiaba
--        una sola fila de una matview de 367 filas / 216 kB.
--
--        Ese 7,4 % es la contencion que hacia que "A Programar" diera
--        "canceling statement due to statement timeout" (problema 492).
--
-- AHORA: el cron llama a gv_refresh_stock_si_cambio(), que compara una HUELLA de
--        lo que alimenta a la matview y refresca solo si se movio.
--
--        Medido en vivo: refresco 1.813 ms · chequeo que salta 12 ms  (150x)
--
-- ⚠ LA FRESCURA NO EMPEORA. El chequeo sigue corriendo cada 2 minutos: apenas
--   se escribe un movimiento, el refresco sale en la corrida siguiente, igual
--   que antes. Lo unico que se saca es el refresco que no cambiaba nada.
--
-- ⚠ EL ARBOL DE DEPENDENCIAS SE CAMINA EN VIVO, NO ES UNA LISTA A MANO.
--   vista_stock_procesada cuelga de 23 tablas y 5 vistas. Una lista escrita a
--   mano es exactamente el pozo que este repo ya piso varias veces (los pases
--   que eligen fecha, el ref compuesto, las tablas del renombre): siempre falta
--   una. Se resuelve con pg_rewrite/pg_depend, asi que una tabla nueva entra
--   sola. Verificado: 23 de 23 cubiertas.
--
-- ⚠ FAIL-OPEN a proposito, al reves del guard de cuarentena (v20.95): si la
--   huella no se puede calcular, SE REFRESCA. Un refresco de mas cuesta 2 s;
--   una vista de stock vieja la mira un operario y le miente.
--
-- ⚠ LA MATVIEW SE EXCLUYE DE SU PROPIA HUELLA. Si contara, su refresco
--   cambiaria la huella y se refrescaria para siempre.
--
-- Rollback (una linea, sin tocar nada mas):
--   select cron.alter_job(55, command := 'REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada');

create table if not exists public."GV_Stock_Refresh_Estado" (
  id             int primary key default 1 check (id = 1),
  huella         jsonb,
  refrescado_en  timestamptz,
  chequeado_en   timestamptz,
  refrescos      bigint not null default 0,
  saltos         bigint not null default 0,
  ultimo_ms      int,
  ultimo_motivo  text
);
alter table public."GV_Stock_Refresh_Estado" enable row level security;
revoke insert, update, delete, truncate on public."GV_Stock_Refresh_Estado" from anon, authenticated;

-- {tabla: escrituras} de TODO lo que alimenta a vista_stock_procesada
create or replace function public.gv_stock_huella_detalle()
returns jsonb
language sql stable security definer set search_path = public, pg_catalog
as $$
  with recursive dep(oid) as (
    select 'public.vista_stock_procesada'::regclass::oid
    union
    select c.oid
      from dep
      join pg_rewrite r on r.ev_class = dep.oid
      join pg_depend  d on d.objid = r.oid and d.classid = 'pg_rewrite'::regclass
      join pg_class   c on c.oid = d.refobjid and c.relkind in ('r','v','m','p')
     where c.oid <> dep.oid
  )
  select coalesce(jsonb_object_agg(c.relname,
                                   s.n_tup_ins + s.n_tup_upd + s.n_tup_del), '{}'::jsonb)
    from dep
    join pg_class c on c.oid = dep.oid
    join pg_stat_user_tables s on s.relid = c.oid
   where c.relkind in ('r','p');   -- solo tablas: la matview se excluye a proposito
$$;

create or replace function public.gv_stock_huella()
returns text language sql stable security definer set search_path = public, pg_catalog
as $$ select md5(public.gv_stock_huella_detalle()::text) $$;

create or replace function public.gv_refresh_stock_si_cambio(
  p_max_edad_min int default 60,
  p_solo_medir   boolean default false)
returns table(refrescada boolean, motivo text, ms int)
language plpgsql security definer set search_path = public, pg_catalog
as $$
declare
  v_new jsonb; v_old jsonb; v_ref timestamptz;
  v_mov text; v_do boolean := true; v_mot text;
  v_t0 timestamptz := clock_timestamp(); v_ms int := 0;
begin
  -- FAIL-OPEN: sin huella, se refresca.
  begin
    v_new := public.gv_stock_huella_detalle();
  exception when others then
    v_new := null;
  end;

  select e.huella, e.refrescado_en into v_old, v_ref
    from public."GV_Stock_Refresh_Estado" e where e.id = 1;

  if v_new is null then
    v_mot := 'huella no disponible';
  elsif v_old is null then
    v_mot := 'primera corrida';
  elsif v_ref is null
     or v_ref < now() - make_interval(mins => greatest(p_max_edad_min, 1)) then
    -- piso de frescura: aunque nada se mueva, una vez por hora se refresca.
    -- Es el seguro contra una dependencia que el arbol no ve (hoy no hay:
    -- ninguna vista ni funcion de la cadena usa now()/current_date, medido).
    v_mot := 'piso de frescura (' || p_max_edad_min || ' min)';
  elsif v_new is not distinct from v_old then
    -- la comparacion que MANDA es el jsonb entero, no clave por clave: asi una
    -- tabla que ENTRA o SALE del arbol de dependencias tambien cuenta
    v_do := false; v_mot := 'sin cambios';
  else
    select string_agg(k || ' +' || ((v_new->>k)::bigint - coalesce((v_old->>k)::bigint, 0)), ', ')
      into v_mov
      from jsonb_object_keys(v_new) k
     where (v_new->>k)::bigint is distinct from (v_old->>k)::bigint;
    v_mot := coalesce(v_mov, 'cambio el arbol de dependencias');
  end if;

  if v_do and not p_solo_medir then
    refresh materialized view concurrently public.vista_stock_procesada;
  end if;
  v_ms := round(extract(epoch from (clock_timestamp() - v_t0)) * 1000)::int;

  if not p_solo_medir then
    insert into public."GV_Stock_Refresh_Estado"
      (id, huella, refrescado_en, chequeado_en, refrescos, saltos, ultimo_ms, ultimo_motivo)
    values (1, case when v_do then v_new else v_old end,
               case when v_do then now() else v_ref end, now(),
               case when v_do then 1 else 0 end,
               case when v_do then 0 else 1 end,
               v_ms, left(v_mot, 400))
    on conflict (id) do update set
      huella        = excluded.huella,
      refrescado_en = excluded.refrescado_en,
      chequeado_en  = excluded.chequeado_en,
      refrescos     = public."GV_Stock_Refresh_Estado".refrescos + excluded.refrescos,
      saltos        = public."GV_Stock_Refresh_Estado".saltos    + excluded.saltos,
      ultimo_ms     = excluded.ultimo_ms,
      ultimo_motivo = excluded.ultimo_motivo;
  end if;

  refrescada := v_do; motivo := left(v_mot, 400); ms := v_ms; return next;
end $$;

revoke all on function public.gv_stock_huella_detalle() from public, anon;
revoke all on function public.gv_stock_huella() from public, anon;
revoke all on function public.gv_refresh_stock_si_cambio(int, boolean) from public, anon, authenticated;
grant execute on function public.gv_stock_huella_detalle() to authenticated, service_role;
grant execute on function public.gv_stock_huella() to authenticated, service_role;
grant execute on function public.gv_refresh_stock_si_cambio(int, boolean) to service_role;

-- EL CENTINELA: sin esto, que el cron deje de chequear no lo ve nadie
create or replace view public.gv_stock_refresh_salud as
select e.refrescado_en,
       round(extract(epoch from (now() - e.refrescado_en)))::int  as segundos_sin_refrescar,
       round(extract(epoch from (now() - e.chequeado_en)))::int   as segundos_sin_chequear,
       e.refrescos, e.saltos,
       case when e.refrescos + e.saltos > 0
            then round(100.0 * e.saltos / (e.refrescos + e.saltos), 1) end as pct_ahorrado,
       e.ultimo_ms, e.ultimo_motivo,
       case when e.chequeado_en is null or e.chequeado_en < now() - interval '10 minutes'
              then 'EL CRON NO ESTA CHEQUEANDO'
            when e.refrescado_en < now() - interval '90 minutes'
              then 'HACE MAS DE 90 MIN QUE NO SE REFRESCA'
            else 'ok' end as estado
  from public."GV_Stock_Refresh_Estado" e where e.id = 1;
alter view public.gv_stock_refresh_salud set (security_invoker = true);
grant select on public.gv_stock_refresh_salud to service_role;

-- EL CRON  (requiere el "si" del dueno: cambia un objeto vivo)
-- select cron.alter_job(55, command := 'select public.gv_refresh_stock_si_cambio();');

-- Centinelas de reglas que no se pueden perder:
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_stock_huella_detalle','funcion','pg_rewrite',
--   'El arbol de dependencias de la matview se camina en vivo, nunca una lista a mano','Thomas','v21.05'),
--  ('gv_refresh_stock_si_cambio','funcion','fail-open|v_new := null',
--   'Sin huella se refresca igual: una vista de stock vieja es peor que un refresco de mas','Thomas','v21.05'),
--  ('gv_stock_huella_detalle','funcion','relkind in \(''r'',''p''\)',
--   'La matview se excluye de su propia huella o se refresca para siempre','Thomas','v21.05');

-- Chequeo:
--   select * from public.gv_stock_refresh_salud;
--   select * from public.gv_refresh_stock_si_cambio(60, true);   -- que HARIA, sin refrescar
