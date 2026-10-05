-- =====================================================================================
-- v26.65 · «FRENAR la tanda» — parte 2b (Luis, 2026-10-05)
-- Proyecto Gestión Virgilio (hrxfctzncixxqmpfhskv). APLICADO el 05/10 (el pedido es la autorización).
--
--   1. gv_tanda_frenar: la ventana del fichaje se mide desde que la tanda volvió a ser TOMADA
--      (ts_estado), no desde la primera toma (ts). Sin esto, al retomarla al otro día el FJ de
--      ayer la volvía a frenar. Marcador 'v26.64-fichaje' (llave, no cambiar).
--   2. gv_tandas_frenar_fichaje(p_simular): «se frena sola cuando ficha salida». Cron 129
--      'gv-tandas-frenar-fichaje' ('6-59/10 * * * *'). Se creó APAGADO y se prendió con el push
--      del front v26.65 (el «▶ Seguir» de un celular viejo no pasa por la reserva).
--   3. gv_tandas_frenadas_de(p_legajo): para el aviso «Tenés la tanda X frenada. ¿La retomás?».
--   4. gv_tanda_lock_estado(p_tanda): para el «✋ Frenar» del supervisor en «Modificar tanda».
--
-- Centinelas 307-310. Prueba (05/10, transacción abortada): de 3 tandas tomadas con FJ, frenó
-- sólo la que no tenía TP ni actividad después del FJ; el PKF quedó con la hora del FJ y
-- ts_inicio = su EP; retomada por el dueño, la segunda corrida no la volvió a frenar.
-- =====================================================================================

-- 1) gv_tanda_frenar: ventana del fichaje ------------------------------------------------
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10)
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_tanda_frenar(text,text,text,text,text,timestamptz)'::regprocedure);
  if d like '%v26.64-fichaje%' then raise notice 'ya estaba'; return; end if;
  n := replace(d, $a$                      and fj.ts_cliente >= r.ts) then$a$,
                  $a$                      and fj.ts_cliente >= coalesce(r.ts_estado, r.ts)) then   -- v26.64-fichaje: desde que la volvió a tomar$a$);
  n := replace(n, $a$and fj.ts_cliente >= coalesce(v_ini, r.ts);$a$,
                  $a$and fj.ts_cliente >= greatest(coalesce(v_ini, r.ts), coalesce(r.ts_estado, r.ts));$a$);
  if n = d or n not like '%v26.64-fichaje%' or n not like '%greatest(coalesce(v_ini, r.ts), coalesce(r.ts_estado, r.ts))%' then
    raise exception 'gv_tanda_frenar: el texto no matcheó';
  end if;
  execute n;
end $p$;

-- 2) el freno al fichar salida -------------------------------------------------------------
create or replace function public.gv_tandas_frenar_fichaje(p_simular boolean default false)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
-- v26.64-fichaje (Luis, 05/10): «se frena sola cuando ficha salida». Una tanda TOMADA cuyo dueño
-- hizo Terminar Día (FJ) después de tomarla, y que no volvió a trabajar desde ese FJ, pasa a
-- FRENADA por gv_tanda_frenar(…, 'fichaje') — que deja el PKF/APF con la hora del FJ.
-- No toca: la que ya tiene su TP/TAP (el candado no se enteró), la que nunca tuvo EP/AP del
-- dueño (reservó y no arrancó) ni la de un legajo de prueba. Lo llama el cron gv-tandas-frenar-fichaje.
declare
  r record; v jsonb; n int := 0; det jsonb := '[]'::jsonb;
begin
  for r in
    select l.tanda, l.fase, l.legajo, fj.ts as fj
      from public."GV_Tandas_Lock" l
      cross join lateral (select max(e.ts_cliente) as ts from public."Registros_Produccion_Virgilio" e
                           where e.opcion = 'FJ' and btrim(e.legajo) = l.legajo
                             and e.ts_cliente >= coalesce(l.ts_estado, l.ts)) fj
     where l.estado = 'tomada' and coalesce(l.legajo, '') <> '' and not public.es_legajo_test(l.legajo)
       and coalesce(l.ts_estado, l.ts) >= now() - interval '3 days'
       and fj.ts is not null
       -- arrancó de verdad (su EP/AP de esta tanda)
       and exists (select 1 from public."Registros_Produccion_Virgilio" a
                    where a.opcion = case l.fase when 'picking' then 'EP' else 'AP' end
                      and upper(btrim(a.texto)) = l.tanda and btrim(a.legajo) = l.legajo)
       -- volvió a trabajar después del FJ: ya está en el depósito, no se le frena nada
       and not exists (select 1 from public."Registros_Produccion_Virgilio" x
                        where btrim(x.legajo) = l.legajo and x.ts_cliente > fj.ts
                          and x.opcion not in ('FJ','PKF','APF'))
       -- la fase ya se cerró aunque el candado no se enteró
       and not exists (select 1 from public."Registros_Produccion_Virgilio" c
                        where c.opcion = case l.fase when 'picking' then 'TP' else 'TAP' end
                          and upper(btrim(split_part(c.texto, '|', 1))) = l.tanda)
  loop
    if p_simular then v := jsonb_build_object('simulado', true);
    else v := public.gv_tanda_frenar(r.tanda, r.fase, r.legajo, 'fichaje');
    end if;
    det := det || jsonb_build_array(jsonb_build_object('tanda', r.tanda, 'fase', r.fase, 'legajo', r.legajo, 'fj', r.fj, 'resultado', v));
    n := n + 1;
  end loop;
  return jsonb_build_object('tandas', n, 'detalle', det);
end $function$;
revoke all on function public.gv_tandas_frenar_fichaje(boolean) from public, anon, authenticated;

-- 3) aviso del día siguiente ---------------------------------------------------------------
create or replace function public.gv_tandas_frenadas_de(p_legajo text)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  -- v26.64-aviso (Luis, 05/10): «Tenés la tanda X frenada. ¿La retomás?» — sólo las que siguen
  -- frenadas a nombre de ese legajo y que nadie tomó (las tomadas ya no están 'frenada').
  select coalesce(jsonb_agg(jsonb_build_object('tanda', l.tanda, 'fase', l.fase, 'ts_freno', f.ts_freno,
                                               'motivo', f.motivo, 'ubicacion', f.ubicacion) order by f.ts_freno), '[]'::jsonb)
    from public."GV_Tandas_Lock" l
    join lateral (select z.ts_freno, z.motivo, z.ubicacion from public."GV_Tanda_Freno" z
                   where z.tanda = l.tanda and z.fase = l.fase and z.retomada_ts is null
                   order by z.ts_freno desc limit 1) f on true
   where l.estado = 'frenada' and l.legajo = btrim(coalesce(p_legajo, ''))
     and coalesce(l.ts_estado, l.ts) >= now() - interval '10 days';
$function$;
revoke all on function public.gv_tandas_frenadas_de(text) from public;
grant execute on function public.gv_tandas_frenadas_de(text) to anon, authenticated;

-- 4) para el «✋ Frenar» del supervisor ------------------------------------------------------
create or replace function public.gv_tanda_lock_estado(p_tanda text)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  -- v26.64-sup (Luis, 05/10): para el «✋ Frenar» del supervisor — qué fase de la tanda está
  -- tomada / frenada y por quién. Sólo lectura (lo mismo que ya muestra el monitor).
  select coalesce(jsonb_agg(jsonb_build_object(
           'fase', l.fase, 'estado', l.estado, 'legajo', l.legajo,
           'nombre', coalesce(nullif(btrim(l.nombre), ''),
                              (select e."Empleado" from public."Empleados" e where btrim(e."Legajo"::text) = l.legajo limit 1)),
           'ts', l.ts, 'ts_estado', l.ts_estado) order by l.fase), '[]'::jsonb)
    from public."GV_Tandas_Lock" l
   where l.tanda = upper(btrim(coalesce(p_tanda, '')));
$function$;
revoke all on function public.gv_tanda_lock_estado(text) from public;
grant execute on function public.gv_tanda_lock_estado(text) to anon, authenticated;

-- 5) cron ----------------------------------------------------------------------------------
-- select cron.schedule('gv-tandas-frenar-fichaje', '6-59/10 * * * *', 'select public.gv_tandas_frenar_fichaje(false)');   -- jobid 129
-- select cron.alter_job(129, active := true);   -- se prende con el push del front v26.65

-- Chequeo:
--   select public.gv_tandas_frenar_fichaje(true);          -- qué frenaría ahora, sin tocar nada
--   select * from public."GV_Tanda_Freno" order by id desc limit 20;
--   select * from public.gv_reglas_perdidas;                -- vacía

-- ROLLBACK:
--   select cron.alter_job(129, active := false);            -- (o cron.unschedule('gv-tandas-frenar-fichaje'))
--   gv_tanda_frenar: reaplicar el bloque 1 de sql/gv_tanda_frenada_v2662.sql (create or replace).
--   Las tres funciones nuevas no tienen lectores fuera del front v26.65: se pueden dejar o dropear.
--   update public."GV_Reglas_Centinela" set activo = false where id between 307 and 310;
