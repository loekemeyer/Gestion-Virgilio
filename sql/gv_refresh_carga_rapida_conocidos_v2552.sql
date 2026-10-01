-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 01/10/2026: "d7 metele")
-- v25.50 — refresh_stocks_carga_rapida(): gv_stock_cod_conocido(vsp.cod) se llamaba POR FILA
-- (se aplicó como v25.52; el marcador interno dice v25.50-conocidos: es la llave de idempotencia, no cambiarlo)
-- Medido 01/10: 5,9 s -> 273 ms por corrida; stocks_carga_rapida idéntica (md5 a5531d3c…, 374 filas).
-- (SET search_path => no se inlinea): ~6,4 s de 5,9 s por corrida. Se arma UNA vez el array de
-- códigos conocidos de los 7 maestros (mismo criterio de normalización) y se compara con = any().
-- Backup de la definición: zz_backups."GV_Backup_RefreshCargaRapida_def_20261001".
-- Rollback: recrear la función desde ese backup.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.refresh_stocks_carga_rapida()'::regprocedure);
  if d ~ 'v25\.50-conocidos' then raise notice 'ya aplicado'; return; end if;
  if (length(d) - length(replace(d, 'public.gv_stock_cod_conocido(vsp.cod)', ''))) / length('public.gv_stock_cod_conocido(vsp.cod)') <> 2 then
    raise exception 'refresh_stocks_carga_rapida: no encuentro las 2 llamadas a gv_stock_cod_conocido';
  end if;
  if position(E'AS $function$\nBEGIN\n' in d) = 0 then
    raise exception 'refresh_stocks_carga_rapida: no encuentro el BEGIN';
  end if;
  n := replace(d, E'AS $function$\nBEGIN\n', E'AS $function$\nDECLARE v_conocidos text[];  -- v25.50-conocidos\nBEGIN\n'
    || $x$  v_conocidos := array(select distinct c from (
    select upper(regexp_replace(cod,'^0+(?=.)','')) c from public.vista_nombres_articulos
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public.vista_uxb_articulo
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."OC_Maximos"
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."GV_Lugar_Item"
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."Capacidad_Sector"
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public.proyeccion_madre
    union all select upper(regexp_replace(cod::text,'^0+(?=.)','')) from public."Insumos") z where c is not null);
$x$);
  n := replace(n, 'public.gv_stock_cod_conocido(vsp.cod)',
    $x$(upper(regexp_replace(regexp_replace(coalesce(vsp.cod,''),'\s+(LK|CH|LOKE)$','','i'),'^0+(?=.)','')) = any(v_conocidos))$x$);
  execute n;
end $patch$;

update public."GV_Reglas_Centinela" set patron = 'v_conocidos', version = 'v25.50'
 where objeto = 'refresh_stocks_carga_rapida' and patron = 'gv_stock_cod_conocido';
