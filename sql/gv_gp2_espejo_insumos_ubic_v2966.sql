-- v29.66 (Luis, 13/10) — el espejo de insumos GV → GP2 CREA SOLO el depósito «<sector> en Virgilio»
--
-- Por qué: `gv_gp2_espejo_insumos` deja en GP2 el saldo de Virgilio en la ubicación
-- `virgilio_sector` del sector del componente. Si ese depósito no existe, la fila salía
-- «sin depósito en Virgilio» y ese stock NO se reflejaba NUNCA — y nadie se enteraba.
-- Pasó el 13/10 al vincular C9 y D14 (Resortes, Sector Bombilla): 24.552 unidades mudas.
--
-- Qué hace: adentro del loop, si el sector no tiene su depósito, lo crea (sólo ejecutando,
-- no al simular) y sigue con el ajuste normal. Idempotente: si ya está, no hace nada.
-- Marcadores internos `v29.61-ubic` / `v29.61-ubic3` (son la llave, NO cambiarlos); el
-- marcador viejo `v29.32-espejo-gp2` queda intacto.
--
-- ⚠ El insert va con `not exists`, NO con `on conflict (tipo, ref_id)`: el único índice es
-- PARCIAL (`ubicacion_tipo_ref_uq ... where ref_id is not null`) y un ON CONFLICT sin su
-- predicado da 42P10. Y hace falta el guard porque dos componentes del mismo sector entran
-- en el mismo loop: el segundo chocaba con la ubicación que creó el primero (23505).
--
-- Rollback (deshace los replace sobre la def viva, sin tocar nada más):
--   do $r$ declare d text := pg_get_functiondef('public.gv_gp2_espejo_insumos(text,boolean)'::regprocedure);
--   begin
--     d := regexp_replace(d, '\n  v_ubic bigint;   -- v29\.61-ubic', '');
--     d := replace(d, 'max(cv.sector_id) sect, string_agg', 'string_agg');
--     d := regexp_replace(d, 'v_ubic := r\.ubic;.*?componente_id := r\.componente_id', 'componente_id := r.componente_id', 'n');
--     d := replace(d, 'v_ubic', 'r.ubic');
--     execute d; end $r$;

do $p$
declare
  d text := pg_get_functiondef('public.gv_gp2_espejo_insumos(text,boolean)'::regprocedure);
  n int;
begin
  if d ~ 'v29.61-ubic' then raise notice 'ya aplicado'; return; end if;

  d := replace(d, '  v_kg_bolsa numeric;',
                  '  v_kg_bolsa numeric;' || chr(10) || '  v_ubic bigint;   -- v29.61-ubic');
  if d !~ 'v29.61-ubic' then raise exception 'no matchea el declare'; end if;

  d := replace(d, 'string_agg(distinct cv.cod_virgilio, '', '') cods,',
                  'max(cv.sector_id) sect, string_agg(distinct cv.cod_virgilio, '', '') cods,');
  if d !~ 'max\(cv\.sector_id\) sect' then raise exception 'no matchea el select'; end if;

  d := replace(d, 'componente_id := r.componente_id; codigo_gp2 := r.codigo; ubicacion_id := r.ubic; cods := r.cods;',
    'v_ubic := r.ubic;' || chr(10) ||
    '    -- v29.61-ubic: el sector que todavia no tiene deposito "en Virgilio" se crea solo,' || chr(10) ||
    '    -- o su stock de Virgilio no se reflejaria nunca (caso Sector Bombilla, C9 y D14).' || chr(10) ||
    '    if v_ubic is null and r.sect is not null and not p_simular then' || chr(10) ||
    '      insert into "GP2".ubicacion (tipo, ref_id, nombre)   -- v29.61-ubic3' || chr(10) ||
    '      select ''virgilio_sector'', r.sect, s.nombre || '' en Virgilio''' || chr(10) ||
    '        from "GP2".sector s' || chr(10) ||
    '       where s.id = r.sect' || chr(10) ||
    '         and not exists (select 1 from "GP2".ubicacion u2' || chr(10) ||
    '                          where u2.tipo = ''virgilio_sector'' and u2.ref_id = r.sect);' || chr(10) ||
    '      select u.id into v_ubic from "GP2".ubicacion u' || chr(10) ||
    '       where u.tipo = ''virgilio_sector'' and u.ref_id = r.sect limit 1;' || chr(10) ||
    '    end if;' || chr(10) ||
    '    componente_id := r.componente_id; codigo_gp2 := r.codigo; ubicacion_id := v_ubic; cods := r.cods;');
  if d !~ 'v29\.61-ubic: el sector' then raise exception 'no matchea el arranque del loop'; end if;

  d := replace(d, 'and i.ubicacion_id = r.ubic;', 'and i.ubicacion_id = v_ubic;');
  d := replace(d, 'if r.ubic is null then', 'if v_ubic is null then');
  d := replace(d, 'case when delta < 0 then r.ubic end,', 'case when delta < 0 then v_ubic end,');
  d := replace(d, 'case when delta > 0 then r.ubic end,', 'case when delta > 0 then v_ubic end,');
  d := replace(d, 'values (r.componente_id, r.ubic, r.cods', 'values (r.componente_id, v_ubic, r.cods');
  select count(*) into n from regexp_matches(d, 'r\.ubic', 'g');
  if n <> 1 then raise exception 'r.ubic aparece % veces, esperaba 1', n; end if;

  execute d;
  raise notice 'aplicado';
end $p$;

-- Verificación (las dos tienen que dar lo mismo que Virgilio):
-- select count(*) filter (where resultado <> 'ok') as pendientes from public.gv_gp2_espejo_insumos(null, true);  -- 0
-- select id, ref_id, nombre from "GP2".ubicacion where tipo = 'virgilio_sector' order by id;
