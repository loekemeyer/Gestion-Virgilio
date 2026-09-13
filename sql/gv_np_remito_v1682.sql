-- =====================================================================================
-- NP -> NUMERO DE REMITO  (v16.82, 2026-09-13)
--
-- PEDIDO DEL DUENO: "en lugar de controlar con numero de NP, se deberia controlar contra
-- nro de remito (figura en la fc que se parsea)". El operario tiene el remito de papel en
-- la mano; la NP es un numero interno que en el papel no figura.
--
-- POR QUE HIZO FALTA INVESTIGAR: el remito SI esta parseado -- `remito_ref` en
-- isis_lk.documentos / isis_ch.documentos, 21.767 y 5.884 documentos, al dia -- pero la
-- columna `orden_compra`, que seria el lugar natural de la NP, viene VACIA. O sea que
-- ISIS no manda la NP junto al remito y NO hay atadura directa.
--
-- Cruzar por cliente + fecha NO alcanza, y se ve en la pantalla del dueno: las NP 98644 y
-- 98645 son las dos de Rebagliati (cod 1562) del 10/09, y ese cliente tiene DOS remitos
-- ese dia. Nada dice cual es cual.
--
-- LA CLAVE SON LAS CAJAS. `GV_Conciliacion_Facturacion.cajas_ent` coincide EXACTO con
-- `documentos.total_cajas`:
--     NP 98603 -> 301 cajas -> remito 0001-00091775
--     NP 98644 ->  36 cajas -> remito 0001-00091776
--     NP 98645 ->  17 cajas -> remito 0001-00091777
--
-- MEDIDO sobre las 67 NP de la conciliacion desde el 01/08, variando la ventana de fecha:
--     mismo dia : 33 resuelven (49%) | 34 sin remito | 0 ambiguas
--     +- 1 dia  : 56 resuelven (84%) |  9 sin remito | 2 ambiguas   <-- elegida
--     +- 5 dias : 61 resuelven (91%) |  4 sin remito | 2 ambiguas
-- Se toma +-1: la factura sale el mismo dia o el siguiente, y estirar la ventana suma poco
-- y afloja la clave. Corrido en vivo: 57 de 67 con remito (85,1%), y de las 19 filas que
-- hoy muestra la pantalla de RR, las 19 tienen numero.
--
-- POR QUE UNA TABLA Y NO UNA VISTA: `anon` NO tiene acceso a isis_lk / isis_ch (ni USAGE
-- del schema) y ahi viven precios, CUITs y totales. Una vista con security_invoker = true
-- -- que es lo que exige el CLAUDE.md -- devolveria VACIO para el front. Y ponerla en
-- security definer expondria los documentos, que es justo la filtracion del 2026-09-04.
-- Solucion: una funcion SECURITY DEFINER llena una tabla que guarda SOLO np, remito y
-- cajas (nada sensible), con RLS prendida y una policy de SELECT para anon.
--
-- NUNCA SE ADIVINA: si el cruce da 2 candidatos, `remito` queda en NULL y la pantalla
-- sigue mostrando la NP. `candidatos` deja registrado cuantos matchearon.
--
-- CRON: jobid 83 `gv-np-remito-sync`, '7 * * * *' (cada hora al minuto 7), ventana 60 dias.
-- ROLLBACK: select cron.unschedule('gv-np-remito-sync');
--           drop view public.gv_vista_control_remitos;  -- y recrearla sin la columna remito
--           drop function public.gv_np_remito_sync(int);
--           drop table public."GV_NP_Remito";
-- =====================================================================================

create table if not exists public."GV_NP_Remito" (
  np            text primary key,
  empresa       text,
  remito        text,
  cajas         numeric,
  fecha_salida  date,
  candidatos    int  not null default 0,
  actualizado_at timestamptz not null default now()
);
alter table public."GV_NP_Remito" enable row level security;
drop policy if exists gv_np_remito_lectura on public."GV_NP_Remito";
create policy gv_np_remito_lectura on public."GV_NP_Remito" for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public."GV_NP_Remito" from anon, authenticated;

create or replace function public.gv_np_remito_sync(p_dias int default 60)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  with base as (
    select regexp_replace(btrim(c.np::text), '\.0+$', '') np,
           lower(coalesce(nullif(btrim(c.empresa), ''), 'lk')) emp,
           btrim(c.cod_cliente) cod,
           c.cajas_ent::numeric cajas,
           c.fecha_salida::date f
      from public."GV_Conciliacion_Facturacion" c
     where c.cod_cliente is not null and c.cajas_ent is not null and c.fecha_salida is not null
       and c.fecha_salida >= current_date - p_dias
  ),
  docs as (
    select 'lk' emp, btrim(contraparte_codigo) cod, fecha::date f,
           total_cajas::numeric cajas, btrim(remito_ref) remito
      from isis_lk.documentos
     where nullif(btrim(coalesce(remito_ref, '')), '') is not null
       and total_cajas is not null and fecha >= current_date - p_dias - 5
    union all
    select 'chef', btrim(contraparte_codigo), fecha::date,
           total_cajas::numeric, btrim(remito_ref)
      from isis_ch.documentos
     where nullif(btrim(coalesce(remito_ref, '')), '') is not null
       and total_cajas is not null and fecha >= current_date - p_dias - 5
  ),
  m as (
    select b.np, b.emp, b.cajas, b.f,
           (select count(*) from docs d
             where d.emp = b.emp and d.cod = b.cod and d.cajas = b.cajas
               and d.f between b.f - 1 and b.f + 1) n,
           (select min(d.remito) from docs d
             where d.emp = b.emp and d.cod = b.cod and d.cajas = b.cajas
               and d.f between b.f - 1 and b.f + 1) r
      from base b
  )
  insert into public."GV_NP_Remito" (np, empresa, remito, cajas, fecha_salida, candidatos, actualizado_at)
  select m.np, m.emp,
         case when m.n = 1 then m.r end,   -- con 2 candidatos queda NULL a proposito
         m.cajas, m.f, m.n, now()
    from m
  on conflict (np) do update
     set empresa = excluded.empresa, remito = excluded.remito, cajas = excluded.cajas,
         fecha_salida = excluded.fecha_salida, candidatos = excluded.candidatos,
         actualizado_at = now();

  get diagnostics v_n = row_count;
  return v_n;
end $function$;

revoke all on function public.gv_np_remito_sync(int) from public, anon, authenticated;

-- la vista de RR suma la columna `remito` (LEFT JOIN: si no resolvio, queda NULL)
-- El CREATE completo de gv_vista_control_remitos vive en sql/gv_vista_control_remitos.sql

select cron.schedule('gv-np-remito-sync', '7 * * * *', $$select public.gv_np_remito_sync(60);$$);

-- verificacion
-- select count(*) filas, count(remito) con_remito, count(*) filter (where candidatos > 1) ambiguas
--   from public."GV_NP_Remito";
