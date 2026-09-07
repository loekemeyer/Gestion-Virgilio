-- gv_ppp_super_mezclado — v14.23 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- LA REGLA
-- ========
--     "Súper no se puede juntar con clientes. Ya tenías esa regla. Van separados."  (dueño, 07/09)
--
-- Y era cierto: **el armado automático ya la respetaba**. `gv_ppp_web_camion_del_dia` sólo
-- considera reutilizar camiones cuya zona no sea súper (`zona !~* 'super|retira|expo'`, línea
-- 212) y el bloque 3b es explícito: "un súper con zona numérica no es camión a esa zona".
--
-- QUIÉN LA ROMPIÓ
-- ===============
-- Yo, a mano. Buscando con quién juntar a Luján (Extralimp 4114, 0,745 m³, camión propio a 57 km
-- del depósito) encontré Moreno a 31,5 km por el mismo Acceso Oeste y lo enganché ahí con un
-- `GV_PPP_Prog_Override`. Pero Moreno es **Chango Más** (Dorinka SRL, NP 44619, OC de Krikos):
-- un súper. El override no pasa por `gv_ppp_web_camion_del_dia`, así que se saltea la regla sin
-- que nada avise. Revertido el mismo día: Luján volvió a `E11A` / mar 15, camión propio.
--
-- QUÉ AGREGA ESTA VISTA
-- =====================
-- El chequeo que me habría frenado: lista las filas de cualquier camión que tenga a la vez un
-- súper y un cliente común, mirando web + ISIS. **Vacía = todo bien.**
--
-- Detecta el súper por zona (`super|coto|carrefour|chango|krikos`), que es como viene marcado
-- tanto en la programación de ISIS como en la web.
--
--     select * from public.gv_ppp_super_mezclado;
--
-- MEDIDO al crearla, ya revertido lo mío: **0 filas**.
--
-- ROLLBACK: drop view if exists public.gv_ppp_super_mezclado;

create or replace view public.gv_ppp_super_mezclado
with (security_invoker = true) as
  with filas as (
    select left(btrim(p.fecha_entrega),10) dia,
           substring(upper(btrim(p.tanda)) from 1 for 3) cam,
           upper(btrim(p.tanda)) tanda, btrim(p.np) np, btrim(p.cod) cod,
           p.razon_social, p.barrio, coalesce(p.zona,'') zona
      from public.gv_ppp_programacion_diaria p
     where coalesce(btrim(p.tanda),'') <> ''
       and left(btrim(p.fecha_entrega),10) ~ '^\d{4}-\d{2}-\d{2}$'
    union all
    select w.fecha_entrega::text, substring(upper(btrim(w.tanda)) from 1 for 3),
           upper(btrim(w.tanda)), w.empresa || ' ' || w.np, btrim(coalesce(w.cod_cliente,'')),
           w.razon_social, w.barrio, coalesce(w.zona,'')
      from public."PPP_Web_Programacion" w
     where coalesce(btrim(w.tanda),'') <> ''
  ),
  marcado as (select *, (zona ~* 'super|coto|carrefour|chango|krikos') es_super from filas),
  camiones as (
    select dia, cam, bool_or(es_super) tiene_super, bool_or(not es_super) tiene_cliente
      from marcado group by 1,2
  )
  select m.dia, m.cam, m.tanda, m.np, m.cod, m.razon_social, m.barrio, m.zona,
         case when m.es_super then 'SÚPER' else 'cliente' end as que_es
    from marcado m
    join camiones c on c.dia = m.dia and c.cam = m.cam
   where c.tiene_super and c.tiene_cliente
   order by m.dia, m.cam, m.es_super desc, m.tanda;
