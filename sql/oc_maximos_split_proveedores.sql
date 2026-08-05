-- =====================================================================
-- oc_maximos_split_proveedores.sql — Reparto de OCs por 2 proveedores (v7.66)
--
-- Pedido del usuario (cierra la idea 1382): que cada artículo pueda repartirse
-- proporcionalmente entre DOS talleristas al generar las OCs (los "duales" como
-- el 123 = Garcia/Lucho). La proporción se edita en Configuraciones (la pantalla
-- del generador de OCs) y el generador (app + cron) parte el "a pedir" en dos
-- líneas, una por tallerista.
--
-- MODELO:
--   OC_Maximos.proveedor      = Proveedor 1
--   OC_Maximos.prop_prov1      = % Prov 1 (default 100)
--   OC_Maximos.proveedor2      = Proveedor 2 (nullable)
--   OC_Maximos.prop_prov2      = % Prov 2 (default 0)
--   (los dos % tienen que sumar 100; artículo de un solo proveedor = 100% al 1)
--
-- REGISTRO DE PROVEEDORES = Talleristas_Contacto (los desplegables de Proveedor 1/2
--   salen de ahí). Col nueva `es_proveedor_oc` para excluir del desplegable los
--   rótulos duales viejos ("Garcia / Lucho", "Pintos / Maspoli"). Se agregaron
--   Kuffo, Log/ Fabr y Racks como proveedores. Se re-habilitó la escritura para
--   authenticated (el botón "➕ Agregar proveedor" del editor).
--
-- La lógica de reparto en el cron está en generar_ocs_automaticas.sql /
-- simular_ocs_automaticas.sql (CTEs falta → split). Este archivo es solo el DDL.
-- =====================================================================

alter table public."OC_Maximos"
  add column if not exists prop_prov1 numeric,
  add column if not exists proveedor2 text,
  add column if not exists prop_prov2 numeric;
update public."OC_Maximos" set prop_prov1 = 100 where prop_prov1 is null;
update public."OC_Maximos" set prop_prov2 = 0   where prop_prov2 is null;

-- Migrar los duales existentes "X / Y" → Prov 1 = X (50%), Prov 2 = Y (50%).
-- OJO: "Log/ Fabr" tiene "/" pero NO es dual (es la fábrica) → se excluye.
update public."OC_Maximos"
   set proveedor2 = btrim(split_part(proveedor, '/', 2)),
       proveedor  = btrim(split_part(proveedor, '/', 1)),
       prop_prov1 = 50, prop_prov2 = 50
 where proveedor like '%/%'
   and upper(btrim(proveedor)) not in ('LOG/ FABR', 'LOG/FABR', 'LOG/ FABRICA');

-- Talleristas_Contacto = registro de proveedores del generador.
alter table public."Talleristas_Contacto"
  add column if not exists es_proveedor_oc boolean not null default true;
update public."Talleristas_Contacto" set es_proveedor_oc = false where nombre like '%/%';
insert into public."Talleristas_Contacto" (nombre, telefono, enviar_por_telefono, nota, activo, es_proveedor_oc) values
 ('Kuffo', null, false, 'Proveedor OC (sin telefono cargado)', true, true),
 ('Log/ Fabr', null, false, 'Fabrica (interno): genera OC pero no se le manda por telefono', true, true),
 ('Racks', null, false, 'Importacion: se abastece por otra via (excluido del generador)', true, true)
on conflict (nombre) do update set es_proveedor_oc = true, activo = true;

-- El editor de config agrega/edita proveedores desde la app (supervisor = authenticated).
drop policy if exists tc_write_auth on public."Talleristas_Contacto";
create policy tc_write_auth on public."Talleristas_Contacto" for all to authenticated using (true) with check (true);
grant insert, update, delete on public."Talleristas_Contacto" to authenticated;
