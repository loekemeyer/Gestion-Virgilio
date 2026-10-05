-- v26.86 (Luis, 05/10/2026): "que salte mensaje en telegram cuando alguien guarda cosas en una
-- gondola cuando en teoria no entran por espacio". NO frena el guardado (D1 = no): avisa.
-- Caso que lo origino: 505, gondola 3.617 contra capacidad 3.340 (guardados de 574 el 21/09 y el
-- 28/09 con lugar para ~170 y ~163).
--
-- Mira cada movimiento que SUMA a gondola (deposito terminado: guardado, baja_racks, recepcion_imp)
-- de las ultimas 6 h, calcula el saldo de gondola de ese codigo despues del movimiento (dual: por
-- empresa) contra la capacidad (Capacidad_Sector = GV_Lugar_Item) y, si se paso, manda UN Telegram
-- por movimiento. Dedup en GV_Alerta_Gondola_Llena (el outbox se purga al mandar).
-- Forward-facing: al instalar se siembra el dedup con lo de las ultimas 6 h (no avisa lo viejo).
-- Cron gv-alerta-gondola-llena, minutos 3,8,...,58 (lejos de :00 y :30).
-- Probar sin mandar nada: select * from public.gv_alerta_gondola_llena_telegram(true);
do $inst$
begin
  execute $t$
    create table if not exists public."GV_Alerta_Gondola_Llena" (
      mov_id bigint primary key,
      cod text, empresa text, delta numeric, saldo numeric, cap numeric, legajo text,
      semilla boolean not null default false,
      avisado_en timestamptz not null default now())
  $t$;
  execute 'alter table public."GV_Alerta_Gondola_Llena" enable row level security';
  execute 'revoke all on public."GV_Alerta_Gondola_Llena" from anon, authenticated';

  execute $f$
create or replace function public.gv_alerta_gondola_llena_telegram(p_simular boolean default false)
returns table(mov_id bigint, cod text, empresa text, delta numeric, saldo numeric, cap numeric, legajo text, enviado boolean)
language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
#variable_conflict use_column
declare r record; v_n int := 0; v_nom text; v_desc text; v_txt text;
begin
  for r in
    with _gl_c as (
      select m.id, m.ts, m.cod_art, m.empresa as emp, m.delta::numeric as d, m.tipo, m.legajo as leg,
             gv_cod_stock(m.cod_art) as c,
             case when upper(btrim(m.cod_art)) ~ '^[0-9]+$' then
                    case when length(regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '')) >= 3
                         then regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '')
                         else lpad(regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', ''), 3, '0') end
                  else upper(btrim(m.cod_art)) end as ck,
             exists (select 1 from codigos_duales cd where gv_cod_stock(cd.cod) = gv_cod_stock(m.cod_art)) as dual
        from "Movimientos_Stock" m
       where m.deposito = 'terminado' and m.delta::numeric > 0
         and m.tipo in ('guardado','baja_racks','recepcion_imp')
         and m.ts > now() - interval '6 hours'
         and not exists (select 1 from "GV_Alerta_Gondola_Llena" a where a.mov_id = m.id))
    select g.*,
      (select coalesce(sum(s.delta::numeric), 0) from "Movimientos_Stock" s
        where s.deposito = 'terminado'
          and (case when upper(btrim(s.cod_art)) ~ '^[0-9]+$' then
                    case when length(regexp_replace(upper(btrim(s.cod_art)), '^0+(?=.)', '')) >= 3
                         then regexp_replace(upper(btrim(s.cod_art)), '^0+(?=.)', '')
                         else lpad(regexp_replace(upper(btrim(s.cod_art)), '^0+(?=.)', ''), 3, '0') end
                  else upper(btrim(s.cod_art)) end) = g.ck
          and (s.ts, s.id) <= (g.ts, g.id)
          and (not g.dual or s.empresa = g.emp)) as sal,
      (select sum(k.cajas_max) from "Capacidad_Sector" k
        where gv_cod_stock(k.cod) = g.c and (not g.dual or k.empresa = g.emp)) as capa
    from _gl_c g
  loop
    continue when coalesce(r.capa, 0) <= 0 or r.sal <= r.capa;
    mov_id := r.id; cod := r.cod_art; empresa := r.emp; delta := r.d; saldo := r.sal; cap := r.capa; legajo := r.leg;
    enviado := not p_simular;
    if not p_simular then
      select "Empleado" into v_nom from "Empleados" where "Legajo"::text = btrim(r.leg) limit 1;
      select sc.descripcion into v_desc from stocks_carga_rapida sc where sc.cod_base = r.c or sc.cod = r.cod_art limit 1;
      v_txt := '🛒 GÓNDOLA SIN LUGAR — ' || r.cod_art || coalesce(' ' || v_desc, '') ||
               case when r.dual then ' (' || coalesce(r.emp, '') || ')' else '' end || E'\n' ||
               coalesce(nullif(btrim(v_nom), ''), 'Legajo ' || coalesce(r.leg, '?')) || ' guardó ' ||
               replace(to_char(r.d, 'FM999G999'), ',', '.') || ' cajas (' || case r.tipo when 'baja_racks' then 'bajada de racks' when 'recepcion_imp' then 'recepción de importación' else 'guardado a góndola' end || ', ' ||
               to_char(r.ts at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') || ').' || E'\n' ||
               'Góndola: ' || replace(to_char(r.sal, 'FM999G999'), ',', '.') || ' cajas · capacidad ' || replace(to_char(r.capa, 'FM999G999'), ',', '.') ||
               ' · ' || replace(to_char(r.sal - r.capa, 'FM999G999'), ',', '.') || ' de más.' || E'\n' ||
               'Lo que no entra va a excedente con su ubicación: ¿dónde quedó?';
      perform tg_enqueue(v_txt, 'gv_gond_llena_' || r.id);
      insert into "GV_Alerta_Gondola_Llena" (mov_id, cod, empresa, delta, saldo, cap, legajo)
      values (r.id, r.cod_art, r.emp, r.d, r.sal, r.capa, r.leg) on conflict on constraint "GV_Alerta_Gondola_Llena_pkey" do nothing;
      v_n := v_n + 1;
    end if;
    return next;
  end loop;
  if v_n > 0 then perform tg_outbox_flush(); end if;
end $fn$
  $f$;
  execute 'revoke all on function public.gv_alerta_gondola_llena_telegram(boolean) from public, anon, authenticated';

  -- semilla: lo que ya estaba (forward-facing, no se avisa lo de antes de instalar)
  execute $s$
    insert into public."GV_Alerta_Gondola_Llena" (mov_id, cod, empresa, delta, saldo, cap, legajo, semilla)
    select x.mov_id, x.cod, x.empresa, x.delta, x.saldo, x.cap, x.legajo, true
      from public.gv_alerta_gondola_llena_telegram(true) x
    on conflict (mov_id) do nothing
  $s$;
end $inst$;

-- cron (fuera del do: cron.schedule no se repite si ya existe con el mismo nombre)
select cron.schedule('gv-alerta-gondola-llena', '3-58/5 * * * *',
                     'select count(*) from public.gv_alerta_gondola_llena_telegram(false)');

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_alerta_gondola_llena_telegram','funcion','r\.sal <= r\.capa',
        'guardar en gondola por encima de la capacidad avisa por Telegram (no frena el guardado)','Luis','v26.85');  -- etiqueta con la que se aplico (05/10)

-- ROLLBACK
-- select cron.unschedule('gv-alerta-gondola-llena');
-- drop function if exists public.gv_alerta_gondola_llena_telegram(boolean);
-- (la tabla GV_Alerta_Gondola_Llena se puede dejar: es el registro de lo avisado)
-- delete from public."GV_Reglas_Centinela" where objeto='gv_alerta_gondola_llena_telegram';
