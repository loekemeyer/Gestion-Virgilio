-- v17.14 (2026-09-14) — Problema 140: en Facturación, las NP armadas FUERA de la PPP
-- salían con la columna "Razón Social" VACÍA. Y de yapa: una de ellas estaba CANCELADA.
--
-- QUÉ VEÍA LUIS (pantalla Facturación, 14/09):
--
--   NP      ENTREGA     COD   RAZÓN SOCIAL
--   44500   2026-07-22  1768  (vacío)
--   98272   2026-08-14  2336  (vacío)
--
-- CAUSA RAÍZ (la de la razón social): la vista resolvía el nombre con un LEFT JOIN LATERAL
-- a `GV_Clientes_Direcciones` (el padrón), pero esa tabla tiene RLS con policy SELECT
-- **sólo para `authenticated`**:
--
--   select policyname, roles, cmd from pg_policies
--    where tablename = 'GV_Clientes_Direcciones';
--   -- gv_cli_dir_lectura | {authenticated} | SELECT
--
-- La vista es `security_invoker = true` (bien: así debe ser) y el front la lee con la
-- **anon key** pelada (`facSinTandaCargar()` en index.html manda `apikey`/`Authorization`
-- con SUPABASE_KEY, no con el JWT del supervisor). O sea: el join corre como `anon`, no ve
-- ni una fila del padrón, y `razon_social` queda NULL. Medido:
--
--   como postgres:  44500 → 'Ruiz Graciela Beatriz'      98272 → 'Cittadini Gerardo Alberto'
--   set role anon:  44500 → null                          98272 → null      ← lo que ve la app
--
-- No es un dato perdido: el nombre está en el padrón. Es un problema de permisos de lectura.
--
-- POR QUÉ NO SE ARREGLA DÁNDOLE LA POLICY A `anon`: `GV_Clientes_Direcciones` tiene
-- direcciones, localidad, CP y expreso de todos los clientes. La anon key viaja en el front,
-- o sea que abrirla es publicar el padrón de direcciones entero. Lo que la pantalla necesita
-- es UN nombre por NP, no el padrón.
--
-- SOLUCIÓN: una función SECURITY DEFINER acotada, `gv_fac_rs_np(np)`, que resuelve la razón
-- social SÓLO para una NP que (a) está en `Entregas_Virgilio` (o sea que se armó de verdad) y
-- (b) no está facturada — que son exactamente las filas que esta pantalla ya muestra. No se
-- puede enumerar el padrón con ella: por un cod cualquiera no devuelve nada, hay que tener la
-- NP armada y sin facturar.
--
-- SEGUNDO ARREGLO (el pendiente que dejó anotado §3.ea del 13/09): la vista **no excluía
-- `NP_Canceladas`**. La 44500 (Ruiz Graciela) se armó el 20/07 y el cliente la canceló el
-- 11/08; estaba en la lista de "pendiente de facturar" como si hubiera que facturarla.

-- ---------------------------------------------------------------------------------------
-- 1) Resolutor de razón social por NP. SECURITY DEFINER a propósito (lee el padrón), pero
--    con el ámbito cerrado a las NP armadas y sin facturar.
-- ---------------------------------------------------------------------------------------
create or replace function public.gv_fac_rs_np(p_np text)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with e as (
    select max(nullif(btrim(v.cod_cliente), '')) as cod
      from public."Entregas_Virgilio" v
     where btrim(v.np) = btrim(p_np)
    having max(nullif(btrim(v.cod_cliente), '')) is not null
  ), q as (
    select regexp_replace(e.cod, '\.0+$', '') as cod,
           public.gv_empresa_de_np_texto(btrim(p_np)) as empresa
      from e
     where not exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = btrim(p_np))
  )
  select coalesce(
           -- override del dueño primero (13/09: en la PPP va la razón social, no la fantasía)
           (select rs.razon_social from public."GV_Cliente_Razon_Social" rs, q
             where rs.cod = q.cod and rs.empresa = q.empresa),
           (select max(x.razon_social) from public."GV_Clientes_Direcciones" x, q
             where btrim(x.cod) = q.cod and lower(btrim(x.empresa)) = q.empresa)
         );
$$;

revoke all on function public.gv_fac_rs_np(text) from public;
grant execute on function public.gv_fac_rs_np(text) to anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- 2) La vista. Igual que la viva al 14/09, con dos cambios:
--      · el LATERAL a GV_Clientes_Direcciones (invisible para anon) → gv_fac_rs_np(np)
--      · se excluyen las NP de NP_Canceladas
-- ---------------------------------------------------------------------------------------
create or replace view public.gv_fac_armado_sin_facturar as
with ent as (
  select btrim(e.np) as np,
         max(nullif(btrim(e.tanda), '')) as tanda_armado,
         max(nullif(btrim(e.fecha_salida), '')) as fecha_salida,
         sum(coalesce(e.cajas_entregadas, 0)) as cajas,
         max(nullif(btrim(e.cod_cliente), '')) as cod
    from public."Entregas_Virgilio" e
   where nullif(btrim(e.np), '') is not null
   group by 1
), prog as (
  select btrim(d.np) as np,
         nullif(btrim(d.tanda), '') as tanda,
         d.razon_social,
         'isis'::text as origen,
         public.gv_empresa_de_np_texto(btrim(d.np)) as empresa
    from public.gv_ppp_programacion_diaria d
   where nullif(regexp_replace(coalesce(d.np, ''), '\D', '', 'g'), '') is not null
  union all
  select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         nullif(btrim(w.tanda), ''),
         w.razon_social,
         'web'::text,
         w.empresa
    from public."PPP_Web_Programacion" w
   where w.np is not null
)
select e.np,
       coalesce(p.origen, 'fuera de la PPP') as origen,
       e.cod,
       coalesce(p.razon_social, f.razon_social, public.gv_fac_rs_np(e.np)) as razon_social,
       e.tanda_armado,
       p.tanda as tanda_ppp,
       e.fecha_salida,
       e.cajas,
       (p.np is not null and p.tanda is not null) as se_ve_en_facturacion,
       case when p.np is null then 'la NP no esta en la PPP'
            when p.tanda is null then 'la NP esta en la PPP pero sin tanda'
            else null end as por_que_no_se_ve,
       coalesce(p.empresa, public.gv_empresa_de_np_texto(e.np)) as empresa
  from ent e
  left join prog p on p.np = e.np
  left join public."Facturacion_NP" f on btrim(f.np) = e.np
 where not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = e.np)
   and not exists (select 1 from public."NP_Canceladas" c
                    where regexp_replace(btrim(c.np), '\.0+$', '') = regexp_replace(e.np, '\.0+$', ''));

-- ⚠ CREATE OR REPLACE VIEW BORRA LAS reloptions. Reponer SIEMPRE (si no, la vista corre
--   como postgres y saltea la RLS — la causa de la filtración del 2026-09-04):
alter view public.gv_fac_armado_sin_facturar set (security_invoker = true);
grant select on public.gv_fac_armado_sin_facturar to anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- MEDICIÓN (antes / después), corrida como anon que es quien lee desde la app:
--
--   set local role anon;
--   select np, cod, razon_social from public.gv_fac_armado_sin_facturar
--    where se_ve_en_facturacion is false order by fecha_salida;
--
--   ANTES:  44500 | 1768 | null        98272 | 2336 | null
--   DESPUÉS: 44500 ya no aparece (cancelada 11/08)
--            98272 | 2336 | Cittadini Gerardo Alberto
--
-- ROLLBACK: volver a aplicar `sql/gv_fac_armado_sin_facturar_v1658.sql` (definición vieja,
-- sin el LATERAL y sin el filtro de canceladas) y después:
--   alter view public.gv_fac_armado_sin_facturar set (security_invoker = true);
--   drop function if exists public.gv_fac_rs_np(text);
