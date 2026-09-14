-- v17.93 (Luis, 2026-09-14) — LAS ALERTAS DEJAN DE AVISAR POR UNA NP CANCELADA O DESARMADA.
--
-- Salió de una pregunta de Luis sobre el desarme: *"lo de ocultar la NP me hizo ruido. ¿Por qué
-- «ocultar» y no «borrar»?"*.
--
-- ═══ POR QUÉ SE OCULTA Y NO SE BORRA ═══
--
-- Porque la fila NO ES NUESTRA. `GV_PPP_Programacion_Diaria` es el **espejo de ISIS**: se alimenta
-- desde afuera (al 14/09 tiene 133 filas, 117 de los últimos 7 días, con entregas hasta el 28/10) y
-- **ninguna función de la base la escribe**. Un `delete` ahí sería un borrado que se deshace solo:
-- la próxima importación de la PPP vuelve a traer la fila. El `oculto` de `GV_PPP_Prog_Override`,
-- en cambio, es nuestro y sobrevive a la reimportación.
--
-- Es además lo que manda el `CLAUDE.md`: sobre una tabla compartida se AGREGA, nunca se borra →
-- tabla `GV_*` de override + vista que la superpone.
--
-- (La NP **web** sí se "borra" de verdad: el desarme le pone `tanda = null` y `fecha_entrega = null`
-- en `PPP_Web_Programacion`, que es tabla nuestra, y la manda a `GV_Web_Cancelados`.)
--
-- ═══ PERO EL RUIDO TENÍA RAZÓN DE SER ═══
--
-- "Oculto" sólo sirve si TODOS miran el override, y no todos lo miraban. Las tres vistas `gv_*` sí,
-- pero **11 funciones leen la tabla MADRE directo** y no miran ni `oculto` ni `NP_Canceladas`.
-- La peor: `notificar_falta_facturacion_telegram` (y su gemela de las 16:30). Su filtro es
-- *tanda con TAP + fecha de entrega hoy/mañana + sin facturar* — que es **exactamente la forma de
-- una NP desarmada**, así que la nombraba en la alerta como si faltara facturarla.
--
-- No lo trajo el desarme (v17.88): viene de `gv_ppp_np_cancelar` (v15.55), que oculta igual. Lo que
-- hizo el botón nuevo es volverlo frecuente.
--
-- ARREGLO: estas cinco pasan a leer la vista `gv_ppp_programacion_diaria`, que ya saltea lo oculto.
-- Es un cambio de fuente, no de lógica: la vista expone las mismas columnas (np, tanda,
-- fecha_entrega, cod, razon_social, m3).

do $do$
declare r record; v_def text; v_new text; v_n int := 0;
begin
  for r in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.proname in ('notificar_falta_facturacion_telegram','notificar_falta_facturacion_1630_telegram',
                         'notificar_pedido_adelantado_telegram','notificar_tandas_adelantar_telegram',
                         'generar_inconsistencias')
  loop
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(v_def, '"GV_PPP_Programacion_Diaria"', 'gv_ppp_programacion_diaria');
    if v_new = v_def then raise notice '% : sin cambios', r.proname; continue; end if;
    begin
      execute v_new;
    exception when others then
      raise exception 'no compila %: %', r.proname, sqlerrm;   -- con el nombre: si una falla, no queda nada a medias
    end;
    v_n := v_n + 1;
  end loop;
  raise notice 'reescritas: %', v_n;
end $do$;

-- ═══ MEDICIÓN ═══
--
-- Contra los datos de hoy el cambio no saca NI UNA fila (no hay ninguna tanda con TAP reciente y
-- NP sin facturar), así que hizo falta un CONTROL POSITIVO — si no, un "0" también sería el
-- resultado de un cambio que no hace nada:
--
--   np      en_la_madre   en_la_vista
--   44620        1             0
--   44621        1             0
--   98696        1             0
--
-- La NP oculta está en la madre y no está en la vista: la fuente nueva filtra.
--
-- ⚠ FALTA (queda anotado como problema aparte, NO se toca acá): otras seis funciones siguen
-- leyendo la madre directo, y una importa de verdad — `gv_pedidos_web_excluidos` usa
-- `GV_PPP_Programacion_Diaria` para decidir "este pedido ya está en ISIS", sin saltear lo oculto.
-- O sea que ocultar una NP de ISIS que duplicaba un pedido web **no libera** a ese pedido web, que
-- era justamente el motivo de ocultarla. Tocarla cambia qué pedidos entran a A Programar, así que
-- va medido y aparte. Las de cobranzas / valorización quedan como están a propósito: una NP
-- cancelada o desarmada probablemente deba seguir valorizada en el histórico, y eso lo decide el
-- dueño, no esta migración.
--
-- ROLLBACK: mismo bloque con el replace al revés
-- (`replace(v_def, 'gv_ppp_programacion_diaria', '"GV_PPP_Programacion_Diaria"')`).
