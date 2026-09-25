-- v22.53 (Luis, 25/09): el Histórico de recepción sólo muestra lo que ya se cerró con Enviar.
-- `pendiente` = la entrega tiene su tarjeta todavía en Pendientes (Control_Modo_OP estado='pendiente').
create or replace view public.vista_historial_entregas with (security_invoker = true) as
 SELECT 'tallerista'::text AS fuente,
    gv_fecha_recepcion_norm(t."Fecha") AS fecha,
    t.created_at,
    t."Cod" AS cod_art,
    ''::text AS descripcion,
    t."Cajas"::numeric AS cajas,
    t."Nombre_Tall" AS quien,
    t."Remito" AS remito,
    cmo.llegada,
    cmo.carga,
        CASE
            WHEN cmo.llegada IS NOT NULL AND cmo.carga IS NOT NULL THEN round(EXTRACT(epoch FROM cmo.carga - cmo.llegada) / 3600.0, 2)
            ELSE NULL::numeric
        END AS demora_hs,
    cmo.recibido_por,
    cmo.recibido_at,
    (EXISTS ( SELECT 1 FROM "Control_Modo_OP" c2
          WHERE c2.estado = 'pendiente'::text AND NULLIF(btrim(c2.remito), ''::text) = NULLIF(btrim(t."Remito"), ''::text) AND lower(btrim(c2.nombre)) = lower(btrim(t."Nombre_Tall")))) AS pendiente
   FROM "Entregas Tallerista Virgilio" t
     LEFT JOIN LATERAL ( SELECT c.created_at AS llegada,
            c.procesado_at AS carga,
            c.gv_recibido_por AS recibido_por,
            c.gv_recibido_at AS recibido_at
           FROM "Control_Modo_OP" c
          WHERE c.estado = 'procesado'::text AND c.procesado_at IS NOT NULL AND NULLIF(btrim(c.remito), ''::text) = NULLIF(btrim(t."Remito"), ''::text) AND lower(btrim(c.nombre)) = lower(btrim(t."Nombre_Tall"))
          ORDER BY c.procesado_at DESC
         LIMIT 1) cmo ON true
UNION ALL
 SELECT 'prov_at'::text AS fuente,
    gv_fecha_recepcion_norm(p."Dia_mes") AS fecha,
    NULL::timestamp with time zone AS created_at,
    p."Cod_Art" AS cod_art,
    COALESCE(p."Descripcion", ''::text) AS descripcion,
    p."Cantidad"::numeric AS cajas,
    p."Proveedor" AS quien,
    p."Remito" AS remito,
    cmo.llegada,
    cmo.carga,
        CASE
            WHEN cmo.llegada IS NOT NULL AND cmo.carga IS NOT NULL THEN round(EXTRACT(epoch FROM cmo.carga - cmo.llegada) / 3600.0, 2)
            ELSE NULL::numeric
        END AS demora_hs,
    cmo.recibido_por,
    cmo.recibido_at,
    (EXISTS ( SELECT 1 FROM "Control_Modo_OP" c2
          WHERE c2.estado = 'pendiente'::text AND NULLIF(btrim(c2.remito), ''::text) = NULLIF(btrim(p."Remito"), ''::text) AND lower(btrim(c2.nombre)) = lower(btrim(p."Proveedor")))) AS pendiente
   FROM "Entregas Prov AT" p
     LEFT JOIN LATERAL ( SELECT c.created_at AS llegada,
            c.procesado_at AS carga,
            c.gv_recibido_por AS recibido_por,
            c.gv_recibido_at AS recibido_at
           FROM "Control_Modo_OP" c
          WHERE c.estado = 'procesado'::text AND c.procesado_at IS NOT NULL AND NULLIF(btrim(c.remito), ''::text) = NULLIF(btrim(p."Remito"), ''::text) AND lower(btrim(c.nombre)) = lower(btrim(p."Proveedor"))
          ORDER BY c.procesado_at DESC
         LIMIT 1) cmo ON true;
alter view public.vista_historial_entregas set (security_invoker = true);

-- Nombres de quién recibe (los que se agregan con «Otro…» quedan como opción).
create table if not exists public."GV_Recepcion_Receptores" (
  nombre text primary key,
  creado_por text,
  created_at timestamptz not null default now()
);
alter table public."GV_Recepcion_Receptores" enable row level security;
revoke update, delete, truncate on public."GV_Recepcion_Receptores" from anon, authenticated;
grant select, insert on public."GV_Recepcion_Receptores" to anon, authenticated;
drop policy if exists gv_rr_sel on public."GV_Recepcion_Receptores";
drop policy if exists gv_rr_ins on public."GV_Recepcion_Receptores";
create policy gv_rr_sel on public."GV_Recepcion_Receptores" for select to anon, authenticated using (true);
create policy gv_rr_ins on public."GV_Recepcion_Receptores" for insert to anon, authenticated
  with check (length(btrim(nombre)) between 1 and 40);

-- 38868 (Log/ Fabr) se cerró con el «Recibido» viejo sin ISIS ni partes: vuelve a Pendientes (pedido de Luis).
update public."Control_Modo_OP" set estado='pendiente', procesado_at=null where id=459;
