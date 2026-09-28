-- v23.03 (2026-09-28, Luis) — problema 77: cod_cliente sin empresa en vendedor y teléfono.
-- clientes_vendedor y whatsapp_clientes no tienen empresa (foto manual del padrón de LK del
-- 11/08). A 244 clientes de Chef les tocaba el vendedor del cliente de LK con ese mismo número.
-- La fuente real es el padrón de cada página (customers.vend / customers.whatsapp de LK y de Chef),
-- que ahora trae sync-clientes-dto cada 15 min a GV_Clientes_Contacto.
-- APLICADO en la base el 28/09. Backup de las 3 definiciones previas:
--   zz_backups."GV_Backup_defs_contacto_20260928" (obj, def).

create table if not exists public."GV_Clientes_Contacto" (
  empresa text not null check (empresa in ('lk','chef')),
  cod_cliente text not null,
  vend text,
  whatsapp text,
  actualizado timestamptz not null default now(),
  primary key (empresa, cod_cliente)
);
alter table public."GV_Clientes_Contacto" enable row level security;
revoke insert, update, delete, truncate on public."GV_Clientes_Contacto" from anon, authenticated;
create policy gvcc_sel on public."GV_Clientes_Contacto" for select to anon, authenticated using (true);

-- Vendedor y teléfono resueltos por (empresa, cod). Teléfono: GV_Clientes_Whatsapp de la empresa
-- > whatsapp de la página > whatsapp_clientes SÓLO si el código no existe en la otra empresa
-- (ahí la empresa queda determinada; si existe en las dos, no se adivina: queda vacío).
create or replace view public.gv_cliente_contacto with (security_invoker = true) as
select c.empresa, c.cod_cliente as cod, nullif(btrim(c.vend),'') as vend,
  coalesce(nullif(btrim(w.telefono),''), nullif(btrim(c.whatsapp),''),
           case when not amb.dos then nullif(btrim(wc.telefono),'') end) as telefono,
  case when nullif(btrim(w.telefono),'') is not null then 'padron_empresa'
       when nullif(btrim(c.whatsapp),'') is not null then 'pagina'
       when not amb.dos and nullif(btrim(wc.telefono),'') is not null then 'historico'
       else '' end as tel_origen
from public."GV_Clientes_Contacto" c
cross join lateral (select exists (select 1 from public."GV_Clientes_Contacto" o
                                    where o.cod_cliente = c.cod_cliente and o.empresa <> c.empresa) as dos) amb
left join lateral (select x.telefono from public."GV_Clientes_Whatsapp" x
                    where lower(btrim(x.empresa)) in (c.empresa, case c.empresa when 'chef' then 'ch' else c.empresa end)
                      and btrim(x.cod_cliente) = c.cod_cliente and nullif(btrim(x.telefono),'') is not null limit 1) w on true
left join lateral (select y.telefono from public.whatsapp_clientes y
                    where btrim(y.cod_cliente) = c.cod_cliente and nullif(btrim(y.telefono),'') is not null limit 1) wc on true;

-- Consumidores repuntados (reemplazo por texto sobre la definición viva, con raise si no matchea):
--   gv_cuar_contacto_lote       : clientes_vendedor/whatsapp_clientes por cod  -> gv_cliente_contacto por (empresa, cod)
--   vista_plata_perdida         : clientes_vendedor por cod                    -> gv_cliente_contacto (empresa de la NP)
--   vista_avisar_programacion   : vendedor por (empresa del grupo, cod); el teléfono histórico sólo si el código es de una sola empresa
-- Medido: LK igual que antes salvo 28 filas de clientes dados de alta después del 11/08 (la foto vieja no los tenía);
-- Chef: 210 de 215 filas de plata perdida cambian de vendedor (tenían el del cliente de LK).
--
-- Rollback: recrear las 3 definiciones desde zz_backups."GV_Backup_defs_contacto_20260928".
