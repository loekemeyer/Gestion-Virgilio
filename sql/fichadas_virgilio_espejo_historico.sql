-- ✅ APLICADO 2026-08-28 (migración `fichadas_virgilio_espejo_historico`).
-- ✅ FASE 2 APLICADA 2026-08-28 (migración `registros_fichada_espejo`).
--
-- Dos triggers backend eliminan la doble escritura del front a Fichadas_Historico:
--
--   1. trg_fichadas_virgilio_espejo (AFTER INSERT en Fichadas_Virgilio)
--      → cubre el QR de fichada.html (tipo 'ingreso' → evento 'Entrada').
--
--   2. trg_registros_fichada_espejo (AFTER INSERT en Registros_Produccion_Virgilio,
--      WHEN opcion IN ('PC','FJ'))
--      → cubre PC (Comida Inicia/Termina) y FJ (Salida) de index.html.
--
-- El front ya NO escribe en Fichadas_Historico (código mirror eliminado de
-- index.html y fichada.js).

create or replace function public.fichada_espejo_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
set lock_timeout = '400ms'
as $$
declare
  v_email   text;
  v_empresa text;
begin
  if es_legajo_test(new.legajo) then return new; end if;

  select e.email, e."Sede" into v_email, v_empresa
    from "Empleados" e
   where btrim(coalesce(e."Legajo",'')) = btrim(coalesce(new.legajo,''))
     and e.email is not null
   order by e.id limit 1;

  if v_email is null then
    select fe.email, fe.empresa into v_email, v_empresa
      from "Fichadas_Estructura" fe
     where btrim(coalesce(fe.leg,'')) = btrim(coalesce(new.legajo,''))
       and fe.tipo = 'emp' and fe.es_virgilio = true and fe.email is not null
     order by fe.orden limit 1;
  end if;

  if v_email is null then return new; end if;

  insert into "Fichadas_Historico" (ts_evento, evento, email, legajo, empresa, imported_at)
  values (new.ts_cliente, new.tipo, v_email, new.legajo, v_empresa, now())
  on conflict do nothing;

  return new;
end;
$$;

revoke execute on function public.fichada_espejo_insert() from public, anon, authenticated;

drop trigger if exists trg_fichadas_virgilio_espejo on public."Fichadas_Virgilio";
create trigger trg_fichadas_virgilio_espejo
  after insert on public."Fichadas_Virgilio"
  for each row
  execute function public.fichada_espejo_insert();

-- =====================================================================
-- Trigger 2: Registros_Produccion_Virgilio (PC/FJ) → Fichadas_Historico
-- =====================================================================

create or replace function public.registros_fichada_espejo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
set lock_timeout = '400ms'
as $$
declare
  v_email   text;
  v_empresa text;
  v_evento  text;
begin
  if es_legajo_test(new.legajo) then return new; end if;

  if new.opcion = 'FJ' then
    v_evento := 'Salida';
  elsif new.opcion = 'PC' then
    if new.ts_inicio is not null then
      v_evento := 'Comida Termina';
    else
      v_evento := 'Comida Inicia';
    end if;
  else
    return new;
  end if;

  select e.email, e."Sede" into v_email, v_empresa
    from "Empleados" e
   where btrim(coalesce(e."Legajo",'')) = btrim(coalesce(new.legajo,''))
     and e.email is not null
   order by e.id limit 1;

  if v_email is null then
    select fe.email, fe.empresa into v_email, v_empresa
      from "Fichadas_Estructura" fe
     where btrim(coalesce(fe.leg,'')) = btrim(coalesce(new.legajo,''))
       and fe.tipo = 'emp' and fe.es_virgilio = true and fe.email is not null
     order by fe.orden limit 1;
  end if;

  if v_email is null then return new; end if;

  insert into "Fichadas_Historico" (ts_evento, evento, email, legajo, empresa, imported_at)
  values (new.ts_cliente, v_evento, v_email, new.legajo, v_empresa, now())
  on conflict do nothing;

  return new;
end;
$$;

revoke execute on function public.registros_fichada_espejo() from public, anon, authenticated;

drop trigger if exists trg_registros_fichada_espejo on public."Registros_Produccion_Virgilio";
create trigger trg_registros_fichada_espejo
  after insert on public."Registros_Produccion_Virgilio"
  for each row
  when (new.opcion in ('PC', 'FJ'))
  execute function public.registros_fichada_espejo();
