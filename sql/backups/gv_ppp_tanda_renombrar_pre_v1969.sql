-- Backup de las definiciones VIVAS al 2026-09-18, antes de la v19.69 (problema 407).
-- Traídas con pg_get_functiondef justo antes de reemplazarlas. Esto es el rollback.

CREATE OR REPLACE FUNCTION public.gv_ppp_tanda_renombrar(p_vieja text, p_nueva text, p_por text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_a text := upper(btrim(coalesce(p_vieja, ''))); v_b text := upper(btrim(coalesce(p_nueva, ''))); v_n int := 0;
begin
  if v_a = '' or v_b = '' or v_a = v_b then return 0; end if;
  update public."Registros_Produccion_Virgilio" r set texto = v_b where upper(btrim(r.texto)) = v_a;
  get diagnostics v_n = row_count;
  update public."Registros_Produccion_Virgilio" r
     set texto = split_part(r.texto, '|', 1) || '|' || split_part(r.texto, '|', 2) || '|' || v_b
   where upper(btrim(split_part(r.texto, '|', 3))) = v_a;
  update public."Entregas_Virgilio" e set tanda = v_b where upper(btrim(e.tanda)) = v_a;
  update public."Facturacion_NP" f set tanda = v_b where upper(btrim(f.tanda)) = v_a;
  update public."Movimientos_Stock" m set ref = v_b where upper(btrim(coalesce(m.ref, ''))) = v_a;
  update public."GV_PPP_Armados_Espera" e set tanda = v_b where upper(btrim(coalesce(e.tanda, ''))) = v_a;
  update public."PPP_Web_Tandas" t set codigo = v_b
   where upper(btrim(t.codigo)) = v_a
     and not exists (select 1 from public."PPP_Web_Tandas" x where upper(btrim(x.codigo)) = v_b);
  delete from public."PPP_Web_Tandas" t where upper(btrim(t.codigo)) = v_a;
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION public.gv_ppp_web_codigo_tomado(p_codigo text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public."GV_PPP_Programacion_Diaria" where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Programacion"    where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Tandas"          where codigo = p_codigo and estado <> 'descartada')
      or exists (select 1 from public."GV_PPP_Prog_Override"    where tanda = p_codigo);
$function$;
