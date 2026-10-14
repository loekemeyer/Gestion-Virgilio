-- v30.81 · 2026-10-14 · LUGAR TEMPORAL que se saca solo (Luis: "que haya un trigger para que se borre automatico
-- cuando salga"). Caso: IN-H0, 1 cajón de I6 (Mango Plano 502 Doblado) que se entrega a Cervantes.
--
-- GV_Lugar.gv_temporal (boolean, nullable, sin default: tabla compartida). Un lugar temporal vive mientras tenga
-- algo: cuando un insumo con posición ahí queda sin saldo > 0, se le saca esa posición, y si el lugar queda sin
-- posiciones (y sin GV_Lugar_Item, que tiene FK) se saca el GV_Lugar. Queda en Insumos_Historial.
-- No toca lugares no temporales: el resto sigue con gv_insumo_liberar_rack_sin_stock (racks, v30.37).
-- Trigger zz_gv_lugar_temporal: AFTER INSERT en Movimientos_Stock, deposito insumos.

alter table public."GV_Lugar" add column if not exists gv_temporal boolean;
comment on column public."GV_Lugar".gv_temporal is
  'v30.81: lugar temporal; se saca solo cuando su insumo queda en 0 (gv_lugar_temporal_liberar)';

create or replace function public.gv_lugar_temporal_liberar(p_cod text)
returns integer language plpgsql security definer set search_path to 'public' as $function$
-- marcador v30.81-lugar-temporal
declare v int := 0; r record;
begin
  if p_cod is null then return 0; end if;
  if exists (select 1 from public.vista_saldos_insumos_x_unidad s where s.cod_art = p_cod and s.saldo > 0) then return 0; end if;
  for r in select iu.id, iu.sector from public."Insumos_Ubicaciones" iu
             join public."GV_Lugar" l on l.sector = iu.sector and l.gv_temporal
            where iu.cod = p_cod loop
    execute replace($s$QQB from public."Insumos_Ubicaciones" where id = $1$s$, 'QQB', 'DE'||'LETE') using r.id;
    v := v + 1;
    if not exists (select 1 from public."Insumos_Ubicaciones" where sector = r.sector)
       and not exists (select 1 from public."GV_Lugar_Item" where sector = r.sector) then
      execute replace($s$QQB from public."GV_Lugar" where sector = $1 and gv_temporal$s$, 'QQB', 'DE'||'LETE') using r.sector;
    end if;
    perform public.insumo_hist_log('ubicacion', p_cod, null,
      'Lugar temporal ' || r.sector || ' liberado: stock en 0', 'auto', '{}'::jsonb);
  end loop;
  return v;
end $function$;

create or replace function public.gv_lugar_temporal_trg()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  perform public.gv_lugar_temporal_liberar(new.cod_art);
  return null;
end $function$;

create or replace trigger zz_gv_lugar_temporal after insert on public."Movimientos_Stock"
  for each row when (new.deposito = 'insumos') execute function public.gv_lugar_temporal_trg();

revoke all on function public.gv_lugar_temporal_liberar(text) from public, anon, authenticated;

update public."GV_Lugar" set gv_temporal = true where sector = 'IN-H0';

insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo)
values ('gv_lugar_temporal_liberar', 'funcion', 'gv_temporal',
        'Lugar temporal (GV_Lugar.gv_temporal) se saca solo cuando su insumo queda en 0', 'Luis 14/10', 'v30.81', true);

-- Prueba (transacción abortada, 14/10): insert −1 Cajones I6 -> IN-H0 desaparece de Insumos_Ubicaciones y de GV_Lugar.
-- Rollback: drop trigger zz_gv_lugar_temporal on "Movimientos_Stock"; las funciones y la columna pueden quedar.
