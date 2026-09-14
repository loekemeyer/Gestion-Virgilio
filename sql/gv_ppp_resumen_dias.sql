/* =====================================================================
   gv_ppp_resumen_dias — la PPP resumida POR DÍA, para el operario (v17.48)
   ---------------------------------------------------------------------
   Pedido del dueño (2026-09-14): "desde la botonera de los operarios, tengan
   un botón para ver la PPP" con el formato  Fecha ; Mt3 ; Tandas ; NPs.

   Por qué una VISTA y no que el front sume: el operario entra del celular.
   Bajar `gv_ppp_programacion_diaria` + `PPP_Web_Programacion` enteras para
   contar 4 números serían ~20k filas por apertura. Acá viaja UNA fila por día.
   Y es la regla del repo: la agregación es lógica de negocio → backend.

   Fuentes (las MISMAS dos que usa la PPP del supervisor):
     - public.gv_ppp_programacion_diaria  → ISIS (ya saltea las filas ocultas
       y las desprogramadas de GV_PPP_Prog_Override)
     - public."PPP_Web_Programacion"      → pedidos de la página ya programados
       (`tanda not null`, mismo filtro que `pppTraerWebProgramados`)
   Regla del dueño (v13.64): ISIS y web NO se muestran separados. Van sumados.

   Columnas: fecha (date) · dia (nombre en español) · m3 (2 dec) ·
             tandas (distintas) · nps (pedidos).
   Objeto NUEVO con prefijo gv_ y `security_invoker = true` (protocolo).
   Rollback:  drop view public.gv_ppp_resumen_dias;
   ===================================================================== */
create or replace view public.gv_ppp_resumen_dias
with (security_invoker = true) as
with isis as (
  select left(fecha_entrega, 10)::date          as fecha,
         'isis:' || np                          as np_key,
         nullif(btrim(coalesce(tanda, '')), '') as tanda,
         coalesce(m3, 0)                        as m3
    from public.gv_ppp_programacion_diaria
   where fecha_entrega ~ '^\d{4}-\d{2}-\d{2}'
), web as (
  select fecha_entrega                                       as fecha,
         'web:' || empresa || ':' || coalesce(np::text, 'o' || order_id::text || '-' || coalesce(np_idx, 1)::text) as np_key,
         nullif(btrim(coalesce(tanda, '')), '')              as tanda,
         coalesce(m3, 0)                                     as m3
    from public."PPP_Web_Programacion"
   where fecha_entrega is not null
     and nullif(btrim(coalesce(tanda, '')), '') is not null
), todo as (
  select * from isis
  union all
  select * from web
)
select fecha,
       (array['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'])
         [extract(dow from fecha)::int + 1]      as dia,
       round(sum(m3)::numeric, 2)                as m3,
       count(distinct tanda)::int                as tandas,
       count(distinct np_key)::int               as nps
  from todo
 group by fecha;

comment on view public.gv_ppp_resumen_dias is
  'PPP resumida por día (ISIS + web juntos): m³, tandas y NPs. La lee el botón 🗓️ PPP de la botonera del operario. v17.48.';

grant select on public.gv_ppp_resumen_dias to anon, authenticated;
