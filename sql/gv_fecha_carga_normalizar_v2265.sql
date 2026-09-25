-- v22.65 (Luis 25/09): "no deberia poder venir en formatos diferentes".
-- Las filas sin año de Envios a Talleristas / Envios a PS (21-25/09) las escribia el repo de ORIGEN
-- GestionProductivaEntero (EnviosTall.js / EnviosPS.js: `${dia}/${mes}`), que se sigue usando;
-- el parche v20.54 se habia aplicado solo a las copias de cervantes-admin/.
-- Arreglo en el backend: trigger BEFORE INSERT/UPDATE que deja la fecha SIEMPRE dd/mm/aa,
-- venga de la pantalla que venga. Vacia o basura -> error (no se graba en silencio).
create or replace function public.gv_fecha_carga_normalizar()
returns trigger language plpgsql set search_path = public as $$
declare
  col text := TG_ARGV[0];
  v text; m text[]; d int; mo int; y int;
  hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  v := btrim(coalesce(to_jsonb(NEW) ->> col, ''));
  if v = '' then
    raise exception 'FECHA_CARGA: falta la fecha (%). No se guardo nada, cargala y volve a enviar.', TG_TABLE_NAME;
  end if;
  if v ~ '^\d{4}-\d{1,2}-\d{1,2}$' then
    m := regexp_match(v, '^(\d{4})-(\d{1,2})-(\d{1,2})$'); y := m[1]::int; mo := m[2]::int; d := m[3]::int;
  elsif v ~ '^\d{1,2}[/-]\d{1,2}[/-]\d{2}(\d{2})?$' then
    m := regexp_match(v, '^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$'); d := m[1]::int; mo := m[2]::int; y := m[3]::int;
    if y < 100 then y := 2000 + y; end if;
  elsif v ~ '^\d{1,2}[/-]\d{1,2}$' then
    m := regexp_match(v, '^(\d{1,2})[/-](\d{1,2})$'); d := m[1]::int; mo := m[2]::int;
    y := extract(year from hoy)::int;
    if mo > extract(month from hoy)::int then y := y - 1; end if;
  else
    raise exception 'FECHA_CARGA: "%" no es una fecha (%). No se guardo nada.', v, TG_TABLE_NAME;
  end if;
  begin
    perform make_date(y, mo, d);
  exception when others then
    raise exception 'FECHA_CARGA: "%" no es una fecha valida (%). No se guardo nada.', v, TG_TABLE_NAME;
  end;
  NEW := jsonb_populate_record(NEW, jsonb_build_object(col,
           lpad(d::text,2,'0') || '/' || lpad(mo::text,2,'0') || '/' || lpad((y % 100)::text,2,'0')));
  return NEW;
end $$;

create trigger gv_fecha_carga_norm before insert or update of "Dia-mes" on public."Envios a Talleristas"
  for each row execute function public.gv_fecha_carga_normalizar('Dia-mes');
create trigger gv_fecha_carga_norm before insert or update of "Dia-mes" on public."Envios a PS"
  for each row execute function public.gv_fecha_carga_normalizar('Dia-mes');
create trigger gv_fecha_carga_norm before insert or update of "Dia_mes" on public."Entregas Prov AT"
  for each row execute function public.gv_fecha_carga_normalizar('Dia_mes');

-- Probado como anon en transaccion abortada:
--   '25/09' -> 25/09/26 · '2026-09-25' -> 25/09/26 · '25/12' (en sept) -> 25/12/25 · '17-09' -> 17/09/26 · '' -> error
-- Rollback:
--   drop trigger gv_fecha_carga_norm on public."Envios a Talleristas";
--   drop trigger gv_fecha_carga_norm on public."Envios a PS";
--   drop trigger gv_fecha_carga_norm on public."Entregas Prov AT";
