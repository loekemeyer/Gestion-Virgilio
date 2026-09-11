-- v15.74 — Cuenta corriente con los proveedores chinos + las fechas de EMBARQUE del Excel de Thomas
-- Proyecto Supabase: hrxfctzncixxqmpfhskv — 2026-09-11
--
-- Thomas mandó la foto de su Excel ("estado actual de deudas al exterior"). Columnas:
--   A nombre de | Proveedor | FOB | Pago | Pend Giro Directo | Falta | Embarque   +   Fecha Pago 30% | Fecha Recup
-- Fórmulas que se leen en la planilla:
--   · Falta    = FOB − Pago − Pend Giro Directo
--   · Embarque = Fecha Pago 30% + lead time del PI   (la celda G3 es literalmente "=+I3+45")
--     Fujian +45, Zhixin +40, Ownland +60 (coincide con "60 days when deposit received" del PI),
--     Hugo +51, Frontier +62, Becky +112.
--   · "A nombre de" = quién emite la factura y cobra: NTL (el forwarder de Hong Kong) o el proveedor.
--     Sólo las filas a nombre del PROVEEDOR tienen "Pend Giro Directo" (lo que va girado derecho).
--   · "Fecha Recup" sólo aparece en las filas de NTL.
-- Marco de por qué se paga así: docs/IMPORTACIONES-PAGOS-ARGENTINA.md
--
-- Qué hace este script:
--   1) carga las 6 fechas de EMBARQUE del Excel en GV_Importados_Baches.fecha_embarque;
--   2) crea GV_Imp_Pedido_CC (la cabecera de plata de cada pedido) y GV_Imp_Pagos (cada giro);
--   3) crea la vista gv_imp_cuenta_corriente y las RPC para leer/escribir desde la app;
--   4) siembra las 6 filas con los números del Excel (1 pago por pedido = el 30% ya girado).
--
-- Backups: GV_Importados_Baches_bkp_cc_20260911 (tabla entera, antes de tocar fecha_embarque).

-- ---------- 0) BACKUP ----------
create table if not exists public."GV_Importados_Baches_bkp_cc_20260911" as
  select * from public."GV_Importados_Baches";

-- ---------- 1) fechas de EMBARQUE (del Excel) ----------
update public."GV_Importados_Baches" b
   set fecha_embarque = v.emb, actualizado = now()
  from (values
    ('Frontier 505C',     date '2026-10-26'),
    ('PI HT26-06-600-R1', date '2026-09-19'),
    ('PI BX260722D',      date '2026-10-14'),
    ('PI OL-10139',       date '2026-11-08'),
    ('PI B260601-2',      date '2026-09-22'),
    ('PI NY26-031438',    date '2026-09-19')
  ) as v(ref, emb)
 where b.pedido_ref = v.ref and b.estado = 'en_curso';
-- PI B260601 (Becky, llega 29/09) y "323ES suelto" no están en el Excel: sin deuda / fuera de la planilla.

-- ---------- 2) tablas ----------
-- Cabecera de plata por pedido. UNA fila por (pedido_ref, proveedor) — el mismo par que agrupa
-- gv_importados_pedidos_curso, así la cuenta corriente se cuelga del pedido sin duplicar nada.
create table if not exists public."GV_Imp_Pedido_CC" (
  id                bigserial primary key,
  pedido_ref        text not null,
  proveedor         text not null,
  a_nombre_de       text,                       -- quién factura y cobra: 'NTL' o el proveedor
  fob_total         numeric,                    -- el FOB del PI. null = usa el que calcula el motor
  pend_giro_directo numeric not null default 0, -- del saldo, lo que va girado derecho al proveedor
  fecha_pago_30     date,                       -- el anticipo/depósito. De acá sale el embarque
  fecha_recup       date,                       -- cuándo se recupera (sólo las filas de NTL)
  nota              text,
  creado            timestamptz not null default now(),
  actualizado       timestamptz not null default now(),
  unique (pedido_ref, proveedor)
);

-- Cada giro al exterior. El "Pago" del Excel es la SUMA de estos.
-- factura_ref / despacho_ref son la pata legal (contra qué se cursó el giro): ver el doc de pagos.
create table if not exists public."GV_Imp_Pagos" (
  id           bigserial primary key,
  pedido_ref   text not null,
  proveedor    text not null,
  fecha        date not null,
  monto_usd    numeric not null check (monto_usd > 0),
  beneficiario text,                            -- a quién se le giró: 'NTL' o el proveedor
  tipo         text not null default 'saldo'
    check (tipo in ('anticipo30', 'saldo', 'giro_directo')),
  factura_ref  text,
  despacho_ref text,
  nota         text,
  creado       timestamptz not null default now(),
  creado_por   text
);
create index if not exists gv_imp_pagos_pedido_idx on public."GV_Imp_Pagos" (pedido_ref, proveedor);

alter table public."GV_Imp_Pedido_CC" enable row level security;
alter table public."GV_Imp_Pagos"     enable row level security;
-- Sin policy para anon: se entra por las RPC SECURITY DEFINER de abajo, igual que los baches.

-- ---------- 3) vista + RPC ----------
create or replace view public.gv_imp_cuenta_corriente as
with pg as (
  select pedido_ref, proveedor, sum(monto_usd)::numeric as pagado, count(*)::int as n_pagos,
         max(fecha) as ultimo_pago
    from public."GV_Imp_Pagos" group by 1, 2
)
select
  c.pedido_ref, c.proveedor,
  cc.a_nombre_de,
  round(coalesce(cc.fob_total, c.usd), 2)                              as fob,
  round(coalesce(pg.pagado, 0), 2)                                     as pagado,
  round(coalesce(cc.pend_giro_directo, 0), 2)                          as pend_giro_directo,
  round(coalesce(cc.fob_total, c.usd) - coalesce(pg.pagado, 0)
        - coalesce(cc.pend_giro_directo, 0), 2)                        as falta,
  round(coalesce(cc.fob_total, c.usd) - coalesce(pg.pagado, 0), 2)     as saldo,   -- lo que falta girar en total
  coalesce(pg.n_pagos, 0)                                              as n_pagos,
  pg.ultimo_pago,
  cc.fecha_pago_30, cc.fecha_recup, cc.nota,
  c.fecha_embarque, c.fecha_llegada,
  (c.fecha_llegada - c.fecha_embarque)::int                            as dias_viaje,
  (c.fecha_embarque - cc.fecha_pago_30)::int                           as dias_produccion,
  c.n_lineas, c.pendiente as unidades, c.m3,
  round(c.usd, 2)                                                      as fob_calculado,
  (cc.fob_total is not null and round(cc.fob_total, 2) <> round(c.usd, 2)) as fob_difiere
from public.gv_importados_pedidos_curso c
left join public."GV_Imp_Pedido_CC" cc
       on cc.pedido_ref = c.pedido_ref and cc.proveedor = c.proveedor
left join pg on pg.pedido_ref = c.pedido_ref and pg.proveedor = c.proveedor;

alter view public.gv_imp_cuenta_corriente set (security_invoker = true);

create or replace function public.gv_imp_cc_lista()
returns setof public.gv_imp_cuenta_corriente
language sql stable security definer set search_path to 'public' as $fn$
  select * from public.gv_imp_cuenta_corriente
   order by coalesce(fecha_llegada, '9999-12-31'::date), proveedor, pedido_ref;
$fn$;

/* Editar la cabecera. Cada p_set_* distingue "no tocar" de "poner en null/0". */
create or replace function public.gv_imp_cc_set(
  p_pedido_ref text, p_proveedor text,
  p_a_nombre_de text default null, p_set_a_nombre_de boolean default false,
  p_fob numeric default null,      p_set_fob boolean default false,
  p_pend_giro numeric default null, p_set_pend_giro boolean default false,
  p_pago_30 date default null,     p_set_pago_30 boolean default false,
  p_recup date default null,       p_set_recup boolean default false,
  p_nota text default null,        p_set_nota boolean default false)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if coalesce(btrim(p_pedido_ref), '') = '' or coalesce(btrim(p_proveedor), '') = '' then
    raise exception 'pedido_ref y proveedor requeridos';
  end if;
  insert into public."GV_Imp_Pedido_CC" (pedido_ref, proveedor)
  values (btrim(p_pedido_ref), btrim(p_proveedor))
  on conflict (pedido_ref, proveedor) do nothing;

  update public."GV_Imp_Pedido_CC"
     set a_nombre_de       = case when p_set_a_nombre_de then nullif(btrim(coalesce(p_a_nombre_de, '')), '') else a_nombre_de end,
         fob_total         = case when p_set_fob         then p_fob        else fob_total end,
         pend_giro_directo = case when p_set_pend_giro   then coalesce(p_pend_giro, 0) else pend_giro_directo end,
         fecha_pago_30     = case when p_set_pago_30     then p_pago_30    else fecha_pago_30 end,
         fecha_recup       = case when p_set_recup       then p_recup      else fecha_recup end,
         nota              = case when p_set_nota        then nullif(btrim(coalesce(p_nota, '')), '') else nota end,
         actualizado = now()
   where pedido_ref = btrim(p_pedido_ref) and proveedor = btrim(p_proveedor)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $fn$;

create or replace function public.gv_imp_pagos(p_pedido_ref text, p_proveedor text default null)
returns table (id bigint, fecha date, monto_usd numeric, beneficiario text, tipo text,
               factura_ref text, despacho_ref text, nota text, creado timestamptz, creado_por text)
language sql stable security definer set search_path to 'public' as $fn$
  select id, fecha, monto_usd, beneficiario, tipo, factura_ref, despacho_ref, nota, creado, creado_por
    from public."GV_Imp_Pagos"
   where pedido_ref = p_pedido_ref and (p_proveedor is null or proveedor = p_proveedor)
   order by fecha, id;
$fn$;

create or replace function public.gv_imp_pago_add(
  p_pedido_ref text, p_proveedor text, p_fecha date, p_monto numeric,
  p_beneficiario text default null, p_tipo text default 'saldo',
  p_factura text default null, p_despacho text default null,
  p_nota text default null, p_legajo text default null)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if coalesce(btrim(p_pedido_ref), '') = '' or coalesce(btrim(p_proveedor), '') = '' then
    raise exception 'pedido_ref y proveedor requeridos';
  end if;
  if not (coalesce(p_monto, 0) > 0) then raise exception 'el monto debe ser > 0'; end if;
  insert into public."GV_Imp_Pagos"
    (pedido_ref, proveedor, fecha, monto_usd, beneficiario, tipo, factura_ref, despacho_ref, nota, creado_por)
  values (btrim(p_pedido_ref), btrim(p_proveedor), coalesce(p_fecha, current_date), p_monto,
          nullif(btrim(coalesce(p_beneficiario, '')), ''), coalesce(nullif(btrim(coalesce(p_tipo, '')), ''), 'saldo'),
          nullif(btrim(coalesce(p_factura, '')), ''), nullif(btrim(coalesce(p_despacho, '')), ''),
          nullif(btrim(coalesce(p_nota, '')), ''), nullif(btrim(coalesce(p_legajo, '')), ''))
  returning id into v_id;
  return jsonb_build_object('pago_id', v_id);
end $fn$;

create or replace function public.gv_imp_pago_borrar(p_pago_id bigint)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  delete from public."GV_Imp_Pagos" where id = p_pago_id;
  if not found then raise exception 'Pago % no existe', p_pago_id; end if;
  return jsonb_build_object('pago_id', p_pago_id, 'borrado', true);
end $fn$;

grant execute on function public.gv_imp_cc_lista()                                  to anon, authenticated;
grant execute on function public.gv_imp_cc_set(text,text,text,boolean,numeric,boolean,numeric,boolean,date,boolean,date,boolean,text,boolean) to anon, authenticated;
grant execute on function public.gv_imp_pagos(text, text)                           to anon, authenticated;
grant execute on function public.gv_imp_pago_add(text,text,date,numeric,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.gv_imp_pago_borrar(bigint)                         to anon, authenticated;

-- ---------- 4) SEED con el Excel de Thomas (11/09/2026) ----------
insert into public."GV_Imp_Pedido_CC"
  (pedido_ref, proveedor, a_nombre_de, fob_total, pend_giro_directo, fecha_pago_30, fecha_recup, nota)
values
  ('Frontier 505C',     'Frontier',  'NTL',       14400,       0, '2026-08-25', '2026-10-30', 'Excel de Thomas 11/09/2026'),
  ('PI HT26-06-600-R1', 'Fujian',    'NTL',       32388,       0, '2026-08-05', '2026-09-25', 'Excel de Thomas 11/09/2026'),
  ('PI BX260722D',      'Zhixin',    'NTL',       10273,       0, '2026-09-04', '2026-10-20', 'Excel de Thomas 11/09/2026'),
  ('PI OL-10139',       'Ownland',   'Ownland',   46626,   20956, '2026-09-09', null,         'Excel de Thomas 11/09/2026'),
  ('PI B260601-2',      'Becky',     'Becky',     31614,   22441, '2026-06-02', null,         'Excel de Thomas 11/09/2026'),
  ('PI NY26-031438',    'Hugo Wong', 'Hugo Wong', 38640,   21952, '2026-07-30', null,         'Excel de Thomas 11/09/2026')
on conflict (pedido_ref, proveedor) do nothing;

-- El "Pago" del Excel entra como UN giro por pedido, con la fecha del 30%. Cuando Thomas cargue
-- los giros reales (pueden ser varios), se borra el sembrado y quedan los de verdad.
insert into public."GV_Imp_Pagos"
  (pedido_ref, proveedor, fecha, monto_usd, beneficiario, tipo, nota, creado_por)
values
  ('Frontier 505C',     'Frontier',  '2026-08-25',  4320, 'NTL',       'anticipo30', 'Seed Excel 11/09: 30% exacto',                   'seed_excel_20260911'),
  ('PI HT26-06-600-R1', 'Fujian',    '2026-08-05', 10000, 'NTL',       'anticipo30', 'Seed Excel 11/09: 30,9% del FOB',                'seed_excel_20260911'),
  ('PI BX260722D',      'Zhixin',    '2026-09-04',  3100, 'NTL',       'anticipo30', 'Seed Excel 11/09: 30,2% del FOB',                'seed_excel_20260911'),
  ('PI OL-10139',       'Ownland',   '2026-09-09', 14000, 'Ownland',   'anticipo30', 'Seed Excel 11/09: 30,0% del FOB',                'seed_excel_20260911'),
  ('PI B260601-2',      'Becky',     '2026-06-02',  7359, 'Becky',     'anticipo30', 'Seed Excel 11/09: 23,3% del FOB (¿un solo giro?)', 'seed_excel_20260911'),
  ('PI NY26-031438',    'Hugo Wong', '2026-07-30', 14041, 'Hugo Wong', 'anticipo30', 'Seed Excel 11/09: 36,3% del FOB (¿un solo giro?)', 'seed_excel_20260911');

-- ---------- CHEQUEO ----------
-- select pedido_ref, proveedor, a_nombre_de, fob, pagado, pend_giro_directo, falta,
--        fecha_pago_30, fecha_embarque, fecha_llegada, dias_viaje
--   from public.gv_imp_cuenta_corriente order by fecha_llegada;
-- El "falta" tiene que dar: Frontier 10.080 · Fujian 22.388 · Zhixin 7.173 · Ownland 11.670
--                           Becky 1.814 · Hugo 2.647   (los mismos del Excel)
--
-- ---------- ROLLBACK ----------
--   drop view if exists public.gv_imp_cuenta_corriente cascade;
--   drop function if exists public.gv_imp_cc_lista(), public.gv_imp_pago_borrar(bigint);
--   drop function if exists public.gv_imp_cc_set(text,text,text,boolean,numeric,boolean,numeric,boolean,date,boolean,date,boolean,text,boolean);
--   drop function if exists public.gv_imp_pagos(text,text);
--   drop function if exists public.gv_imp_pago_add(text,text,date,numeric,text,text,text,text,text,text);
--   drop table if exists public."GV_Imp_Pagos", public."GV_Imp_Pedido_CC";
--   update public."GV_Importados_Baches" b set fecha_embarque = k.fecha_embarque
--     from public."GV_Importados_Baches_bkp_cc_20260911" k where k.id = b.id;
