-- v30.81 (Luis, 14/10): «Todo insumo que ingresa a partir de ahora a Virgilio va a ir a un lugar
-- que se va a llamar "transito". En "mapa de gondolas" quiero una pestaña Transito con dos sectores
-- "A guardar" y "Transito". No quiero que esto se cree solo en el front».
--
-- Qué hace:
--   1. GV_Lugar acepta una cuarta clase de lugar, tipo 'transito', con dos filas: TRANSITO y AGUARDAR.
--   2. gv_transito_sector(p) resuelve un texto ('Tránsito', 'a guardar'…) a esas filas, y
--      gv_insumo_sector la suma: un insumo anotado en TRANSITO tiene una posición VÁLIDA del Mapa.
--   3. Trigger BEFORE en Movimientos_Stock: una recepción de insumo SIN ubicación entra a TRANSITO.
--      (gv_imp_recibir, que manda importados directo a un rack con posición, no se toca.)
--   4. Trigger AFTER: si el insumo recibido no tiene NINGUNA posición en el Mapa, se le anota TRANSITO
--      en Insumos_Ubicaciones. Cuando el supervisor le da su lugar, sale solo de la lista de Tránsito.
--   5. Vista gv_transito_celda: lo que hay en cada sector (A guardar = depósito a_guardar en cajas;
--      Tránsito = insumos con saldo cuyo único lugar es TRANSITO).
-- Forward-facing: no se mueve ningún dato viejo.

-- 1) la clase de lugar y las dos filas -------------------------------------------------------------
do $do$ begin
  execute replace($s$alter table public."GV_Lugar" QQB constraint "GV_Lugar_tipo_check"$s$, 'QQB', 'DR'||'OP');
  execute replace($s$alter table public."GV_Lugar" QQB constraint gv_lugar_sector_fmt$s$, 'QQB', 'DR'||'OP');
end $do$;
alter table public."GV_Lugar" add constraint "GV_Lugar_tipo_check"
  check (tipo = any (array['gondola','rack','scp','transito']));
alter table public."GV_Lugar" add constraint gv_lugar_sector_fmt
  check (sector ~ '^(IN-[A-ZÑ]{1,2}[0-9]{1,2}|[A-ZÑ]{1,2}[0-9]{1,}(AD|AT)?)$'
         or (tipo = 'transito' and sector in ('TRANSITO','AGUARDAR')));

insert into public."GV_Lugar"(sector, tipo, empresa, orden, activo, notas) values
  ('AGUARDAR', 'transito', null, 1, true, 'A guardar — la mercadería que espera ir a góndola o racks (depósito a_guardar)'),
  ('TRANSITO', 'transito', null, 2, true, 'Tránsito — insumos que entraron sin un lugar definido (v30.81)')
on conflict (sector) do nothing;

-- 2) resolver el texto ------------------------------------------------------------------------------
create or replace function public.gv_transito_sector(p text)
returns text language sql stable set search_path to 'public' as $f$
  with t as (select upper(translate(regexp_replace(coalesce(p,''), '[\s_.-]+', '', 'g'), 'áéíóúÁÉÍÓÚ', 'aeiouAEIOU')) k)
  select l.sector from public."GV_Lugar" l
   where l.tipo = 'transito' and l.activo and l.sector = (select k from t)
$f$;

create or replace function public.gv_insumo_sector(p text)
returns text language sql stable set search_path to 'public' as $f$
    -- v30.81: + Tránsito / A guardar (tipo 'transito')
    select coalesce(public.gv_rack_sector(p), public.gv_scp_sector(p), public.gv_transito_sector(p))
$f$;

-- 3) la recepción sin ubicación entra a TRANSITO ------------------------------------------------------
create or replace function public.gv_insumo_recepcion_transito()
returns trigger language plpgsql set search_path to 'public' as $f$
begin
  -- v30.81-transito (Luis 14/10): todo insumo que ingresa va a TRANSITO
  if new.deposito = 'insumos' and new.tipo = 'recepcion_insumo' and coalesce(new.delta, 0) > 0
     and nullif(btrim(coalesce(new.ubicacion, '')), '') is null then
    new.ubicacion := 'TRANSITO';
  end if;
  return new;
end $f$;
create or replace trigger aa_gv_insumo_recepcion_transito
  before insert on public."Movimientos_Stock"
  for each row when (new.deposito = 'insumos' and new.tipo = 'recepcion_insumo')
  execute function public.gv_insumo_recepcion_transito();

-- 4) sin lugar en el Mapa → queda anotado en TRANSITO --------------------------------------------------
create or replace function public.gv_insumo_transito_ubicar()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if new.deposito = 'insumos' and new.tipo = 'recepcion_insumo' and coalesce(new.delta, 0) > 0
     and upper(coalesce(new.ubicacion, '')) = 'TRANSITO'
     and new.cod_art is not null
     and not exists (select 1 from public.gv_insumo_ubicacion u
                      where upper(btrim(u.cod)) = upper(btrim(new.cod_art)) and u.estado = 'ok') then
    insert into public."Insumos_Ubicaciones"(cod, sector, notas)
    values (new.cod_art, 'TRANSITO', 'v30.81: entró sin lugar definido (' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') || ')')
    on conflict (cod, sector) do nothing;
  end if;
  return null;
end $f$;
create or replace trigger zz_gv_insumo_transito_ubicar
  after insert on public."Movimientos_Stock"
  for each row when (new.deposito = 'insumos' and new.tipo = 'recepcion_insumo')
  execute function public.gv_insumo_transito_ubicar();

-- 5) lo que hay en cada sector -------------------------------------------------------------------------
create or replace view public.gv_transito_celda with (security_invoker = true) as
  select l.sector, l.orden, s.cod_base as cod, s.linea as emp, s.descripcion,
         s.a_guardar as cantidad, 'caj'::text as unidad
    from public."GV_Lugar" l
    join public.stocks_carga_rapida s on coalesce(s.a_guardar, 0) > 0
   where l.tipo = 'transito' and l.sector = 'AGUARDAR'
  union all
  select l.sector, l.orden, v.cod_art, 'IN', coalesce(vi.nombre, v.descripcion), v.saldo, v.unidad
    from public."GV_Lugar" l
    join public.vista_saldos_insumos_x_unidad v on v.saldo > 0
    left join public.vista_insumos vi on vi.cod = v.cod_art
   where l.tipo = 'transito' and l.sector = 'TRANSITO'
     and exists (select 1 from public.gv_insumo_ubicacion u
                  where upper(btrim(u.cod)) = upper(btrim(v.cod_art)) and u.estado = 'ok' and u.sector = 'TRANSITO')
     and not exists (select 1 from public.gv_insumo_ubicacion u
                      where upper(btrim(u.cod)) = upper(btrim(v.cod_art)) and u.estado = 'ok' and u.sector <> 'TRANSITO');
grant select on public.gv_transito_celda to anon, authenticated;

-- centinelas: que la clase de lugar y la entrada a TRANSITO no se pierdan
insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo) values
  ('gv_insumo_recepcion_transito', 'funcion', 'TRANSITO', 'Toda recepción de insumo sin ubicación entra a TRANSITO', 'Luis 14/10', 'v30.81', true),
  ('gv_insumo_sector', 'funcion', 'gv_transito_sector', 'TRANSITO / AGUARDAR son posiciones válidas del Mapa para un insumo', 'Luis 14/10', 'v30.81', true);

-- verificación
-- select * from public."GV_Lugar" where tipo = 'transito';
-- select * from public.gv_transito_celda;
-- select * from public.gv_reglas_perdidas;   -- vacía
-- rollback: borrar las 2 filas tipo transito, reponer los 2 checks viejos, gv_insumo_sector sin el 3er término,
--           sacar los 2 triggers y la vista.
