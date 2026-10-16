-- v31.84 (Luis, 16/10/2026): en RP3.0 (rp.loeke-erp.com/virgilio) la lista «¿Quién sos?» sale ordenada por
-- cuántas veces entró cada operario en la historia: días con eventos en Gestión Virgilio + ingresos OK en RP3.0.
-- El front de RP3.0 respeta el orden que manda el servidor. Aplicado el 16/10/2026.
CREATE OR REPLACE FUNCTION reg_prod_3_0.reg_prod_3_0_virgilio_operarios(p_clave text, p_dispositivo text, p_huella text, p_navegador text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  v := public.gv_clave_chequear('virgilio', 'virgilio-3.0', p_clave, p_dispositivo, p_huella, p_navegador);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  -- v31.84 (Luis, 16/10): la lista sale ordenada por cuántas veces entró cada operario en la historia:
  -- días con eventos en Gestión Virgilio (una sesión por día) + ingresos OK en RP3.0. Empate → nombre.
  return jsonb_build_object('ok', true, 'operarios', coalesce((
    with o as (
      select o.legajo, o.nombre, regexp_replace(o.legajo, '^c', '') leg
        from reg_prod_3_0.operario o where o.legajo <> '0'),
    gv as (
      select r.legajo, count(distinct (r.created_at at time zone 'America/Argentina/Buenos_Aires')::date) n
        from public."Registros_Produccion_Virgilio" r where r.legajo in (select leg from o) group by 1),
    rp as (
      select i.legajo, count(*) n from reg_prod_3_0.reg_prod_3_0_ingresos i where i.ok group by 1)
    select jsonb_agg(jsonb_build_object('legajo', o.leg, 'legajo_verdadero', o.legajo, 'nombre', o.nombre,
                                        'ingresos', coalesce(gv.n, 0) + coalesce(rp.n, 0))
                     order by coalesce(gv.n, 0) + coalesce(rp.n, 0) desc, o.nombre)
      from o left join gv on gv.legajo = o.leg left join rp on rp.legajo = o.legajo), '[]'::jsonb));
end $function$;
