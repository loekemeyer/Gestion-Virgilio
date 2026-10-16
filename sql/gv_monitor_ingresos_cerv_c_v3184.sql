-- v31.84 (Luis, 16/10/2026): el monitor de GV (TV) mostraba operarios de Cervantes. gv_monitor_ingresos ya
-- excluía a quien después marca en Cervantes (v27.69), pero Cervantes graba el legajo con «c» (c19 = 19) y la
-- comparación no lo reconocía. Ahora se compara el legajo pelado. Aplicado el 16/10/2026.
CREATE OR REPLACE FUNCTION public.gv_monitor_ingresos(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(legajo text, ts_cliente timestamp with time zone, email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select btrim(l.legajo::text), min(l.created_at), null::text
    from public."GV_Dispositivo_Login" l
   where l.tipo = 'operario' and l.metodo in ('clave_tv','nombre') /* v27.68-clavetv */ and l.created_at >= p_desde
     /* v27.69-cerv · v31.84 (Luis, 16/10): Cervantes graba el legajo con «c» (c19 = 19): se compara pelado */
     and not exists (select 1 from reg_prod_3_0.crudo_todas cv where regexp_replace(cv.legajo::text, '^c', '') = btrim(l.legajo::text) and cv.created_at >= l.created_at and cv.created_at < p_hasta)
     and l.created_at < p_hasta
     and coalesce(btrim(l.legajo::text), '') not in ('', '0')
     and p_hasta - p_desde <= interval '8 days'
   group by btrim(l.legajo::text)
   order by 2
$function$;
