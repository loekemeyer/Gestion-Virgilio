-- =====================================================================================
-- v21.84 — CENTINELAS: 4 patrones que vigilan el vecindario, y la regla v14.12 sin nadie
--
-- Luis, 23/09: "contá cuántas reglas no tienen centinela y mira lo otro".
--
-- ⚠⚠ ESTE ARCHIVO NO ESTÁ APLICADO. Toca datos reales (GV_Reglas_Centinela) y por
--    protocolo lo autoriza el dueño. Está escrito, medido y listo para pegar.
--
-- QUÉ SE MIDIÓ
-- ------------
-- «Patrón genérico» NO es "cuántos objetos nombran esa palabra": el centinela sólo mira
-- SU objeto. Lo que importa es cuántas veces aparece el patrón en el cuerpo de su propio
-- objeto. Si aparece UNA vez, el patrón ES la regla y borrarla lo borra.
--
--   19 de los 26 «flojos»  -> 1 aparición  -> están bien, no se tocan
--    7                     -> 2+           -> 3 son la misma regla repetida (se dejan)
--                                             4 vigilan otra cosa (se ajustan acá)
--
-- Al 23/09: gv_reglas_perdidas = 0 filas. Los 4 patrones nuevos matchean HOY (verificado
-- con gv_regla_presente sobre pg_get_functiondef / pg_get_viewdef), así que este cambio
-- NO pone ninguna regla en rojo: aprieta el foco, no mueve el estado.
-- =====================================================================================

-- ── 1) gv_np_destino (id 53) ──────────────────────────────────────────────────────────
-- La regla es: un Retira que no resuelve provincia sale como 'retira', NO como 'ambiguo'.
-- Eso es UNA línea (`WHEN es_retira THEN 'retira'`). El patrón viejo `es_retira` matchea
-- 6 veces: la definición de la columna y su arrastre por 3 CTE. Borrando la línea de la
-- regla el centinela seguía verde.
update public."GV_Reglas_Centinela"
   set patron  = 'es_retira THEN ''retira''',
       version = 'v21.84'
 where id = 53 and objeto = 'gv_np_destino' and patron = 'es_retira';

-- ── 2) gv_retira_contradictorio (id 61) ───────────────────────────────────────────────
-- La regla es que el centinela compara en las DOS direcciones (v20.66: un pedido que se
-- reparte puede decir Retira). Eso vive en el WHERE, no en la columna.
update public."GV_Reglas_Centinela"
   set patron  = 'NOT es_retira AND',
       version = 'v21.84'
 where id = 61 and objeto = 'gv_retira_contradictorio' and patron = 'es_retira';

-- ── 3) gv_tanda_armada_sin_armado (id 66) ─────────────────────────────────────────────
-- ⚠ El peor de los cuatro: de las 2 apariciones de `Entregas_Virgilio`, UNA es el texto
--   del `motivo` ('...no tiene una sola linea en Entregas_Virgilio'). O sea que borrando
--   el FROM de verdad, el centinela se quedaba verde contra un STRING. Es el mismo pozo
--   del comentario (v21.82), un paso más adelante: ahí vigilaba un comentario, acá un
--   literal de texto.
update public."GV_Reglas_Centinela"
   set patron  = 'FROM "Entregas_Virgilio"',
       version = 'v21.84'
 where id = 66 and objeto = 'gv_tanda_armada_sin_armado' and patron = 'Entregas_Virgilio';

-- ── 4) gv_empresa_de_entrega (id 89) ──────────────────────────────────────────────────
-- Dos ramas devuelven 'LK': la de la **L** (la regla) y la de la **NP** (que es justo lo
-- que la regla dice que NUNCA decide). Con el patrón viejo se podía borrar la rama de la
-- L y el centinela no se enteraba.
update public."GV_Reglas_Centinela"
   set patron  = '\[0-9E\]L\$'' then ''LK''',
       version = 'v21.84'
 where id = 89 and objeto = 'gv_empresa_de_entrega' and patron = '''LK''';

-- ── 5) LA REGLA v14.12, QUE NO TENÍA CENTINELA ────────────────────────────────────────
-- "el agregado va en tanda nueva SÓLO si mezclaría ISIS con web" (dueño, 07/09). El corte
-- es el ORIGEN, y se sostiene en que `gv_ppp_web_tanda_abierta_cliente` mira SOLO
-- PPP_Web_Programacion: las tandas de ISIS no son candidatas. Caso Osa 2533 (09/09):
-- E09A es de ISIS, así que LK 0024 fue a E09B.
-- La v14.05 ya lo había leído al revés una vez, y esa función la tocan varias sesiones.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_web_tanda_abierta_cliente', 'funcion',
        'from public\."PPP_Web_Programacion" w',
        'Las candidatas salen SOLO de PPP_Web_Programacion: una tanda de ISIS nunca es '
        'candidata a recibir un agregado web (regla del dueno del 07/09, v14.12). La v14.05 '
        'lo leyo al reves y metia pedidos de la pagina adentro de tandas de ISIS.',
        'Thomas (07/09)', 'v21.84'),
       ('gv_ppp_web_tanda_abierta_cliente', 'funcion',
        'mismo_camion',
        'Y ademas del MISMO CAMION (Luis, v18.87): una tanda es candidata solo si TODAS sus '
        'NP son del camion pedido; si ya esta mezclada, no se le suma nada mas.',
        'Luis (16/09)', 'v21.84');

-- ── VERIFICACIÓN (obligatoria, después de escribir) ───────────────────────────────────
-- select * from public.gv_reglas_perdidas;      -- tiene que seguir VACÍA
-- select * from public.gv_centinelas_flojos;    -- los 4 salen de la lista; quedan 22
-- select id, objeto, patron, version from public."GV_Reglas_Centinela"
--  where id in (53,61,66,89) or objeto = 'gv_ppp_web_tanda_abierta_cliente';

-- ── ROLLBACK ──────────────────────────────────────────────────────────────────────────
-- update public."GV_Reglas_Centinela" set patron='es_retira',          version='v20.62' where id=53;
-- update public."GV_Reglas_Centinela" set patron='es_retira',          version='v20.65' where id=61;
-- update public."GV_Reglas_Centinela" set patron='Entregas_Virgilio',  version='v20.68' where id=66;
-- update public."GV_Reglas_Centinela" set patron='''LK''',             version='v21.13' where id=89;
-- delete from public."GV_Reglas_Centinela" where objeto='gv_ppp_web_tanda_abierta_cliente';
