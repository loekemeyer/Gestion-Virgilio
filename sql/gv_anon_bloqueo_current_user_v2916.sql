-- v29.16 (Luis, 09/10, D13): el bloqueo de la clave pública (v28.52) mira QUIÉN EJECUTA, no el role de la sesión.
-- REGLA_CONFIRMADA_POR_USUARIO
--
-- Falso positivo medido: una función SECURITY DEFINER llamada con la clave pública escribe como postgres,
-- pero current_setting('role') sigue diciendo 'anon' → el trigger descartaba la escritura interna.
-- Perdidas 08-09/10: Importados_Mov_Stock 14 (gv_imp_imputar_ingreso_racks), Racks_Bajadas 4
-- (registrar_baja_racks), Fichadas_Historico 20 (espejo de fichadas). Stock y pedidos no se tocaron.
--
-- Arreglo: el trigger pasa a SECURITY INVOKER y mira current_user. Escritura directa con la clave
-- pública → current_user = anon → se bloquea igual. Escritura adentro de una función del sistema
-- (definer, dueño postgres) → current_user = postgres → entra.
-- El registro (gv_anon_insert_log) sigue definer; anon lo puede ejecutar SÓLO desde un trigger
-- (pg_trigger_depth() > 0): llamado directo por /rpc no hace nada.

create or replace function public.gv_anon_insert_log(p_tabla text, p_fila jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
    begin
      if pg_trigger_depth() = 0 then return; end if;   -- v29.16-anon-solo-trigger
      insert into public."GV_Anon_Insert_Bloqueado"(tabla, fila, headers)
      values (p_tabla, p_fila, nullif(current_setting('request.headers', true), '')::jsonb);
      perform public.tg_enqueue(
        '🚫 La clave pública intentó escribir en ' || p_tabla || ' (tabla cerrada el 08/10, v28.52). '
        || 'La fila NO entró y quedó guardada en GV_Anon_Insert_Bloqueado. Si es una pantalla real, hay que habilitarla.',
        'anon-bloqueo:' || p_tabla || ':' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYYMMDDHH24'));
    end $function$;

create or replace function public.gv_anon_insert_bloquear()
 returns trigger
 language plpgsql
 security invoker
 set search_path to 'public', 'pg_temp'
as $function$
    begin
      if current_user = 'anon' then   -- v28.52-anon-bloqueo · v29.16-current-user
        perform public.gv_anon_insert_log(tg_table_name, to_jsonb(new));
        return null;
      end if;
      return new;
    end $function$;

grant execute on function public.gv_anon_insert_log(text, jsonb) to anon;

update public."GV_Reglas_Centinela"
   set patron = 'current_user = ''anon''', version = 'v29.16'
 where id = 370;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_anon_insert_log', 'funcion', 'pg_trigger_depth\(\) = 0',
        'El registro del bloqueo de la clave pública sólo se dispara desde el trigger (llamado directo por /rpc no escribe ni manda Telegram)',
        'Luis', 'v29.16');

-- ROLLBACK: volver al cuerpo de v28.52 (security definer + current_setting('role', true) = 'anon'),
-- revoke execute on function public.gv_anon_insert_log(text, jsonb) from anon;
-- y el patrón 370 a: current_setting\('role', true\) = 'anon'
