-- v22.58 (Luis, 25/09): los nombres de quién recibe / quién agrega la foto van capitalizados
-- ("pablo" -> "Pablo", "juan  cruz" -> "Juan Cruz"). Aplicado el 25/09.
create or replace function public.gv_nombre_capitalizar(p text) returns text
language sql immutable set search_path = public as $$
  select nullif(initcap(lower(regexp_replace(btrim(coalesce(p,'')), '\s+', ' ', 'g'))), '')
$$;
create or replace function public.gv_recepcion_receptores_norm() returns trigger
language plpgsql set search_path = public as $$
begin new.nombre := public.gv_nombre_capitalizar(new.nombre); return new; end $$;
drop trigger if exists gv_recepcion_receptores_norm on public."GV_Recepcion_Receptores";
create trigger gv_recepcion_receptores_norm before insert or update on public."GV_Recepcion_Receptores"
  for each row execute function public.gv_recepcion_receptores_norm();
-- sólo toca las columnas gv_ que escribe Gestión
create or replace function public.gv_control_modo_op_nombres() returns trigger
language plpgsql set search_path = public as $$
begin
  new.gv_recibido_por  := public.gv_nombre_capitalizar(new.gv_recibido_por);
  new.gv_foto_post_por := public.gv_nombre_capitalizar(new.gv_foto_post_por);
  return new;
end $$;
drop trigger if exists gv_control_modo_op_nombres on public."Control_Modo_OP";
create trigger gv_control_modo_op_nombres before insert or update of gv_recibido_por, gv_foto_post_por
  on public."Control_Modo_OP" for each row execute function public.gv_control_modo_op_nombres();
-- datos: "mel" -> "Mel" (backup zz_backups."GV_Backup_Recep_Prueba_477_20260925")
update public."GV_Recepcion_Receptores" set nombre = nombre;
update public."Control_Modo_OP" set gv_recibido_por = gv_recibido_por where gv_recibido_por is not null;
-- recepción de prueba del legajo 1 (Poly, RTO 1, 066 x 1) anulada con la misma función del botón:
-- select public.anular_modo_op(477);
-- rollback triggers: drop trigger gv_control_modo_op_nombres on public."Control_Modo_OP";
--                    drop trigger gv_recepcion_receptores_norm on public."GV_Recepcion_Receptores";
