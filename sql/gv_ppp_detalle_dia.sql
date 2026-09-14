/* =====================================================================
   gv_ppp_detalle_dia — QUÉ SALE cada día, pedido por pedido (v17.54)
   ---------------------------------------------------------------------
   Dueño (2026-09-14): "debe poder clickear sobre el día y ver la composición
   de lo que sale ese día. Cuando entra que vea ordenado x número de NP".

   Es el detalle de `gv_ppp_resumen_dias` (§3.ff): las MISMAS dos fuentes, el
   mismo criterio, una fila por pedido en vez de una por día. Si los números de
   las dos vistas no coinciden, una de las dos está mal — se arman igual a
   propósito.

   Orden: `np_num` (el número pelado de la NP) ascendente. Las NP web son un
   contador propio de 4 dígitos (v13.70) y las de ISIS tienen 5, así que la web
   queda primero. `np` es la etiqueta que ve el operario ("LK 0028", "98704"),
   armada con `gv_ppp_web_np_label` — la MISMA función que usa el front, para
   que no se dupliquen dos maneras de escribir lo mismo.

   Objeto NUEVO con prefijo gv_ y `security_invoker = true` (protocolo).
   Rollback:  drop view public.gv_ppp_detalle_dia;
   ===================================================================== */
create or replace view public.gv_ppp_detalle_dia
with (security_invoker = true) as
with isis as (
  select left(fecha_entrega, 10)::date                     as fecha,
         np                                                as np,
         nullif(regexp_replace(coalesce(np, ''), '\D', '', 'g'), '')::numeric as np_num,
         coalesce(nullif(btrim(coalesce(tanda, '')), ''), '—')                as tanda,
         coalesce(m3, 0)                                   as m3,
         coalesce(btrim(cod), '')                          as cod,
         coalesce(btrim(razon_social), '')                 as razon_social,
         coalesce(nullif(btrim(coalesce(barrio, '')), ''), btrim(coalesce(direccion, ''))) as localidad,
         coalesce(btrim(zona), '')                         as zona,
         'isis'::text                                      as origen
    from public.gv_ppp_programacion_diaria
   where fecha_entrega ~ '^\d{4}-\d{2}-\d{2}'
), web as (
  select fecha_entrega                                     as fecha,
         case when np is null
              then (case when lower(coalesce(empresa, '')) in ('chef', 'ch') then 'CH' else 'LK' end
                    || ' pedido ' || order_id::text)
              else public.gv_ppp_web_np_label(empresa, np, np_idx) end        as np,
         coalesce(np, order_id)::numeric                   as np_num,
         coalesce(nullif(btrim(coalesce(tanda, '')), ''), '—')                as tanda,
         coalesce(m3, 0)                                   as m3,
         coalesce(btrim(cod_cliente), '')                  as cod,
         coalesce(btrim(razon_social), '')                 as razon_social,
         coalesce(nullif(btrim(coalesce(barrio, '')), ''), btrim(coalesce(direccion, ''))) as localidad,
         coalesce(btrim(zona), '')                         as zona,
         'web'::text                                       as origen
    from public."PPP_Web_Programacion"
   where fecha_entrega is not null
     and nullif(btrim(coalesce(tanda, '')), '') is not null
)
select * from isis
union all
select * from web;

comment on view public.gv_ppp_detalle_dia is
  'Detalle de la PPP por dia: una fila por pedido (NP, cliente, tanda, m3), ISIS + web. Lo abre el boton PPP de la botonera del operario al tocar un dia. Ordenar por np_num. v17.54.';

grant select on public.gv_ppp_detalle_dia to anon, authenticated;
