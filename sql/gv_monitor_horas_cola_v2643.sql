-- v26.43-cola (Luis, 02/10/2026): el TIEMPO SIN REGISTRO que sigue a un TP/TAP, hasta que el operario
-- empieza su proxima tarea registrada (o el fin de jornada), SE SUMA al picking/armado de esa tanda.
--
-- Luis, textual: "si hay tiempos sin registros, luego de que esten haciendo picking o armado, hasta que
-- inicien la nueva tarea, esos tiempos quiero que se registren dentro de picking o armado ... si vos
-- pusiste termine antes de acomodarlas en la mesa, te estas beneficiando un tiempo que realmente no
-- terminaste".
--
-- Que cambia (gv_monitor_horas_operario_dia, y la copia verbatim gv_horas_operario_detalle_v2 del xlsx):
--   · CTE nuevo `cola`: por TP/TAP (tanda <> '' y <> 'ANULADO'), segundos desde el cierre hasta el MINIMO de
--       - el inicio de la proxima tarea registrada del legajo ese dia: coalesce(ts_inicio, ts_cliente) de todo
--         evento que no sea automatico (PUB, AUB, PKC, ENT, RSP, ROC, RAG, FGU, FSS, IMPT, TAL, GST, MGR, PKM,
--         SSG, PSP, NPD, PKAX ni los *X). Un tramo que YA estaba abierto al cerrar (ts_inicio <= TP) deja la
--         cola en 0. Un segundo TP/TAP de la MISMA tanda no la corta (se toma el max por tanda).
--       - la primera bajada de racks sin tramo (Movimientos_Stock baja_racks) del legajo: ese tramo ya cuenta
--         como racks en rk_ag, no se cuenta dos veces.
--       - el tope de jornada: least(now(), greatest(ultimo evento del legajo, p_dia + hora_salida)). El FJ es un
--         evento registrado, asi que corta la cola solo.
--   · pick / arm: max(dur_s) + coalesce(max(k.s), 0). hs_prod y hs_total no cambian de formula.
--   El monitor grande (index.html, fetchMonitorDayStats, `colaMsDe`) hace lo mismo; tests/mon-vs-vista.cjs
--   compara los dos sobre el 15/09 (fixture tests/tools/vista-15.json re-congelado con esta version).
--
-- Medido antes de aplicar (copia de prueba en transaccion abortada):
--   15/09: 277 hs_pick 6,37 -> 7,77 · 237 hs_arm 5,60 -> 6,63 · 8 hs_arm 6,75 -> 8,76 · 104 y 94 iguales.
--   01/10: 104 hs_arm 5,06 -> 5,29 · 8 hs_arm 2,63 -> 4,24 · 94 hs_pick 3,35 -> 3,71.
--   60 dias, por tanda: TP mediana 1,7 min, p90 9,7, 4 colas > 60 min (la mayor 518 min: TP sin ningun evento
--   despues hasta la hora de salida). TAP mediana 2,1 min, p90 16,4.
--
-- Idempotente: si el cuerpo ya dice v26.43-cola, no hace nada. Falla con raise si una ancla no matchea
-- (varias sesiones tocan esta funcion: se parte de pg_get_functiondef, nunca de una copia).
-- Al ejecutarlo hay que mandar el comentario -- REGLA_CONFIRMADA_POR_USUARIO (es un objeto con centinela).
--
-- Rollback: el bloque del final (saca el CTE y vuelve pick/arm a max(dur_s)); despues volver a congelar
-- tests/tools/vista-15.json y el md5 de GV_Huella_Objeto.

-- REGLA_CONFIRMADA_POR_USUARIO
do $do$
declare v_def text; v_new text; v_a text; v_p1 text; v_p2 text; v_cola text; v_obj text;
begin
  v_a  := $a$evok as (select * from ev where dur_s > 0 and dur_s < 24 * 3600),$a$;
  v_p1 := $a$pick as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TP' and e.tanda <> '' group by e.legajo, e.tanda),$a$;
  v_p2 := $a$arm  as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TAP' and e.tanda <> '' group by e.legajo, e.tanda),$a$;
  v_cola := $c$
cola as (   -- v26.43-cola (Luis, 02/10): lo que sigue a un TP/TAP SIN registro, hasta que el legajo empieza su
            -- proxima tarea registrada (o el fin de jornada), es picking/armado de esa tanda.
  select c.legajo, c.opcion, c.tanda,
         max(greatest(0, extract(epoch from (
           least(coalesce((select min(case when s.ts_inicio is not null and s.ts_inicio <= c.ts_cliente then c.ts_cliente
                                          else coalesce(s.ts_inicio, s.ts_cliente) end)
                             from base s
                            where s.legajo = c.legajo and s.ts_cliente > c.ts_cliente
                              and s.opcion not in ('PUB','AUB','PKC','ENT','RSP','ROC','RAG','FGU','FSS','IMPT','TAL','GST','MGR','PKM','SSG','PSP','NPD','PKAX')
                              and s.opcion !~ 'X$'
                              and not (s.opcion = c.opcion and s.tanda = c.tanda)), 'infinity'),
                 coalesce((select min(m.ts) from public."Movimientos_Stock" m
                            where m.tipo = 'baja_racks' and m.deposito in ('racks','racks_ch')
                              and m.legajo::text = c.legajo and m.ts > c.ts_cliente
                              and (m.ts at time zone 'America/Argentina/Buenos_Aires')::date = p_dia), 'infinity'),
                 least(now(), greatest((select max(u.ts_cliente) from base u where u.legajo = c.legajo),
                       (p_dia + coalesce((select e.h_sal from emp e where e.legajo = c.legajo), time '17:00'))
                         at time zone 'America/Argentina/Buenos_Aires')))
           - c.ts_cliente)))) as s
    from base c
   where c.opcion in ('TP','TAP') and c.tanda <> '' and c.tanda <> 'ANULADO'
   group by 1, 2, 3
),$c$;
  foreach v_obj in array array['public.gv_monitor_horas_operario_dia(date)', 'public.gv_horas_operario_detalle_v2(date)'] loop
    v_def := pg_get_functiondef(v_obj::regprocedure);
    if v_def like '%v26.43-cola%' then
      raise notice '% ya tiene la regla v26.43-cola: no se toca', v_obj; continue;
    end if;
    if position(v_a in v_def) = 0 or position(v_p1 in v_def) = 0 or position(v_p2 in v_def) = 0 then
      raise exception 'v26.43-cola: una ancla no matchea en % (evok %, pick %, arm %) — traer la definicion viva y rehacer el parche',
        v_obj, position(v_a in v_def) > 0, position(v_p1 in v_def) > 0, position(v_p2 in v_def) > 0;
    end if;
    v_new := replace(v_def, v_a, v_a || v_cola);
    v_new := replace(v_new, v_p1, $a$pick as (select e.legajo, e.tanda, max(e.dur_s) + coalesce(max(k.s), 0) as dur_s from evok e
          left join cola k on k.legajo = e.legajo and k.tanda = e.tanda and k.opcion = 'TP'
          where e.opcion = 'TP' and e.tanda <> '' group by e.legajo, e.tanda),$a$);
    v_new := replace(v_new, v_p2, $a$arm  as (select e.legajo, e.tanda, max(e.dur_s) + coalesce(max(k.s), 0) as dur_s from evok e
          left join cola k on k.legajo = e.legajo and k.tanda = e.tanda and k.opcion = 'TAP'
          where e.opcion = 'TAP' and e.tanda <> '' group by e.legajo, e.tanda),$a$);
    execute v_new;
    raise notice '% parcheada (v26.43-cola)', v_obj;
  end loop;
end $do$;

-- la huella (tests/tools/vista-15.json se re-congelo con esta version) y el centinela de la regla
update public."GV_Huella_Objeto"
   set md5_esperado = md5(pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure)),
       version = 'v26.43', actualizado_en = now()
 where objeto = 'gv_monitor_horas_operario_dia';
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_monitor_horas_operario_dia', 'funcion', 'max\(e\.dur_s\) \+ coalesce\(max\(k\.s\), 0\)',
       'La COLA sin registro despues del TP/TAP (hasta la proxima tarea registrada del legajo o el fin de jornada) se suma al picking/armado de esa tanda (Luis, 02/10). = index.html fetchMonitorDayStats colaMsDe.',
       'Luis', 'v26.43'
 where not exists (select 1 from public."GV_Reglas_Centinela" where objeto = 'gv_monitor_horas_operario_dia' and version = 'v26.43');

-- verificacion
select * from public.gv_huellas_cambiadas;      -- vacia
select * from public.gv_reglas_perdidas;        -- vacia
select legajo, hs_pick, hs_arm, hs_prod from public.gv_monitor_horas_operario_dia(date '2026-09-15') order by 1;
-- 104 0,00/0,00/0,36 · 237 0,00/6,63/6,63 · 277 7,77/0,00/7,77 · 8 0,01/8,76/12,10 · 94 0,00/0,00/0,00

/* ROLLBACK (con -- REGLA_CONFIRMADA_POR_USUARIO):
do $do$
declare v_def text; v_new text; v_obj text; v_ini int; v_fin int;
begin
  foreach v_obj in array array['public.gv_monitor_horas_operario_dia(date)', 'public.gv_horas_operario_detalle_v2(date)'] loop
    v_def := pg_get_functiondef(v_obj::regprocedure);
    if v_def not like '%v26.43-cola%' then continue; end if;
    v_ini := position($x$
cola as (   -- v26.43-cola$x$ in v_def);
    v_fin := position($x$   group by 1, 2, 3
),$x$ in v_def) + length($x$   group by 1, 2, 3
),$x$);
    v_new := left(v_def, v_ini - 1) || substr(v_def, v_fin);
    v_new := replace(v_new, 'max(e.dur_s) + coalesce(max(k.s), 0) as dur_s', 'max(e.dur_s) as dur_s');
    v_new := replace(v_new, $x$
          left join cola k on k.legajo = e.legajo and k.tanda = e.tanda and k.opcion = 'TP'$x$, '');
    v_new := replace(v_new, $x$
          left join cola k on k.legajo = e.legajo and k.tanda = e.tanda and k.opcion = 'TAP'$x$, '');
    execute v_new;
  end loop;
end $do$;
delete from public."GV_Reglas_Centinela" where objeto = 'gv_monitor_horas_operario_dia' and version = 'v26.43';
update public."GV_Huella_Objeto" set md5_esperado = md5(pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure)), version = 'v25.64', actualizado_en = now() where objeto = 'gv_monitor_horas_operario_dia';
*/
