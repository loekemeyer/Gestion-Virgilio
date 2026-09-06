-- ═══════════════════════════════════════════════════════════════════════════════════════
-- GV_PPP_Prog_Override — lo que Gestión cambia sobre una NP de ISIS SIN tocar la tabla compartida
-- v13.50 (2026-09-06 domingo) · migración gv_ppp_prog_override_v1350
--
-- Dueño: *"Chango Mas, programalo"*. La NP 44619 (Dorinka / Chango Mas, súper, 4,31 m³) estaba en
-- `PPP_Programacion_Diaria` para el vie 11 con `tanda = ''`: ISIS la dejó sin tanda, el tablero no la
-- mostraba en ningún camión y el cupo no la contaba.
--
-- `PPP_Programacion_Diaria` es COMPARTIDA con Producción (regla del dueño 2026-09-04: se agrega, nunca
-- se modifica). Patrón de CLAUDE.md: tabla `GV_*` de override + la vista que Gestión ya lee
-- (`gv_ppp_programacion_diaria`, canilla v12.90) la superpone. Producción sigue viendo la fila cruda.
--
--   GV_PPP_Prog_Override (np pk, tanda, fecha_entrega, nota, creado_en)
--     · np sin ".0" (se cruza con regexp_replace(p.np, '\.0+$', ''))
--     · tanda no vacía → pisa la tanda del espejo; fecha_entrega no nula → pisa la fecha ('YYYY-MM-DD 00:00:00')
--   gv_ppp_programacion_diaria: mismas columnas y tipos; left join al override.
--   gv_ppp_web_letra_y_camion(): también cuenta los códigos del override (si no, el próximo
--     automático repetiría E07A).
--   RLS: select para anon/authenticated (la vista es security_invoker); escribe sólo postgres/service_role
--   (por SQL, con pedido del dueño).
--
-- Cargado: 44619 → E07A (vie 11). Medido: la vista devuelve E07A · letra_y_camion = (4, 7) → próxima E08A ·
-- calendario vie 11 = 10,88 m³ (7,45 ISIS + 3,43 web; pasado a propósito, súper va en camión propio) ·
-- gv_ppp_base_pedidos tiene sus 12 líneas / 589 cajas.
--
-- Receta para otro caso:
--   insert into public."GV_PPP_Prog_Override" (np, tanda, fecha_entrega, nota)
--   values ('98xxx', 'E08A', null, 'motivo') on conflict (np) do update set tanda = excluded.tanda, nota = excluded.nota;
--
-- ROLLBACK:
--   delete from public."GV_PPP_Prog_Override" where np = '44619';
--   -- vista: volver a la de sql/gv_espejo_corte.sql (select p.* … sin el left join)
--   -- gv_ppp_web_letra_y_camion: quitar el union del override (sql/gv_ppp_web_armar_pendientes.sql §3)
--   drop table public."GV_PPP_Prog_Override";
-- ═══════════════════════════════════════════════════════════════════════════════════════

create table if not exists public."GV_PPP_Prog_Override" (
  np            text primary key,
  tanda         text,
  fecha_entrega date,
  nota          text,
  creado_en     timestamptz not null default now()
);
alter table public."GV_PPP_Prog_Override" enable row level security;
drop policy if exists gv_ppp_prog_override_read on public."GV_PPP_Prog_Override";
create policy gv_ppp_prog_override_read on public."GV_PPP_Prog_Override" for select to anon, authenticated using (true);
grant select on public."GV_PPP_Prog_Override" to anon, authenticated;
grant all on public."GV_PPP_Prog_Override" to service_role;

create or replace view public.gv_ppp_programacion_diaria
with (security_invoker = true) as
  select p.id,
         p.np,
         coalesce(nullif(btrim(o.tanda), ''), p.tanda) as tanda,
         p.tipo, p.fecha_recep, p.cod, p.razon_social, p.m3, p.v, p.direccion, p.barrio, p.op,
         coalesce(o.fecha_entrega::text || ' 00:00:00', p.fecha_entrega) as fecha_entrega,
         p.fecha_fc, p.zona, p.observaciones
    from public."PPP_Programacion_Diaria" p
    cross join public.gv_espejo_corte() c(lk, chef)
    left join public."GV_PPP_Prog_Override" o on o.np = regexp_replace(p.np, '\.0+$', '')
   where public.gv_espejo_np_pasa(p.np, c.lk, c.chef);

create or replace function public.gv_ppp_web_letra_y_camion(out letra int, out camion int)
language plpgsql stable set search_path = public, pg_temp as $$
declare r record;
begin
  select public.ppp_web_letra_idx(m[1]) as idx, (m[2])::int as nn
    into r
    from (
      select regexp_match(tanda, '^([A-Z]+)([0-9]+)[A-Z]+$') as m from public."PPP_Programacion_Diaria" where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
      union all
      select regexp_match(tanda, '^([A-Z]+)([0-9]+)[A-Z]+$') from public."GV_PPP_Prog_Override" where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
      union all
      select regexp_match(tanda, '^([A-Z]+)([0-9]+)[A-Z]+$') from public."PPP_Web_Programacion" where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
      union all
      select regexp_match(codigo, '^([A-Z]+)([0-9]+)[A-Z]+$') from public."PPP_Web_Tandas" where codigo ~ '^[A-Z]+[0-9]+[A-Z]+$' and estado <> 'descartada'
    ) t
   order by public.ppp_web_letra_idx(m[1]) desc, (m[2])::int desc
   limit 1;
  if not found or r.idx is null then letra := 0; camion := 0; return; end if;
  if r.nn >= 99 then letra := r.idx + 1; camion := 0;
  else letra := r.idx; camion := r.nn; end if;
end $$;

insert into public."GV_PPP_Prog_Override" (np, tanda, fecha_entrega, nota)
values ('44619', 'E07A', null, 'v13.50 2026-09-06 · dueño: "Chango Mas, programalo". ISIS lo dejó sin tanda para el vie 11 (Dorinka / Chango Mas, súper, 4,31 m³, OC 9400146407).')
on conflict (np) do nothing;
