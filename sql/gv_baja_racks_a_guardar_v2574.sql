-- v25.74 (Luis, 01/10): «Bajar de Racks» es su propio módulo y baja a A GUARDAR, no a góndola.
-- registrar_baja_racks acepta "destino":"a_guardar" por ítem: el + va a a_guardar, sin excedente.
-- Sin el campo (celulares viejos, supervisor desde Stock) sigue yendo a terminado como antes.
-- Se aplica sobre la definición VIVA, idempotente, y falla si el texto no matchea.
do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public.registrar_baja_racks(jsonb)'::regprocedure);
  if d like '%v25.74-aguardar%' then raise notice 'ya aplicado'; return; end if;
  n := replace(d, $a$v_dual boolean; -- v24.68-conteo$a$, $a$v_dual boolean; v_dest text; -- v24.68-conteo · v25.74-aguardar$a$);
  n := replace(n, $a$ v_cr := nullif(it->>'conteo_rack',''$a$,
    $a$ v_dest := case when lower(btrim(coalesce(it->>'destino',''))) = 'a_guardar' then 'a_guardar' else 'terminado' end;$a$ || chr(10) ||
    $a$ if v_dest = 'a_guardar' then v_exc := 0; end if;$a$ || chr(10) ||
    $a$ v_cr := nullif(it->>'conteo_rack',''$a$);
  n := replace(n, $a$values (v_cod, v_desc, 'terminado', v_caj - v_exc, 'baja_racks'$a$,
                  $a$values (v_cod, v_desc, v_dest, v_caj - v_exc, 'baja_racks'$a$);
  if n = d or n not like '%v_dest := case%' or n not like '%v_desc, v_dest, v_caj%' then
    raise exception 'registrar_baja_racks: el texto vivo no matcheo, no se aplico nada';
  end if;
  execute n;
end $do$;
-- Probado en transaccion abortada (01/10): 546 en O05, 2 cj con excedente 1 -> a_guardar +2 · racks -2.
-- Rollback: volver a aplicar la definición anterior (v24.68), quitando v_dest.
