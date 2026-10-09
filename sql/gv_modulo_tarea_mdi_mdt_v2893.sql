-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 09/10/2026: "todos deberían tener la lógica igual que los otros módulos ...
--   para el tracking de tiempo más efectivo posible")
-- v28.93 — Mover racks / Completar Pedido / Pasar a urgente / Insumos y Productos son TAREAS (≡ BR/MG):
--   MDI = empieza (texto = el código del módulo) · MDT = termina (ts_inicio = cuándo empezó; texto = el código o ANULADO).
--   Monitor (gv_monitor_horas_operario_dia ≡ fetchMonitorDayStats): MDT es MOVIMIENTO; MDT ANULADO es cancelación (no prod).
--   Sueldos (gv_horas_operario_detalle_v2): MDT en la columna rg (MG+RT); anulada en ANU.
--   Alarma de inactividad del servidor: un MDI sin su MDT es una tarea abierta.
-- Se aplica sobre la definición VIVA (pg_get_functiondef), es idempotente (marcador 'MDI') y falla si un texto no matchea.
do $x$
declare
  f text; d text; n int;
  rep text[];
  fns text[] := array['public.gv_monitor_horas_operario_dia(date)','public.gv_horas_operario_detalle_v2(date)',
                      'public.gv_horas_operario_tandas_v2(date)','public.gv_alerta_inactivo_servidor(boolean,timestamptz)'];
  i int;
begin
  foreach f in array fns loop
    d := pg_get_functiondef(f::regprocedure);
    if position('''MDI''' in d) > 0 then continue; end if;
    if f like '%alerta_inactivo%' then
      rep := array[
        $a$('EP','AP','MGI','RKI','IRI','AT'$a$, $a$('EP','AP','MGI','RKI','IRI','MDI','AT'$a$,
        $a$(a.opcion='IRI' and c.opcion='IRT')$a$, $a$(a.opcion='IRI' and c.opcion='IRT') or (a.opcion='MDI' and c.opcion='MDT')$a$];
    else
      rep := array[
        $a$when 'IRI' then 'IRT' else$a$, $a$when 'IRI' then 'IRT' when 'MDI' then 'MDT' /* v28.93-mdt */ else$a$,
        $a$'MGI','RKI','IRI','CR'$a$, $a$'MGI','RKI','IRI','MDI','CR'$a$,
        $a$'RI','EI','RKB','IRT')))$a$, $a$'RI','EI','RKB','IRT','MDT')))$a$];
      if f like '%monitor_horas%' then
        rep := rep || array[
          $a$or (e.opcion = 'MG' and e.cruza)) and e.tanda <> 'ANULADO') as mov_s$a$, $a$or (e.opcion = 'MG' and e.cruza) or e.opcion = 'MDT') and e.tanda <> 'ANULADO') as mov_s$a$,
          $a$e.opcion in ('CC','CR','RR','RT','RI','EI')))$a$, $a$e.opcion in ('CC','CR','RR','RT','RI','EI','MDT')))$a$];
      elsif f like '%detalle_v2%' then
        rep := rep || array[
          $a$e.tanda = 'ANULADO' and e.opcion in ('CC','CR','RR','RT','RI','EI')$a$, $a$e.tanda = 'ANULADO' and e.opcion in ('CC','CR','RR','RT','RI','EI','MDT')$a$,
          $a$('CC','CR','RR','RT','RI','EI','RKB','IRT','AT'$a$, $a$('CC','CR','RR','RT','RI','EI','RKB','IRT','MDT','AT'$a$,
          $a$a.k in ('MG','RT')$a$, $a$a.k in ('MG','RT','MDT')$a$];
      end if;
    end if;
    i := 1;
    while i < array_length(rep,1) loop
      n := (length(d) - length(replace(d, rep[i], ''))) / length(rep[i]);
      if n = 0 then raise exception 'v28.93: % no tiene «%»', f, rep[i]; end if;
      d := replace(d, rep[i], rep[i+1]);
      i := i + 2;
    end loop;
    execute d;
  end loop;
end
$x$;

-- centinela y huella
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_monitor_horas_operario_dia', 'funcion', $p$'IRT','MDT'\)$p$,
       'MDT (Mover racks / CP / RC / Insumos) cuenta como movimiento', 'Luis', 'v28.93'
 where not exists (select 1 from public."GV_Reglas_Centinela" where version = 'v28.93' and objeto = 'gv_monitor_horas_operario_dia');
update public."GV_Huella_Objeto" h
   set md5_esperado = md5(p.prosrc), version = 'v28.93', actualizado_en = now()
  from pg_proc p
 where p.oid = 'public.gv_monitor_horas_operario_dia(date)'::regprocedure and h.objeto = 'gv_monitor_horas_operario_dia';
