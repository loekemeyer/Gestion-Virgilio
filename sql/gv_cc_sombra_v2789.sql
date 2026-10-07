-- =====================================================================================
-- v27.89 (Luis, 07/10/2026): MODO SOMBRA de la CUENTA CORRIENTE del cliente
-- =====================================================================================
-- "No se le muestra nada de nada al cliente bajo ninguna circunstancia hasta que este el
--  pedido explicito de Thomy o Luis." Esto NO muestra nada: sólo MIDE.
--
-- Qué mide: el saldo que el sistema le mostraría a cada cliente ENTRE dos subidas del
-- Excel de deuda (Cuarentena) contra lo que dice el Excel siguiente (= el ERP).
--   variante 'excel+isis'        = ancla anterior + facturas/NC/ND de ISIS posteriores
--   variante 'excel+isis-banco'  = lo anterior − recibos de la conciliación posteriores
--                                  (misma lógica que gv_cobranza_deuda_viva_refrescar)
-- Diferencia = |estimado − Excel nuevo| por cliente. Un cruce está OK si NINGÚN cliente
-- difiere en $1 o más (tolerancia en GV_CC_Sombra_Config).
--
-- Racha: días hábiles SEGUIDOS (gv_es_dia_habil) en que hubo al menos un cruce y todos
-- dieron OK. Un día hábil sin subida del Excel CORTA la racha (no se puede validar lo que
-- no se midió). Con 20 → se abre UNA tarea en el Planify de Luis (employee 52), una vez
-- por empresa y variante (GV_CC_Sombra_Aviso).
--
-- El Excel de deuda se reemplaza en cada subida (GV_Cuarentena_Deuda_Detalle sólo guarda
-- el último lote): por eso cada lote se COPIA a GV_CC_Ancla apenas aparece.
--
-- Cron: gv-cc-sombra, '9-59/10 * * * *' (minutos con 1-2 jobs en gv_cron_colisiones),
-- con anti-solape. Rollback al final.
-- =====================================================================================

create table if not exists public."GV_CC_Ancla" (
  id bigserial primary key,
  empresa text not null,
  lote text not null,
  ancla timestamptz not null,
  cod text not null,
  doc_key text,
  comprobante text,
  pendiente numeric not null,
  copiado_en timestamptz not null default now()
);
create index if not exists gv_cc_ancla_lote_idx on public."GV_CC_Ancla" (empresa, lote);

create table if not exists public."GV_CC_Cruce" (
  id bigserial primary key,
  empresa text not null,
  variante text not null,
  lote_prev text not null, ancla_prev timestamptz not null,
  lote_nuevo text not null, ancla_nueva timestamptz not null,
  dia date not null,
  clientes int not null,
  clientes_dif int not null,
  suma_abs_dif numeric not null,
  max_abs_dif numeric not null,
  ok boolean not null,
  creado_en timestamptz not null default now(),
  unique (empresa, variante, lote_prev, lote_nuevo)
);

create table if not exists public."GV_CC_Cruce_Detalle" (
  cruce_id bigint not null references public."GV_CC_Cruce"(id) on delete cascade,
  cod text not null,
  estimado numeric not null,
  excel numeric not null,
  dif numeric not null,
  primary key (cruce_id, cod)
);

create table if not exists public."GV_CC_Sombra_Config" (
  clave text primary key,
  valor numeric not null,
  nota text
);
insert into public."GV_CC_Sombra_Config" values
  ('tolerancia', 1, 'diferencia por cliente en $ que cuenta como distinta (0 diferencia = menos de $1)'),
  ('racha_objetivo', 20, 'dias habiles seguidos con 0 diferencia para abrir la tarea de implementar'),
  ('planify_employee', 52, 'Luis Rial Otero')
on conflict (clave) do nothing;

create table if not exists public."GV_CC_Sombra_Aviso" (
  empresa text not null,
  variante text not null,
  task_id bigint,
  racha int,
  creado_en timestamptz not null default now(),
  primary key (empresa, variante)
);

alter table public."GV_CC_Ancla" enable row level security;
alter table public."GV_CC_Cruce" enable row level security;
alter table public."GV_CC_Cruce_Detalle" enable row level security;
alter table public."GV_CC_Sombra_Config" enable row level security;
alter table public."GV_CC_Sombra_Aviso" enable row level security;
revoke all on public."GV_CC_Ancla", public."GV_CC_Cruce", public."GV_CC_Cruce_Detalle",
              public."GV_CC_Sombra_Config", public."GV_CC_Sombra_Aviso" from anon, authenticated;

-- -------------------------------------------------------------------------------------
-- Estimado por cliente entre dos anclas (no escribe nada)
-- -------------------------------------------------------------------------------------
create or replace function public.gv_cc_sombra_estimar(p_emp text, p_lote_prev text, p_hasta timestamptz)
returns table (cod text, base numeric, nuevos numeric, cobros numeric)
language plpgsql stable security definer set search_path = public
as $f$
declare v_ancla timestamptz; v_dia date; v_hasta_dia date; v_med numeric; v_nrec bigint;
begin
  select max(a.ancla) into v_ancla from "GV_CC_Ancla" a where a.empresa = p_emp and a.lote = p_lote_prev;
  if v_ancla is null then return; end if;
  v_dia := (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date;
  v_hasta_dia := (p_hasta at time zone 'America/Argentina/Buenos_Aires')::date;

  -- recibos posteriores al Excel: mismo criterio de numeración que gv_cobranza_deuda_viva_refrescar
  select percentile_cont(0.5) within group (order by r.recibo::bigint) into v_med
    from gv_cobranza_recibos r where r.empresa = p_emp and r.fecha_primer_cobro between v_dia - 30 and v_dia;
  select max(r.recibo::bigint) into v_nrec
    from gv_cobranza_recibos r
   where r.empresa = p_emp and r.fecha_primer_cobro between v_dia - 30 and v_dia and r.recibo::bigint <= 1.05 * v_med;

  return query
  with b as materialized (
         select a.cod, a.doc_key, a.pendiente from "GV_CC_Ancla" a where a.empresa = p_emp and a.lote = p_lote_prev),
       docs as materialized (
         select regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') c,
                gv_cobranza_doc_key(d.familia, d.punto_venta||d.numero) k,
                case when d.familia = 'nc_venta' then -abs(d.total) else abs(d.total) end m
           from isis_lk.documentos d
          where p_emp = 'lk' and d.familia in ('factura_venta','nc_venta','nd_venta')
            and (d.fecha > v_dia or (d.fecha = v_dia and d.familia <> 'nc_venta'))
            and d.fecha <= v_hasta_dia and d.created_at <= p_hasta
         union all
         select regexp_replace(coalesce(d.contraparte_codigo,''),'^0+',''),
                gv_cobranza_doc_key(d.familia, d.punto_venta||d.numero),
                case when d.familia = 'nc_venta' then -abs(d.total) else abs(d.total) end
           from isis_ch.documentos d
          where p_emp = 'chef' and d.familia in ('factura_venta','nc_venta','nd_venta')
            and (d.fecha > v_dia or (d.fecha = v_dia and d.familia <> 'nc_venta'))
            and d.fecha <= v_hasta_dia and d.created_at <= p_hasta),
       n as (select dd.c, sum(dd.m) m from docs dd
              where dd.m <> 0 and not exists (select 1 from b where b.doc_key = dd.k) group by 1),
       r as (select rr.cod_cliente c,
                    sum(rr.pagado / (1 - coalesce((select sd.pct from "GV_Cobranza_Super_Deduccion" sd
                                                    where sd.empresa = p_emp and sd.cod_cliente = rr.cod_cliente), 0))) m
               from gv_cobranza_recibos rr
              where rr.empresa = p_emp and v_nrec is not null
                and rr.recibo::bigint > v_nrec and rr.recibo::bigint <= 1.05 * v_nrec
                and rr.fecha_primer_cobro <= v_hasta_dia
              group by 1),
       bb as (select b.cod c, sum(b.pendiente) m from b group by 1),
       u as (select bb.c from bb union select n.c from n union select r.c from r)
  select u.c, coalesce(bb.m,0), coalesce(n.m,0), coalesce(r.m,0)
    from u left join bb on bb.c = u.c left join n on n.c = u.c left join r on r.c = u.c
   where u.c <> '' and not (p_emp = 'lk' and u.c = '411') and not (p_emp = 'chef' and u.c = '1434');
end $f$;

-- -------------------------------------------------------------------------------------
-- Racha de días hábiles seguidos OK, hacia atrás desde el último día con cruce
-- -------------------------------------------------------------------------------------
create or replace function public.gv_cc_sombra_racha(p_emp text, p_var text)
returns int language plpgsql stable security definer set search_path = public
as $f$
declare v_d date; v_min date; v_n int := 0; v_ok boolean; v_hay boolean;
begin
  select min(dia), max(dia) into v_min, v_d from "GV_CC_Cruce" where empresa = p_emp and variante = p_var;
  if v_d is null then return 0; end if;
  while v_d >= v_min loop
    if gv_es_dia_habil(v_d) then
      select count(*) > 0, coalesce(bool_and(ok), false) into v_hay, v_ok
        from "GV_CC_Cruce" where empresa = p_emp and variante = p_var and dia = v_d;
      exit when not v_hay or not v_ok;
      v_n := v_n + 1;
    end if;
    v_d := v_d - 1;
  end loop;
  return v_n;
end $f$;

-- -------------------------------------------------------------------------------------
-- Tick: copia lotes nuevos, cruza contra el anterior, mira la racha y abre la tarea
-- -------------------------------------------------------------------------------------
create or replace function public.gv_cc_sombra_tick()
returns text language plpgsql security definer set search_path = public
as $f$
declare e text; v_lote text; v_ancla timestamptz; v_prev text; v_tol numeric; v_obj int; v_emp_id int;
        v_var text; v_id bigint; v_racha int; v_task bigint; v_out text := '';
begin
  -- v27.88-cc-sombra
  select valor into v_tol from "GV_CC_Sombra_Config" where clave = 'tolerancia';
  select valor::int into v_obj from "GV_CC_Sombra_Config" where clave = 'racha_objetivo';
  select valor::int into v_emp_id from "GV_CC_Sombra_Config" where clave = 'planify_employee';

  foreach e in array array['lk','chef'] loop
    select x.lote, max(x.cargado_at) into v_lote, v_ancla from "GV_Cuarentena_Deuda_Detalle" x
     where x.empresa = e group by x.lote order by max(x.cargado_at) desc limit 1;
    continue when v_lote is null;
    continue when exists (select 1 from "GV_CC_Ancla" a where a.empresa = e and a.lote = v_lote);

    select a.lote into v_prev from "GV_CC_Ancla" a where a.empresa = e and a.ancla < v_ancla
     order by a.ancla desc limit 1;

    insert into "GV_CC_Ancla" (empresa, lote, ancla, cod, doc_key, comprobante, pendiente)
    select e, v_lote, v_ancla, regexp_replace(coalesce(x.cod,''),'^0+',''),
           gv_cobranza_doc_key(split_part(x.comp_key,'-',1), split_part(x.comp_key,'-',2)),
           x.comprobante, x.pendiente
      from "GV_Cuarentena_Deuda_Detalle" x
     where x.empresa = e and x.lote = v_lote and x.pendiente <> 0 and x.comp_key ~ '^[A-Z]';
    v_out := v_out || format('%s: ancla %s copiada. ', e, v_lote);

    continue when v_prev is null;

    foreach v_var in array array['excel+isis','excel+isis-banco'] loop
      v_id := null;
      insert into "GV_CC_Cruce" (empresa, variante, lote_prev, ancla_prev, lote_nuevo, ancla_nueva, dia,
                                 clientes, clientes_dif, suma_abs_dif, max_abs_dif, ok)
      values (e, v_var, v_prev, (select max(ancla) from "GV_CC_Ancla" where empresa = e and lote = v_prev),
              v_lote, v_ancla, (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date, 0, 0, 0, 0, false)
      on conflict do nothing returning id into v_id;
      continue when v_id is null;

      insert into "GV_CC_Cruce_Detalle" (cruce_id, cod, estimado, excel, dif)
      select v_id, coalesce(s.cod, n.cod),
             round(coalesce(s.base + s.nuevos - case when v_var = 'excel+isis-banco' then s.cobros else 0 end, 0), 2),
             round(coalesce(n.m, 0), 2),
             round(coalesce(s.base + s.nuevos - case when v_var = 'excel+isis-banco' then s.cobros else 0 end, 0)
                   - coalesce(n.m, 0), 2)
        from gv_cc_sombra_estimar(e, v_prev, v_ancla) s
        full join (select a.cod, sum(a.pendiente) m from "GV_CC_Ancla" a
                    where a.empresa = e and a.lote = v_lote
                      and not (e = 'lk' and a.cod = '411') and not (e = 'chef' and a.cod = '1434')
                    group by 1) n on n.cod = s.cod;

      update "GV_CC_Cruce" c set
        clientes     = d.n,
        clientes_dif = d.nd,
        suma_abs_dif = d.sa,
        max_abs_dif  = d.mx,
        ok           = (d.nd = 0)
        from (select count(*) n, count(*) filter (where abs(dif) >= v_tol) nd,
                     coalesce(sum(abs(dif)),0) sa, coalesce(max(abs(dif)),0) mx
                from "GV_CC_Cruce_Detalle" where cruce_id = v_id) d
       where c.id = v_id;

      v_racha := gv_cc_sombra_racha(e, v_var);
      v_out := v_out || format('%s/%s racha %s. ', e, v_var, v_racha);

      -- una sola tarea por empresa (la primera variante que llegue; planify.tasks tiene unico (name, date))
      if v_racha >= v_obj and not exists (select 1 from "GV_CC_Sombra_Aviso" where empresa = e) then
        insert into planify.tasks (name, type, prio, time, date, note, rec, done, assignment_type,
          employee_id, department_id, system_generated, broadcast, created_at, updated_at)
        values (left('Implementar cuenta corriente en página ' || upper(e), 60), 'tarea', 'normal', '09:00',
          to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD'),
          format('Falta: decidir e implementar la cuenta corriente del cliente en la página %s. El modo sombra (variante %s) dio %s días hábiles seguidos con 0 diferencia contra el Excel de deuda. NO se muestra nada al cliente hasta pedido explícito de Thomas o Luis. Pedido de Luis · cargada por Claude (gv_cc_sombra_tick), sesión https://claude.ai/code/session_016HWyanXdXj3agMmtenRK2U',
                 upper(e), v_var, v_racha),
          'none', false, 'employee', v_emp_id, null, true, false, now(), now())
        returning id into v_task;
        insert into "GV_CC_Sombra_Aviso" (empresa, variante, task_id, racha) values (e, v_var, v_task, v_racha);
        v_out := v_out || format('TAREA %s abierta. ', v_task);
      end if;
    end loop;
  end loop;
  return coalesce(nullif(v_out, ''), 'sin lotes nuevos');
end $f$;

revoke execute on function public.gv_cc_sombra_estimar(text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.gv_cc_sombra_racha(text, text) from public, anon, authenticated;
revoke execute on function public.gv_cc_sombra_tick() from public, anon, authenticated;

-- Lectura para la persona (MCP / SQL editor)
create or replace view public.gv_cc_sombra_estado with (security_invoker = true) as
select c.empresa, c.variante, c.dia, c.lote_prev, c.lote_nuevo, c.clientes, c.clientes_dif,
       round(c.suma_abs_dif) suma_abs_dif, round(c.max_abs_dif) max_abs_dif, c.ok,
       public.gv_cc_sombra_racha(c.empresa, c.variante) racha_actual
  from public."GV_CC_Cruce" c order by c.ancla_nueva desc, c.empresa, c.variante;
revoke all on public.gv_cc_sombra_estado from anon, authenticated;

-- Arranque con lo que hay: copia los lotes vigentes como primeras anclas (no cruza nada)
select public.gv_cc_sombra_tick();

-- Cron (anti-solape)
select cron.schedule('gv-cc-sombra', '9-59/10 * * * *', $c$
do $$ begin
  if pg_try_advisory_xact_lock(hashtext('cron:gv_cc_sombra_tick')::bigint) then
    perform public.gv_cc_sombra_tick();
  end if;
end $$;
$c$);

-- -------------------------------------------------------------------------------------
-- Chequeo
--   select * from public.gv_cc_sombra_estado;
--   select d.* from public."GV_CC_Cruce_Detalle" d join public."GV_CC_Cruce" c on c.id = d.cruce_id
--    where c.id = <id> and abs(d.dif) >= 1 order by abs(d.dif) desc;
--
-- Rollback
--   select cron.unschedule('gv-cc-sombra');
--   drop view if exists public.gv_cc_sombra_estado;
--   drop function if exists public.gv_cc_sombra_tick(), public.gv_cc_sombra_racha(text,text),
--        public.gv_cc_sombra_estimar(text,text,timestamptz);
--   drop table if exists public."GV_CC_Cruce_Detalle", public."GV_CC_Cruce", public."GV_CC_Ancla",
--        public."GV_CC_Sombra_Config", public."GV_CC_Sombra_Aviso";
-- =====================================================================================
