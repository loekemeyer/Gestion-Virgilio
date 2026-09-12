-- v16.21 (2026-09-12) — UNA sola tabla de UxB: se elimina cob_uxb_lk
--
-- Pedido del dueño: "Ahora quiero que empieces a eliminar tablas, primero redirigiendo el
-- codigo que las usa a una sola."
--
-- QUÉ ERA cob_uxb_lk: NO era una tabla muerta. La reescribía entera, en cada corrida del
-- cron, la Edge Function `sync-precios-venta`, copiando el uxb del catálogo de LK
-- (products ∪ loke_products ∪ item_precios manual). Por eso el arreglo del v16.18 sobre esa
-- tabla se hubiera revertido solo en la corrida siguiente.
--
-- EL BUG QUE ARRASTRABA: en el catálogo de LK, uxb = 1 es el placeholder de "no sé". Viajaba
-- tal cual a cob_uxb_lk y de ahí a Facturación, que terminaba cobrando UNIDADES donde iban
-- CAJAS. Testigo: 029 Colador Ø16 — 5 cajas × 24 u × $7.790 se facturaban como 5 × 1 × $7.790.
-- 24 códigos afectados; al corregirlo, vista_facturacion_neto_items sube $2.685.467 (+0,19 %).
--
-- CÓMO QUEDÓ:
--   GV_UxB (empresa, cod) es la ÚNICA tabla de UxB. cod se guarda siempre normalizado con
--   gv_cod_stock, así el '029' del sync de LK y el '29' del listado de Thomas caen en la
--   MISMA fila en vez de duplicarse.
--   · gv_uxb_lk        → vista (cod, uxb) sobre GV_UxB empresa='LK'. Reemplaza a la tabla con
--                        el mismo contrato, así las 4 vistas de negocio no se tocaron por dentro.
--   · curado           → columna nueva. true = lo decidió Thomas o una resolución manual.
--   · trigger gv_uxb_protege_curado → el sync (origen 'sync_lk') NO pisa una fila curada.
--   · trigger gv_uxb_normaliza_cod  → normaliza el cod en cada insert/update.
--   · uxb pasa a ser NULLABLE: "no tengo el dato" ya no se escribe como 1. Los 21 casos
--     quedan listados en gv_uxb_sin_dato.
--
-- CENTINELA: select count(*) from public.gv_uxb_desalineado;  -- tiene que dar 0
--            (al 12/09 da 4, todas del cod 067: LK dice 50 y otras tres tablas 60. Está sin
--             resolver a propósito, esperando a Thomas.)
--
-- BACKUPS de esta corrida:
--   GV_Redir_bkp_20260912        (cob_uxb_lk, proyeccion_madre, OC_Maximos, precios_venta)
--   GV_UxB_bkp_prenorm_20260912  (GV_UxB antes de normalizar el cod)
--   GV_UxB_pre_sync_20260912     (GV_UxB antes de la primera corrida del sync nuevo)
--   GV_Viewdefs_bkp_20260912b    (definición + grants de las 7 vistas tocadas)
--   GV_Baseline_20260912         (filas e importes de las vistas de negocio, antes)
--
-- ROLLBACK: ver docs/ROLLBACK-PRODUCCION.md, entrada v16.21.

-- ── 1) GV_UxB: uxb nullable, curado, normalización del cod ──
alter table public."GV_UxB" alter column uxb drop not null;
alter table public."GV_UxB" add constraint gv_uxb_positiva check (uxb is null or uxb > 0);
alter table public."GV_UxB" add column if not exists curado boolean not null default false;

update public."GV_UxB" set curado = true
 where origen in ('thomas_20260912','Thomas 12/09/2026 (corrige el listado)')
    or origen ilike 'regla del dueno%' or origen ilike 'dual %'
    or origen ilike 'por empresa desde Articulos_Cajas%';

create or replace function public.gv_uxb_normaliza_cod() returns trigger
language plpgsql as $$
begin
  new.cod := public.gv_cod_stock(new.cod);
  return new;
end $$;

create or replace function public.gv_uxb_protege_curado() returns trigger
language plpgsql as $$
begin
  -- el sync automático (origen 'sync_lk') nunca pisa una fila curada a mano
  if tg_op = 'UPDATE' and old.curado and coalesce(new.origen,'') like 'sync\_%' then
    new.uxb := old.uxb;
    new.origen := old.origen;
    new.curado := true;
    new.actualizado := old.actualizado;
  end if;
  return new;
end $$;

-- ojo con el orden: los BEFORE corren alfabéticamente, así que normaliza_cod va primero
drop trigger if exists gv_uxb_normaliza_cod_trg on public."GV_UxB";
create trigger gv_uxb_normaliza_cod_trg before insert or update on public."GV_UxB"
for each row execute function public.gv_uxb_normaliza_cod();

drop trigger if exists gv_uxb_protege_curado_trg on public."GV_UxB";
create trigger gv_uxb_protege_curado_trg before update on public."GV_UxB"
for each row execute function public.gv_uxb_protege_curado();

-- colapsar las grafías duplicadas (31L/031, 34L/034, 35EL/035E, 58L/058, 59L/059, 66L/066:
-- misma uxb en las dos, así que no se pierde nada) y normalizar lo que quedó
delete from public."GV_UxB" a
 where exists (select 1 from public."GV_UxB" b
                where b.empresa=a.empresa and b.cod<>a.cod
                  and public.gv_cod_stock(b.cod)=public.gv_cod_stock(a.cod)
                  and (b.curado, coalesce(b.uxb,-1), b.cod) > (a.curado, coalesce(a.uxb,-1), a.cod));
update public."GV_UxB" set cod = public.gv_cod_stock(cod) where cod <> public.gv_cod_stock(cod);

-- ── 2) la vista que reemplaza a la tabla, con el mismo contrato (cod, uxb integer) ──
create or replace view public.gv_uxb_lk with (security_invoker = true) as
  select cod, uxb::int as uxb from public."GV_UxB" where empresa = 'LK' and uxb is not null;
grant select on public.gv_uxb_lk to anon, authenticated, service_role, lk_ppp_reader;

-- ── 3) repuntar los 7 consumidores: create or replace, sin drops, así los tipos de columna
--      quedan idénticos y las 4 vistas de negocio no cambian ni una fila ──
--   gv_uxb_resuelto · gv_uxb_desalineado · gv_articulo_empresa · cobranzas_precios_super
--   vista_plata_perdida · vista_facturacion_neto_items · vista_facturable_anticipado
-- (se hizo con un DO que reemplaza el texto 'cob_uxb_lk' → 'gv_uxb_lk' en pg_get_viewdef;
--  la definición previa de cada una está en GV_Viewdefs_bkp_20260912b)

-- ── 4) los que quedaron sin dato real (venían con el placeholder 1) ──
create or replace view public.gv_uxb_sin_dato with (security_invoker = true) as
select empresa, cod, descripcion, origen from public."GV_UxB" where uxb is null order by empresa, cod;
grant select on public.gv_uxb_sin_dato to anon, authenticated, service_role;

-- ── 5) recién ahora se puede borrar la tabla ──
drop table public.cob_uxb_lk;

-- ── verificación ──
-- select count(*) from public.gv_uxb_desalineado;   -- 0 salvo el 067 sin resolver
-- select * from public.gv_uxb_sin_dato;             -- 21
-- select to_regclass('public.cob_uxb_lk');          -- null
