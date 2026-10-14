-- gv_fac_xls_sucursal — col H (sucursal) del Excel ISIS desde el PADRÓN VIVO, no desde la etiqueta
-- con la que entró el pedido.
--
-- Luis, 14/10/2026 (cliente LK 4142, Poy Ignacio, NP LK 0367 / LK 0368): la col H salió
-- «Poy Ignacio — ROJAS» en vez de la dirección. El importador de Excel de Krikos de la página LK
-- (admin-excel-krikos.js / vendor-import-excel.js) arma `sucursal_entrega` = razón social + « — » +
-- encabezado de la columna del Excel, y el Facturador lo copiaba tal cual. Luis: *"que no se
-- condicione eso desde que manda el pedido el cliente sino que esté armado con la información más
-- en vivo posible"*.
--
-- Qué devuelve, por NP web (LK y CH):
--   · como = 'padron' → la etiqueta de la dirección del padrón (`GV_Clientes_Direcciones`) que mejor
--     matchea la NP (mismo puntaje que el destino de la Programación, `gv_destino_score`), cuando hay
--     UNA sola etiqueta con el puntaje máximo y ese máximo es > 0.
--   · como = 'unica'  → el cliente tiene una sola dirección en el padrón (y la NP no es Retira).
--   · como = 'ambiguo' / 'sin padron' → sucursal NULL: el front NO adivina (v24.76) y cae a la
--     etiqueta del pedido, salvo que sea del formato «Razón — X», que deja vacía y avisa.
--
-- El padrón lo llena `gv-sync-padron-direcciones` (LK + Chef). El front lo dispara justo antes de
-- armar el Excel para que salga con la dirección vigente de ese momento.
--
-- SECURITY DEFINER porque `GV_Clientes_Direcciones` tiene RLS y la clave pública no la ve. Devuelve
-- sólo la etiqueta de las NP que se piden (la misma dirección que ya expone
-- `PPP_Web_Programacion.direccion`): ni CUIT, ni el padrón entero.

create or replace function public.gv_fac_xls_sucursal(p_nps text[])
returns table(np text, sucursal text, como text)
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  -- marcador: fac-xls-suc-padron-v3076
  with w as (
    select distinct on (gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
           gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
           lower(btrim(coalesce(w.empresa, ''))) as emp,
           btrim(coalesce(w.cod_cliente, ''))    as cod,
           w.direccion, w.barrio
      from public."PPP_Web_Programacion" w
     where gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) = any (
             select upper(regexp_replace(btrim(x), '\.0+$', '')) from unnest(p_nps) x)
     order by gv_ppp_web_np_label(w.empresa, w.np, w.np_idx), w.direccion
  ), q as (
    select w.*,
           (regexp_match(coalesce(w.direccion, ''), '^Exp\.\s*(.+?)\s+—\s'))[1]                                as x_exp,
           (regexp_match(coalesce(w.direccion, ''), '—\s*(.*?)\s*\((?:[^()]|\([^()]*\))*\)\s*$'))[1]            as x_dirx,
           (regexp_match(coalesce(w.direccion, ''), '\(((?:[^()]|\([^()]*\))*)\)\s*$'))[1]                       as x_lab,
           (coalesce(btrim(w.direccion), '') ~* '^retira$'
             or coalesce(w.direccion, '') ~* '^\s*exp\.\s*retira([^a-záéíóúñ]|$)'
             or coalesce(w.direccion, '') ~* 'virgilio\s*2788')                                                  as es_retira
      from w
  ), c as (
    select q.np, q.es_retira, d.etiqueta,
           public.gv_destino_score(d.etiqueta, d.direccion, d.dir_key, d.nombre_expreso, d.dir_expreso,
                                   d.localidad, q.direccion, q.barrio, q.x_exp, q.x_dirx, q.x_lab) as sc
      from q
      left join public."GV_Clientes_Direcciones" d
        on d.empresa = q.emp and btrim(d.cod) = q.cod and nullif(btrim(d.etiqueta), '') is not null
  ), a as (
    select c.np, bool_or(c.es_retira) as es_retira, max(c.sc) as mx,
           count(distinct c.etiqueta) as n_et
      from c group by c.np
  ), t as (
    select c.np, count(distinct c.etiqueta) as n_top, min(c.etiqueta) as et_top
      from c join a using (np)
     where c.etiqueta is not null and c.sc = a.mx
     group by c.np
  )
  select a.np,
         case when a.mx > 0 and t.n_top = 1          then btrim(t.et_top)
              when a.n_et = 1 and not a.es_retira    then btrim(t.et_top)
         end,
         case when a.n_et = 0                        then 'sin padron'
              when a.mx > 0 and t.n_top = 1          then 'padron'
              when a.n_et = 1 and not a.es_retira    then 'unica'
              else 'ambiguo' end
    from a left join t using (np);
$function$;

revoke all on function public.gv_fac_xls_sucursal(text[]) from public;
grant execute on function public.gv_fac_xls_sucursal(text[]) to anon, authenticated, service_role;
