-- v31.78 (Luis, 16/10/2026): desde el sáb 17/10 00:01 el código de la TV deja de abrir Gestión.
-- El operario entra por RP3.0 (https://rp.loeke-erp.com/). RP3.0 valida con su propia función
-- (reg_prod_3_0.reg_prod_3_0_virgilio_operarios), así que este corte no lo toca.
-- Aplicado el 16/10/2026. Front: index.html (_gvClaveTvApagada / «Login Operario»). Test: tests/login-operario-rp3.cjs.
CREATE OR REPLACE FUNCTION public.gv_tv_clave_validar(p_clave text, p_dispositivo text, p_huella text, p_navegador text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  -- v31.78 (Luis, 16/10): desde el sáb 17/10 00:01 el operario entra por RP3.0 (rp.loeke-erp.com);
  -- el código de la TV deja de abrir Gestión, también en celulares con el index viejo cacheado.
  if now() >= timestamptz '2026-10-17 00:01:00-03' then
    return jsonb_build_object('ok', false, 'error', 'migrado', 'url', 'https://rp.loeke-erp.com/');
  end if;
  v := public.gv_clave_chequear('virgilio', 'gestion', p_clave, p_dispositivo, p_huella, p_navegador);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  return jsonb_build_object('ok', true, 'operarios', public.gv_tv_clave_operarios());
end $function$;
