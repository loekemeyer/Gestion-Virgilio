-- BACKUP de la definición ANTERIOR de gv_cuarentena_pago (v15.46), tal como estaba en la base
-- el 2026-09-15 antes de aplicar sql/gv_cuarentena_pago_v1801.sql. Para volver atrás: ejecutar
-- este archivo tal cual.
CREATE OR REPLACE FUNCTION public.gv_cuarentena_pago(p_empresa text, p_cod text)
 RETURNS TABLE(cod text, empresa text, deuda_al_pagar numeric, pedidos_liberados integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_emp   text := lower(nullif(btrim(p_empresa), ''));
  v_cod   text := nullif(btrim(p_cod), '');
  v_at    timestamptz;
  v_deuda numeric;
  v_n     int := 0;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede marcar un cliente como pagado.' using errcode='42501';
  end if;
  if v_emp is null or v_cod is null then
    raise exception 'Falta empresa o codigo de cliente.' using errcode='22023';
  end if;

  -- fecha del reporte de deuda vigente: el pago solo vale contra ESTE reporte.
  select max(f.cargado_at) into v_at
    from public."GV_Cuarentena_Fuente" f
   where f.empresa = v_emp and f.tipo = 'deuda';

  select round(f.deuda, 2) into v_deuda
    from public."GV_Cuarentena_Fuente" f
   where f.empresa = v_emp and f.tipo = 'deuda' and f.cod = v_cod
   limit 1;

  insert into public."GV_Cuarentena_Pagados" (empresa, cod, pagado_at, pagado_por, fuente_at, deuda_al_pagar)
  values (v_emp, v_cod, now(), lower(coalesce(auth.jwt()->>'email','')), v_at, v_deuda)
  on conflict (empresa, cod) do update
    set pagado_at = now(), pagado_por = excluded.pagado_por,
        fuente_at = excluded.fuente_at, deuda_al_pagar = excluded.deuda_al_pagar;

  -- cuantos pedidos de ese cliente estaban esperando: informativo para el aviso del front
  select count(*) into v_n
    from public."PPP_Web_Programacion" pw
   where pw.empresa = v_emp and pw.cod_cliente = v_cod and pw.tanda is null;

  return query select v_cod, v_emp, v_deuda, v_n;
end;
$function$;
