-- v16.60 — Problema 76: `wa_np_snapshot` fingía estar fresca
--
-- EL BUG, en una línea: el `coalesce` estaba **al revés**.
--
--   insert into public.wa_np_snapshot as s ...
--   on conflict (np) do update set
--     direccion = coalesce(s.direccion, excluded.direccion),   -- ⬅ s = la fila VIEJA
--     ...
--     updated_at = now();
--
-- `s` es el alias de la tabla DESTINO, así que eso significa *"si ya hay algo cargado, dejalo"*:
-- una vez que el valor dejaba de ser null **no se actualizaba nunca más**. Y como
-- `updated_at = now()` sí se pisaba en cada corrida (cron 64, cada hora), la fila **parecía
-- fresca** con el contenido del día en que se vio la NP por primera vez. Un dato viejo que se
-- presenta como nuevo es peor que un dato viejo: nadie lo va a dudar.
--
-- POR QUÉ IMPORTA: es el dato con el que se le avisa al cliente por WhatsApp adónde va el pedido.
--
-- MEDIDO al 2026-09-13, sobre las 133 NP que están en el snapshot y en la programación:
--
--   campo          divergencias antes   después
--   direccion              14              0
--   razon_social            7              0
--   barrio                  7              0
--   zona                    4              0
--
-- Caso testigo, la NP 98686:
--   snapshot antes  →  "Av. F. Lacroze  2481"   (Colegiales)
--   programación    →  "Av Corrientes  3864"    (Almagro)
--   snapshot ahora  →  "Av Corrientes  3864"    ✔
-- No era una variante de escritura: era otra dirección, en otro barrio.
--
-- EL ARREGLO: invertir el coalesce. Manda el valor NUEVO y el viejo queda sólo de respaldo
-- cuando el nuevo viene null, así un null de la programación no borra un dato bueno.
--
-- Se corrió la función una vez después de aplicar: 133 filas tocadas, las 265 filas del snapshot
-- siguen ahí (no se creó ni se borró ninguna), y las cuatro divergencias quedaron en 0.
--
-- BACKUPS:
--   zz_backups."GV_Backup_wa_np_snapshot_20260913"          (las 265 filas como estaban)
--   zz_backups."GV_Backup_wa_np_snapshot_run_ddl_20260913"  (la definición previa)

create or replace function public.wa_np_snapshot_run()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare n integer;
begin
  insert into public.wa_np_snapshot as s
    (np, cod_cliente, razon_social, direccion, barrio, zona, sucursal_entrega, metodo_pago)
  select
    p.np, p.cod, p.razon_social,
    nullif(btrim(p.direccion), ''),
    nullif(btrim(p.barrio), ''),
    nullif(btrim(p.zona), ''),
    v.sucursal_entrega, v.metodo_pago
  from public."GV_PPP_Programacion_Diaria" p
  left join public.vista_np_sucursal v on v.np = p.np
  where p.np ~ '^[0-9]+$'
  on conflict (np) do update set
    -- v16.60: el valor NUEVO manda; el viejo sólo si el nuevo viene null.
    direccion        = coalesce(excluded.direccion, s.direccion),
    barrio           = coalesce(excluded.barrio, s.barrio),
    zona             = coalesce(excluded.zona, s.zona),
    sucursal_entrega = coalesce(excluded.sucursal_entrega, s.sucursal_entrega),
    metodo_pago      = coalesce(excluded.metodo_pago, s.metodo_pago),
    razon_social     = coalesce(excluded.razon_social, s.razon_social),
    updated_at       = now();
  get diagnostics n = row_count;
  return n;
end;
$function$;

-- Chequeo (tiene que dar 0 en las cuatro columnas):
--   select count(*) comunes,
--    count(*) filter (where btrim(coalesce(s.direccion,'')) is distinct from coalesce(nullif(btrim(p.direccion),''),'')) dir,
--    count(*) filter (where btrim(coalesce(s.razon_social,'')) is distinct from btrim(coalesce(p.razon_social,''))) rs,
--    count(*) filter (where btrim(coalesce(s.barrio,'')) is distinct from coalesce(nullif(btrim(p.barrio),''),'')) barrio,
--    count(*) filter (where btrim(coalesce(s.zona,'')) is distinct from coalesce(nullif(btrim(p.zona),''),'')) zona
--   from public.wa_np_snapshot s join public."GV_PPP_Programacion_Diaria" p on p.np = s.np;
