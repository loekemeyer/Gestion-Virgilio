-- v28.40 (Luis, 07/10/2026, D10): cambia la DIRECCIÓN de una NP programada → la zona se recalcula.
--   Tanda sin empezar (sin EP/TP/AP/TAP): se aplica. Tanda empezada: la zona no se toca y queda anotado.
--   Cartel: gv_ppp_tanda_zona_fuera_regla (tanda con pedidos en camiones distintos + lo anotado de tandas empezadas).
-- ROLLBACK: alter table public."PPP_Web_Programacion" disable trigger gv_ppp_web_zona_recalc;
-- Aplicado en la sesión. Probado en transacción abortada: F48D (sin empezar) Zona 1 → Zona 6 y cartel 1 fila;
-- F21A (empezada) zona sin tocar y anotado. Lo ya salido (CCN/CRN) no va al cartel.

create table if not exists public."GV_PPP_Zona_Recalc" (
  id bigserial primary key, ts timestamptz not null default now(),
  empresa text not null, order_id bigint not null, np_idx int not null, np_label text, tanda text,
  zona_vieja text, zona_nueva text, dir_vieja text, dir_nueva text,
  aplicada boolean not null, motivo text);
alter table public."GV_PPP_Zona_Recalc" enable row level security;
revoke insert, update, delete, truncate on public."GV_PPP_Zona_Recalc" from anon, authenticated;
create policy gv_zrec_sel on public."GV_PPP_Zona_Recalc" for select to anon, authenticated using (true);
grant select on public."GV_PPP_Zona_Recalc" to anon, authenticated;

create or replace function public.gv_ppp_web_zona_recalc() returns trigger
language plpgsql security definer set search_path to 'public','pg_temp' as $f$
declare v_z text; v_emp boolean;
begin
  -- v28.40-zona-recalc (Luis, 07/10, D10)
  if coalesce(btrim(new.tanda),'') = '' then return new; end if;
  if new.direccion is not distinct from old.direccion and new.barrio is not distinct from old.barrio then return new; end if;
  if new.zona is distinct from old.zona then return new; end if;   -- el que escribe ya trae la zona
  v_z := public.gv_ppp_web_zona(new.barrio, null, new.direccion);
  if v_z is null or v_z = coalesce(new.zona,'') then return new; end if;
  v_emp := exists (select 1 from public."Registros_Produccion_Virgilio" r
                    where r.opcion in ('EP','TP','AP','TAP') and r.texto = new.tanda);
  insert into public."GV_PPP_Zona_Recalc"(empresa,order_id,np_idx,np_label,tanda,zona_vieja,zona_nueva,dir_vieja,dir_nueva,aplicada,motivo)
  values (new.empresa,new.order_id,new.np_idx,public.gv_ppp_web_np_label(new.empresa,new.np,new.np_idx),new.tanda,
          old.zona, v_z, coalesce(old.direccion,'')||' / '||coalesce(old.barrio,''), coalesce(new.direccion,'')||' / '||coalesce(new.barrio,''),
          not v_emp, case when v_emp then 'tanda empezada: zona sin tocar' else 'zona recalculada' end);
  if not v_emp then new.zona := v_z; end if;
  return new;
end $f$;
-- corre ANTES que gv_ppp_web_zona_retira (orden alfabético): el Retira pisa después.
create or replace trigger gv_ppp_web_zona_recalc before update of direccion, barrio on public."PPP_Web_Programacion"
  for each row execute function public.gv_ppp_web_zona_recalc();

create or replace view public.gv_ppp_tanda_zona_fuera_regla with (security_invoker = true) as
with w as (
  select w.fecha_entrega, upper(btrim(w.tanda)) tanda, w.empresa, w.order_id, w.np_idx,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) np_label, w.zona,
         coalesce(public.gv_ppp_web_camion(w.zona, null), '(sin zona)') camion
    from public."PPP_Web_Programacion" w
   where coalesce(btrim(w.tanda),'') <> ''
     and coalesce(w.fecha_entrega, current_date) >= current_date - 7
     and not exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.opcion in ('CCN','CRN')
                        and upper(btrim(split_part(r.texto,'|',1))) = upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
                        and not public.es_legajo_test(r.legajo))
), mez as (
  select fecha_entrega fecha, tanda, 'camiones distintos'::text motivo,
         string_agg(distinct camion, ' + ') camiones,
         string_agg(distinct coalesce(zona,'(sin zona)'), ' + ') zonas,
         string_agg(distinct np_label||' '||coalesce(zona,'(sin zona)'), ' · ') detalle
    from w group by fecha_entrega, tanda having count(distinct camion) > 1
), pend as (
  select distinct on (z.empresa, z.order_id, z.np_idx)
         w.fecha_entrega fecha, w.tanda, 'dirección cambió con la tanda empezada'::text motivo,
         null::text camiones, z.zona_vieja||' → '||z.zona_nueva zonas,
         w.np_label||': '||z.dir_vieja||' → '||z.dir_nueva detalle
    from public."GV_PPP_Zona_Recalc" z
    join w on w.empresa = z.empresa and w.order_id = z.order_id and w.np_idx = z.np_idx
   where not z.aplicada and w.zona is distinct from z.zona_nueva
   order by z.empresa, z.order_id, z.np_idx, z.ts desc
)
select * from mez union all select * from pend;
grant select on public.gv_ppp_tanda_zona_fuera_regla to anon, authenticated;

-- centinelas (ids en GV_Reglas_Centinela, version v28.40)
