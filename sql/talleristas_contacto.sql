-- =====================================================================
-- talleristas_contacto.sql — Teléfonos de contacto de los talleristas (v7.59)
--
-- Los usa el IMPRESO de OC (index.html: ocLoadTels / ocTelDe) para poner el
-- teléfono DEBAJO del nombre del tallerista. Antes no había teléfonos en la base
-- (Ordenes_Compra.proveedor_telefono estaba vacío y la tabla Proveedores de ARCA
-- no es de talleristas), así que el dueño los pasó a mano y se cargan acá.
--
-- RLS: SOLO LECTURA para el front (anon + authenticated). NO hay política de
-- escritura: los teléfonos los administra un supervisor por SQL / migración
-- (service_role, que ignora RLS). Así una sesión anónima (rol authenticated en
-- este proyecto) no puede tocar la tabla. Mismo criterio "lo justo" del proyecto.
--
-- Notas de datos:
--   * "no se le manda" (Oscar, Pedernera) → sin teléfono: se les manda desde la
--     fábrica, no por WhatsApp. Quedan con telefono NULL + enviar_por_telefono=false.
--   * Manfer: "no existe más". Paternal Goma: "en pausa". → sin teléfono.
--   * Duales "Garcia / Lucho" y "Pintos / Maspoli": el impreso toma el número de
--     cualquiera de los dos (ocTelDe matchea por nombre normalizado). El número que
--     se pasó para "garcia/lucho" vino incompleto (+54911) → se dejó NULL.
-- =====================================================================

create table if not exists public."Talleristas_Contacto" (
  id bigint generated always as identity primary key,
  nombre text not null,
  telefono text,
  enviar_por_telefono boolean not null default true,
  nota text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists talleristas_contacto_nombre_uk on public."Talleristas_Contacto" (nombre);

alter table public."Talleristas_Contacto" enable row level security;

-- Solo lectura para el front (anon key). Escritura: service_role (SQL/migración).
drop policy if exists tc_select_all on public."Talleristas_Contacto";
create policy tc_select_all on public."Talleristas_Contacto"
  for select to anon, authenticated using (true);

grant select on public."Talleristas_Contacto" to anon, authenticated;
-- (sin grants de insert/update/delete a anon/authenticated a propósito)

-- Semilla / actualización idempotente de los teléfonos.
insert into public."Talleristas_Contacto" (nombre, telefono, enviar_por_telefono, nota) values
 ('Poly','+5491163615268', true, null),
 ('Lucho','+5491172228961', true, null),
 ('Martin C','+5491162498171', true, null),
 ('Pintos','+5491123370268', true, null),
 ('Carriero','+5491123214585', true, null),
 ('German','+5491139090976', true, null),
 ('Maspoli','+5491164895295', true, null),
 ('Tierra Nativa','+5491162521635', true, null),
 ('Carlos E','+5491159640984', true, null),
 ('Garcia','+5491144135992', true, null),
 ('Pettofrezza','+5491141499064', true, null),
 ('Lopez Jose','+5491123510085', true, null),
 ('The Plast','+5491153100328', true, null),
 ('Oscar', null, false, 'No se le manda por telefono: se le manda desde la fabrica'),
 ('Pedernera', null, false, 'No se le manda por telefono: se le manda desde la fabrica'),
 ('Paternal Goma', null, false, 'En pausa'),
 ('Manfer', null, false, 'No existe mas'),
 ('Garcia / Lucho', null, true, 'Dual (se reparte entre Garcia y Lucho). Numero dado incompleto (+54911); usa el de Garcia o Lucho'),
 ('Pintos / Maspoli', null, true, 'Dual (se reparte entre Pintos y Maspoli); usa el de Pintos o Maspoli')
on conflict (nombre) do update
  set telefono = excluded.telefono,
      enviar_por_telefono = excluded.enviar_por_telefono,
      nota = excluded.nota,
      activo = true,
      updated_at = now();
