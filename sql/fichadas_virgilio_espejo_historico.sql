-- ✅ APLICADO 2026-08-28 (migración `fichadas_virgilio_espejo_historico`).
-- Trigger backend: Fichadas_Virgilio → Fichadas_Historico (espejo).
--
-- FASE 1 (aplicada): solo el trigger. El front sigue escribiendo en ambas.
-- FASE 2 (pendiente, después de 24-48h de verificación): quitar el segundo POST
--   del front (buscar 'Fichadas_Historico' en index.html y recepcion.js).
--
-- Correcciones vs borrador:
--   • es_virgilio=true en fallback Fichadas_Estructura (multi-sede)
--   • ORDER BY e.id LIMIT 1 determinístico en Empleados
--   • set lock_timeout = '400ms'
--   • REVOKE EXECUTE en la función

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
