-- GV_Dias_No_Habiles · v13.23 (2026-09-05 sábado noche) · migración `gv_dias_no_habiles_metalurgico_v1323`
-- Dueño: "el lunes 07/09 no es feriado pero es el Día del Metalúrgico: no van a ir a trabajar; por eso
-- no hay pedidos en la PPP para entregar el lunes".
-- Tabla NUESTRA de días no hábiles de la empresa. NO se toca `planify.feriados`: la pisa el sync de la
-- Edge Function planify_sync-feriados (cron 33) y la usan planify_is_dia_laboral y
-- notificar_pasaje_papeles_48h (Producción). `gv_es_dia_habil` (nuestra) mira las dos.
-- Para agregar un día:  insert into public."GV_Dias_No_Habiles" (fecha, motivo, creado_por) values ('2026-12-24', 'Nochebuena', 'dueño');
-- Para sacarlo:         delete from public."GV_Dias_No_Habiles" where fecha = '2026-12-24';
-- Quién puede escribir: supervisores (gv_es_supervisor_o_servicio) y service_role; todos leen.

create table if not exists public."GV_Dias_No_Habiles" (
  fecha      date primary key,
  motivo     text not null,
  creado_por text,
  creado_en  timestamptz not null default now()
);
alter table public."GV_Dias_No_Habiles" enable row level security;
drop policy if exists gv_dias_no_habiles_sel on public."GV_Dias_No_Habiles";
create policy gv_dias_no_habiles_sel on public."GV_Dias_No_Habiles" for select to anon, authenticated using (true);
drop policy if exists gv_dias_no_habiles_sup on public."GV_Dias_No_Habiles";
create policy gv_dias_no_habiles_sup on public."GV_Dias_No_Habiles" for all to authenticated
  using (public.gv_es_supervisor_o_servicio()) with check (public.gv_es_supervisor_o_servicio());
grant select on public."GV_Dias_No_Habiles" to anon, authenticated, service_role;
grant insert, update, delete on public."GV_Dias_No_Habiles" to authenticated, service_role;

insert into public."GV_Dias_No_Habiles" (fecha, motivo, creado_por)
values ('2026-09-07', 'Día del Metalúrgico (no se trabaja; dueño, 2026-09-05)', 'claude v13.23')
on conflict (fecha) do nothing;

-- gv_es_dia_habil (nuestra): fin de semana, feriado nacional (planify.feriados) o día no hábil de la empresa.
create or replace function public.gv_es_dia_habil(p_fecha date default current_date)
returns boolean language sql stable security definer set search_path to 'public', 'planify' as $$
  select extract(dow from p_fecha) not in (0, 6)
     and not exists (select 1 from planify.feriados f where f.fecha = p_fecha)
     and not exists (select 1 from public."GV_Dias_No_Habiles" g where g.fecha = p_fecha);
$$;

-- Medido (sábado 05/09): gv_es_dia_habil('2026-09-07') = false · gv_ppp_web_dia_minimo('2026-09-07 00:01-03') = 2026-09-11
-- (el lunes es la base, no cuenta como hábil; +4 hábiles = mar, mié, jue, vie).
-- Lo que se saltea el lunes: job 00:01 (cron 71) e intradía (cron 73) igual corren (miran la fecha objetivo,
-- que es hábil), "A Programar" muestra el lunes como "No hábil", el tablero lo sigue dibujando (el front
-- sólo saltea fines de semana).
