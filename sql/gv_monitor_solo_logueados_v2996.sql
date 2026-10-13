-- v29.96 (Luis, 2026-10-13): EL MONITOR MUESTRA SOLO LEGAJOS QUE SE LOGUEARON
-- OJO: los marcadores de la base y el centinela dicen v29.90 (la version con que se aplico,
--      antes de que otra sesion se llevara ese numero): son la LLAVE, no se cambian.
--
-- Luis, textual: "se habra hecho como una prueba para ver visuales desde el admin, no deberían
-- aparecer esas cosas en el monitor. solo legajos que se hayan logueado (trabajadores o entrevistas)".
--
-- El caso: el 13/10 el monitor mostro al legajo 1 «en jornada» con UN evento suelto (un cierre de
-- Recepcion de Insumos) y SIN una sola fila de login ese dia. El CTE `base` no filtra las opciones
-- anuladas (`X`), asi que anular el evento no lo saca: lo que hay que mirar es si la persona ENTRO.
--
-- La regla: un legajo con eventos se muestra solo si ESE DIA se logueo (GV_Dispositivo_Login,
-- tipo operario, cualquier metodo: clave_tv, nombre, legajo, sesion_guardada, legajo_cervantes).
--   ⚠ CUALQUIER metodo, no solo los de LLEGADA (clave_tv/nombre, v27.68). Medido el 13/10 sobre los
--     36 pares (dia, legajo) con eventos desde el 30/09: con cualquier login entran 35 de 36 (el que
--     falta es justo el legajo 1 de hoy); con el filtro de llegada quedarian AFUERA 7 operarios
--     reales que ese dia entraron con `sesion_guardada` (104, 8, 94 el 30/09; 277 el 02/10 y el
--     08/10; 191 y 237 el 06/10).
--   ⚠ FAIL-OPEN: si ese dia NO hay NINGUN login registrado, no se filtra nada. Cubre el historico
--     (el registro de login empieza el 30/09, v25.25) y una caida del registro. Un dia sin logins
--     se ve exactamente como antes.
--
-- Es idempotente y falla con un raise si el texto no matchea (varias sesiones tocan esta vista).
do $gv$
declare d text; n text;
begin
  select pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure) into d;
  if position('v29.90-login' in d) > 0 then
    raise notice 'ya aplicado'; return;
  end if;

  n := replace(d,
    E'legajos as (select b.legajo from base b group by b.legajo union select r.legajo from rk_pts r)',
    E'login_dia as (   -- v29.90-login (Luis, 13/10): quien ENTRO a la app ese dia (cualquier metodo)\n'
    '  select btrim(l.legajo::text) as legajo\n'
    '    from public."GV_Dispositivo_Login" l\n'
    '   where l.tipo = ''operario''\n'
    '     and (l.created_at at time zone ''America/Argentina/Buenos_Aires'')::date = p_dia\n'
    '     and coalesce(btrim(l.legajo::text), '''') not in ('''', ''0'')\n'
    '   group by 1\n'
    '),\n'
    'legajos as (   -- v29.90-login: solo los que se loguearon; si ese dia no hay NINGUN login, no se filtra\n'
    '  select z.legajo from (select b.legajo from base b group by b.legajo\n'
    '                        union select r.legajo from rk_pts r) z\n'
    '   where exists (select 1 from login_dia d where d.legajo = z.legajo)\n'
    '      or not exists (select 1 from login_dia))');

  if n = d then raise exception 'el texto de gv_monitor_horas_operario_dia no matchea: NO se aplico nada'; end if;
  execute n;
end $gv$;

-- centinela: la regla no se puede perder.
-- OJO con el PATRON (regla v21.82): el centinela SACA LOS COMENTARIOS antes de buscar, asi que
-- el marcador `v29.90-login`, que vive en un `--`, vigila el rotulo y NO la regla (se probo: con
-- ese patron gv_reglas_perdidas daba "LA REGLA SE PERDIO" con la regla puesta).
-- Tampoco sirve `GV_Dispositivo_Login`: aparece 2 veces en el cuerpo y la otra es la regla v27.54
-- (la jornada arranca al fichar), o sea que borrando ESTA la palabra queda puesta.
-- El patron es `login_dia`: el CTE de esta regla y nada mas (3 apariciones, las 3 son la regla).
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_monitor_horas_operario_dia', 'funcion', 'login_dia',
       'El monitor muestra solo legajos que se loguearon ese dia (GV_Dispositivo_Login, cualquier metodo); si no hay ningun login ese dia no se filtra',
       'Luis', 'v29.90'
 where not exists (select 1 from public."GV_Reglas_Centinela" c
                    where c.objeto = 'gv_monitor_horas_operario_dia' and c.patron = 'login_dia');

-- la RPC que usa el FRONT para el mismo criterio (index.html fetchMonitorDayStats)
create or replace function public.gv_monitor_logueados(p_desde timestamptz, p_hasta timestamptz)
returns table(legajo text)
language sql stable security definer set search_path to 'public' as $fn$
  /* v29.90-login (Luis, 13/10): los legajos que ENTRARON a la app en la ventana. CUALQUIER metodo
     de login de operario — no solo los de llegada (clave_tv/nombre, v27.68): con el filtro de
     llegada quedaban afuera 7 operarios reales que entraron con `sesion_guardada`.
     Es el MISMO criterio que el CTE `login_dia` de gv_monitor_horas_operario_dia. */
  select btrim(l.legajo::text)
    from public."GV_Dispositivo_Login" l
   where l.tipo = 'operario'
     and l.created_at >= p_desde and l.created_at < p_hasta
     and coalesce(btrim(l.legajo::text), '') not in ('', '0')
     and p_hasta - p_desde <= interval '8 days'
   group by btrim(l.legajo::text)
$fn$;
revoke all on function public.gv_monitor_logueados(timestamptz, timestamptz) from public;
grant execute on function public.gv_monitor_logueados(timestamptz, timestamptz) to anon, authenticated, service_role;

-- ROLLBACK: reponer la definicion de zz_backups."GV_Backup_MonitorHoras_def_20261013"
--           y  drop function public.gv_monitor_logueados(timestamptz, timestamptz);
-- Y re-congelar la huella:
--   update public."GV_Huella_Objeto" set md5_esperado = '<md5_actual>', version = 'v29.90',
--          actualizado_en = now() where objeto = 'gv_monitor_horas_operario_dia';
