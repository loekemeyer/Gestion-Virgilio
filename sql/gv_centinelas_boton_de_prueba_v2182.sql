-- v21.82 — Luis, 2026-09-23: "dale, armalo para las reglas de la base".
--
-- El equivalente de `tests/tools/mutar.cjs` para lo que vive en Supabase. La app tiene sus
-- alarmas (los tests) y la base tiene las suyas (`GV_Reglas_Centinela` + `gv_reglas_perdidas`).
-- De las de la app ya sabemos que muerden porque se probó rompiendo el código. De las de la
-- base no se había probado nunca.
--
-- ⚠ LO QUE APARECIÓ AL MIRARLAS, y es el motivo de este archivo:
--
-- 1) `gv_reglas_perdidas` había PERDIDO su propia regla. El CLAUDE.md dice desde siempre
--    "⚠ El centinela saca los comentarios antes de buscar: si no, un `-- NO usar X` contaba
--    como uso de X", y la definición viva comparaba `cuerpo !~ patron` a secas. O sea que el
--    vigilante estaba en la misma falla que vigila.
--
-- 2) Y eso ya había dejado pasar una: la regla **(a000) v21.61** del armador ("lo ya
--    programado no entra") tenía como patrón `\(a000\) v21\.61`, que en esa función **sólo
--    existe dentro del comentario**. Si alguien borraba el código del pase y dejaba el
--    comentario, el centinela seguía en verde. Medido: 1 de 124.
--
-- Las dos cosas quedan arregladas acá, y con la forma de enterarse si vuelven a pasar.

-- ── 1. la pieza compartida: "¿el patrón sigue en el CÓDIGO?" (sin comentarios) ────────────
-- La usan la vista y el barrido, así que no puede haber dos criterios distintos.
create or replace function public.gv_regla_presente(p_cuerpo text, p_patron text)
returns boolean language sql immutable as $$
  select coalesce(
    regexp_replace(regexp_replace(coalesce(p_cuerpo,''), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
      ~ p_patron, false);
$$;

-- ── 2. gv_reglas_perdidas vuelve a mirar el código ───────────────────────────────────────
-- (el CREATE completo quedó aplicado; respaldo de la definición anterior en
--  zz_backups."GV_Backup_funcdef_20260923b". ⚠ Conserva security_invoker = true.)

-- ── 3. el patrón de la regla 122 pasa a vigilar CÓDIGO, no su propio comentario ───────────
update public."GV_Reglas_Centinela"
   set patron = 'p_filas := coalesce\(\(select jsonb_agg\(x\)'
 where id = 122 and patron = '\(a000\) v21\.61';

-- ── 4. el barrido: qué centinela está flojo ──────────────────────────────────────────────
-- `gv_reglas_perdidas` contesta "¿el patrón sigue?". NO contesta "¿ese patrón SIRVE?".
--   select * from public.gv_centinelas_flojos order by problema, objeto;
-- Al 23/09: 0 que vigilan un comentario, 0 perdidas, 26 con patrón genérico.
--
-- ⚠ "Patrón genérico" (matchea en más de 3 objetos vigilados) es SEÑAL DÉBIL, no un error:
-- lo que el centinela vigila es que alguien pise el objeto con una copia vieja, y para eso
-- alcanza con que el patrón esté una vez. Se lista para poder leer el caso, no para acusar.

-- ── 5. LA PRUEBA DE VERDAD: romper la regla y ver si avisa, revirtiendo siempre ───────────
-- Es el botón de prueba. Se corre a mano cuando se agrega una regla cara. El `raise` del
-- final aborta la transacción entera, así que la función queda como estaba — y el resultado
-- viaja EN EL MENSAJE del error, porque un `raise notice` no se ve desde el MCP.
--
--   do $prueba$
--   declare v_def text; v_mut text; v_antes int; v_despues int; v_listada boolean;
--   begin
--     select count(*) into v_antes from public.gv_reglas_perdidas;
--     select pg_get_functiondef(p.oid) into v_def from pg_proc p
--       join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname='public' and p.proname='<LA FUNCION>';
--     v_mut := regexp_replace(v_def, '<EL PATRON DE SU REGLA>', 'true', 'g');
--     if v_mut = v_def then raise exception 'la mutacion no cambio nada: revisar el patron'; end if;
--     execute v_mut;                                    -- se pisa SIN la regla
--     select count(*) into v_despues from public.gv_reglas_perdidas;
--     select exists(select 1 from public.gv_reglas_perdidas
--                    where objeto='<LA FUNCION>') into v_listada;
--     raise exception 'RESULTADO -> antes: % · con la regla borrada: % · la nombra: %',
--       v_antes, v_despues, v_listada;
--   end $prueba$;
--
-- MEDIDO el 23/09 con refresh_stocks_carga_rapida y la regla del código fantasma (v21.76):
--   RESULTADO -> antes: 0 perdidas · con la regla borrada: 1 · la nombra: t
-- y después: la regla sigue puesta y gv_reglas_perdidas volvió a 0. La cadena entera anda.

-- ⚠ LO QUE SE PROBÓ Y SE DESCARTÓ, para no rehacerlo: una vista `gv_centinelas_no_muerden`
-- que borraba la PRIMERA aparición del patrón y miraba si el centinela avisaba. Marcaba 41
-- de 124 y era RUIDO: el centinela vigila que alguien pise el objeto ENTERO con una copia
-- vieja, y ahí desaparecen todas las apariciones. Se borró el mismo día.

-- CHEQUEO
--   select * from public.gv_reglas_perdidas;      -- vacía = ninguna regla se perdió
--   select * from public.gv_centinelas_flojos;    -- ningún 'VIGILA UN COMENTARIO'
