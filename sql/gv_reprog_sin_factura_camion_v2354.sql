-- v23.54 (Luis 28/09): "maximizar entregas minimizando camiones".
-- El cron de las 18 hs (gv_ppp_reprogramar_sin_factura) SOLO mueve una tanda a un dia que YA
-- tiene camion a su grupo de zonas (Z1 · Z2 · Z3 · Z4 · Z5 · Z6+Z7, sin super ni retira).
-- Nunca abre dia ni camion nuevo: si no hay en 20 dias -> accion 'aviso_sin_camion'.
-- Reemplaza el uso de gv_ppp_web_dia_grupo / dias_ancla / proximo_dia_con_cupo en ese cron
-- (esos abrian un dia libre: la simulacion daba 34 camiones contra 32).
create or replace function public.gv_reprog_dia_con_camion(p_zona text, p_min date, p_tanda text, p_dias int default 20)
returns date language sql stable set search_path to 'public' as $f$
  with g as (
    select case n when 7 then 6 else n end as grp
      from (select nullif(substring(coalesce(p_zona,'') from 'Zona\s*([0-9]+)'),'')::int n) z)
  select min(t.fecha)
    from (select d.fecha, d.tanda,
                 min(case n when 7 then 6 else n end) as grp,
                 bool_or(public.gv_es_super(d.empresa, d.cod) or coalesce(d.zona_corta,'') ~* 'super|retira') as no_cuenta
            from (select dd.*, nullif(substring(coalesce(dd.zona_corta,'') from 'Zona\s*([0-9]+)'),'')::int n
                    from public.gv_ppp_detalle_dia dd
                   where dd.fecha >= p_min and dd.fecha < p_min + p_dias) d
           where upper(btrim(d.tanda)) <> upper(btrim(coalesce(p_tanda,'')))
           group by d.fecha, d.tanda) t, g
   where g.grp is not null and t.grp = g.grp and not t.no_cuenta
     and public.gv_es_dia_con_reparto(t.fecha);
$f$;

-- Parche del cron (sobre la definicion viva; idempotente por el marcador v23.54-camion):
-- el bloque desde "if not r.a_mano and r.zona_larga is not null then" hasta el
-- "if p_aplicar then / begin / perform gv_ppp_tanda_mover" se reemplaza por:
--   v_dest := gv_reprog_dia_con_camion(r.zona, v_min, r.tanda);
--   if v_dest is null then v_acc := 'aviso_sin_camion' ... elsif p_aplicar then <mover> else 'se_moveria'.
-- Centinela: patron 'gv_reprog_dia_con_camion' (v23.54). El de v23.44 (gv_ppp_web_dia_grupo)
-- queda obsoleto: borrarlo con el si de Luis.
