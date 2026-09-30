-- =====================================================================
-- v25.37 (30/09) — Cervantes dice Sí / No a lo que Gestión Virgilio le recibió como destino «Cervantes».
--
-- [usuario 30/09] "que en el módulo de recepción de insumos (dentro de importados) me aparezca una
-- notificación en el sector correspondiente diciendo «Gestión Virgilio notificó que recibiste 3000
-- unidades de GRJ31: Sí/No». En el caso que sea Sí: sumar stock a ese componente. En el caso que sea
-- No: en el mismo lugar que se cargaron las 3000 uni del rallador que vuelvan a aparecer con un
-- cartelito de «Denegado por Cervantes»". Decidido en la charla: el No deja el pedido OTRA VEZ EN
-- VIAJE (📥 RECIBIR y 📦 Baches) para poder recibirlo de nuevo a otro destino.
--
-- El Sí y el No los resuelve GP2 ("GP2".resolver_ingreso_virgilio, repo gestion-productiva-2.0,
-- db/migracion_ingreso_virgilio_resolver.sql). GP2 no toca public (su Regla 0): sólo marca su fila
-- de "GP2".ingreso_virgilio como 'denegado'. Lo que pasa de ESTE lado lo hace un trigger de Virgilio
-- sobre esa tabla, que es la frontera donde hablan las dos plantas (Virgilio ya escribe ahí).
--
-- ⚠ Se aplicó en la base con la etiqueta v25.31 (así dicen los comentarios de las funciones, el marcador
-- 'v25.31-cerv-no' y la columna version de GV_Reglas_Centinela): otra sesión pusheó v25.31-v25.33 mientras
-- tanto y el front salió como v25.37. El marcador es la llave de idempotencia: no cambiarlo.
--
-- Se aplica sobre las definiciones VIVAS (varias sesiones tocan estos objetos) y cada parche es
-- idempotente y falla con un raise si el texto no matchea.
-- =====================================================================

-- ---------- 1) la cuenta del resync, sin el chequeo de supervisor ----------
-- El «No» lo dispara un operario de Cervantes (logueado en GP2), que no es supervisor de Virgilio:
-- llamando a gv_importados_resync el trigger explotaba. La cuenta pasa a una función INTERNA (sin
-- grant a anon/authenticated) y gv_importados_resync la llama después de su chequeo, que no cambia
-- (centinela 210). Una sola copia de la cuenta.
create or replace function public.gv_importados_resync_calc(p_importado_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_codstock text;
begin
  select gv_cod_stock(cod_art) into v_codstock from public."Importados" where id = p_importado_id;
  if v_codstock is null then return; end if;

  update public."Importados" im
  set pedido_curso = coalesce((
        select sum(greatest(0, b.unidades - b.unidades_llegadas))
        from public."GV_Importados_Baches" b
        where b.importado_id = im.id and b.estado = 'en_curso'), 0),
      actualizado = now()
  where im.id = p_importado_id;

  update public."Importados" im
  set reingreso_est = (
        select min(b.fecha_reingreso)
        from public."GV_Importados_Baches" b
        join public."Importados" im2 on im2.id = b.importado_id
        where gv_cod_stock(im2.cod_art) = v_codstock
          and b.estado = 'en_curso'
          and greatest(0, b.unidades - b.unidades_llegadas) > 0
          and b.fecha_reingreso is not null),
      actualizado = now()
  where gv_cod_stock(im.cod_art) = v_codstock;
end $function$;
revoke execute on function public.gv_importados_resync_calc(bigint) from public, anon, authenticated;

create or replace function public.gv_importados_resync(p_importado_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  -- v22.96-sup: sólo supervisor (Thomas 26/09, cierra la v22.81)
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor logueado puede guardar en Importación (iniciá sesión con Google; si ya estás, actualizá la app).' using errcode = '42501';
  end if;
  -- v25.31: la cuenta vive en gv_importados_resync_calc (también la usa el «No» de Cervantes)
  perform public.gv_importados_resync_calc(p_importado_id);
end $function$;

-- ---------- 2) de qué línea de la recepción es lo denegado ----------
alter table public."GV_Imp_Recepcion_Destino"
  add column if not exists denegado_en timestamptz,
  add column if not exists denegado_por text,
  add column if not exists denegado_motivo text,
  add column if not exists denegado_unidades numeric;
comment on column public."GV_Imp_Recepcion_Destino".denegado_en is
  'v25.31: Cervantes dijo que esto NO le llegó (Sí/No en Recepción de Insumos de GP2). El pedido volvió a en viaje.';

-- ---------- 3) al insertar el aviso: cuántas UNIDADES son ----------
-- GP2 suma unidades. Si Virgilio lo mandó en cajas, la conversión la sabe Virgilio (uni_x_caja de SU
-- recepción), no GP2.
create or replace function public.gv_ingreso_virgilio_unidades()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.unidades is null then
    if lower(coalesce(new.unidad, '')) in ('unidades', 'uni', 'u') then
      new.unidades := new.cantidad;
    elsif lower(coalesce(new.unidad, '')) = 'cajas' then
      new.unidades := new.cantidad * (select nullif(r.uni_x_caja, 0) from public."GV_Imp_Recepcion" r where r.id = new.recepcion_id);
    end if;
  end if;
  return new;
end $function$;
revoke execute on function public.gv_ingreso_virgilio_unidades() from public, anon, authenticated;
drop trigger if exists gv_ingreso_virgilio_unidades on "GP2".ingreso_virgilio;
create trigger gv_ingreso_virgilio_unidades before insert on "GP2".ingreso_virgilio
  for each row execute function public.gv_ingreso_virgilio_unidades();

-- ---------- 4) el «No»: el pedido vuelve a EN VIAJE ----------
-- Si algo no cierra (recepción anulada, pedido anulado, sin unidades), el No de Cervantes NO se
-- frena — Cervantes no puede arreglar Virgilio —: queda anotado en virgilio_revertido_error y lo
-- muestra el centinela gv_ingreso_cervantes_sin_revertir. El bloque interno deshace lo que haya
-- escrito a medias (subtransacción).
create or replace function public.gv_ingreso_virgilio_denegado()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare b record; r record; v_uni numeric; v_dest bigint;
begin
  -- v25.31-cerv-no: Cervantes dijo No -> el pedido vuelve a estar en viaje, con «Denegado por Cervantes»
  if new.virgilio_revertido_en is not null then return new; end if;
  begin
    v_uni := coalesce(new.unidades, case when lower(coalesce(new.unidad, '')) in ('unidades', 'uni', 'u') then new.cantidad end);
    if v_uni is null or v_uni <= 0 then raise exception 'no se sabe cuántas unidades son (% %)', new.cantidad, new.unidad; end if;
    select * into r from public."GV_Imp_Recepcion" where id = new.recepcion_id;
    if not found then raise exception 'la recepción % no existe en Virgilio', new.recepcion_id; end if;
    if r.anulada_en is not null then raise exception 'la recepción % ya estaba anulada en Virgilio', r.id; end if;
    select * into b from public."GV_Importados_Baches" where id = coalesce(new.bache_id, r.bache_id) for update;
    if not found then raise exception 'el pedido (bache %) ya no existe', coalesce(new.bache_id, r.bache_id); end if;
    if b.estado = 'anulado' then raise exception 'el pedido (bache %) está anulado', b.id; end if;
    update public."GV_Importados_Baches"
       set unidades_llegadas = greatest(0, unidades_llegadas - round(v_uni)::int), estado = 'en_curso', actualizado = now()
     where id = b.id;
    select d.id into v_dest from public."GV_Imp_Recepcion_Destino" d
     where d.recepcion_id = r.id and d.destino = 'cervantes' and d.denegado_en is null
     order by (d.cantidad = new.cantidad) desc, d.id limit 1;
    if v_dest is null then raise exception 'la recepción % no tiene una línea a Cervantes sin resolver', r.id; end if;
    update public."GV_Imp_Recepcion_Destino"
       set denegado_en = now(), denegado_por = new.denegado_por, denegado_motivo = new.denegado_motivo, denegado_unidades = v_uni
     where id = v_dest;
    insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
    values (now(), b.cod_art, b.marca, 'ajuste', -v_uni,
            'Cervantes denegó recepcion importacion #' || r.id || coalesce(' · ' || new.denegado_motivo, ''),
            coalesce(new.denegado_por, 'cervantes'), now());
    perform public.gv_importados_resync_calc(b.importado_id);
    new.virgilio_revertido_en := now();
    new.virgilio_revertido_error := null;
  exception when others then
    new.virgilio_revertido_error := left(sqlerrm, 500);
  end;
  return new;
end $function$;
revoke execute on function public.gv_ingreso_virgilio_denegado() from public, anon, authenticated;
drop trigger if exists gv_ingreso_virgilio_denegado on "GP2".ingreso_virgilio;
create trigger gv_ingreso_virgilio_denegado before update of estado on "GP2".ingreso_virgilio
  for each row when (old.estado = 'pendiente' and new.estado = 'denegado')
  execute function public.gv_ingreso_virgilio_denegado();

-- ---------- 5) el chip: qué pedidos en viaje volvieron por un No ----------
create or replace function public.gv_imp_cervantes_denegados()
 returns table(bache_id bigint, importado_id bigint, cod_art text, recepcion_id bigint, unidades numeric,
               motivo text, denegado_en timestamptz, denegado_por text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select b.id, b.importado_id, b.cod_art, r.id, d.denegado_unidades, d.denegado_motivo, d.denegado_en, d.denegado_por
    from public."GV_Imp_Recepcion_Destino" d
    join public."GV_Imp_Recepcion" r on r.id = d.recepcion_id
    join public."GV_Importados_Baches" b on b.id = r.bache_id
   where d.denegado_en is not null and b.estado = 'en_curso'
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   order by d.denegado_en desc;
$function$;
revoke execute on function public.gv_imp_cervantes_denegados() from public, anon;
grant execute on function public.gv_imp_cervantes_denegados() to authenticated, service_role;

-- ---------- 6) centinela: un No que Virgilio no pudo aplicar ----------
create or replace view public.gv_ingreso_cervantes_sin_revertir with (security_invoker = true) as
  select i.id, i.creado_en, i.cod_importado, i.cod_insumo, i.cantidad, i.unidad, i.unidades,
         i.bache_id, i.recepcion_id, i.denegado_en, i.denegado_por, i.denegado_motivo, i.virgilio_revertido_error
    from "GP2".ingreso_virgilio i
   where i.estado = 'denegado' and i.virgilio_revertido_en is null;
comment on view public.gv_ingreso_cervantes_sin_revertir is
  'v25.31: Cervantes dijo No y Virgilio no pudo volver a poner el pedido en viaje. Vacía = todo bien.';
revoke all on public.gv_ingreso_cervantes_sin_revertir from anon;
grant select on public.gv_ingreso_cervantes_sin_revertir to authenticated, service_role;

-- ---------- 7) parches sobre la definición VIVA ----------
do $patch$
declare d text; n text;
begin
  -- 7a) historial: la línea a Cervantes dice si Cervantes la denegó
  d := pg_get_functiondef('public.gv_imp_recepcion_historial(integer)'::regprocedure);
  if d !~ 'denegado_en' then
    n := replace(d, $x$'resolucion', d.resolucion)$x$,
         $x$'resolucion', d.resolucion, 'denegado_en', d.denegado_en, 'denegado_por', d.denegado_por, 'denegado_motivo', d.denegado_motivo, 'denegado_unidades', d.denegado_unidades)$x$);
    if n = d then raise exception 'gv_imp_recepcion_historial: el texto no matcheó, no se parcheó'; end if;
    execute n;
  end if;
  -- 7b) anular una recepción que Cervantes ya denegó: lo denegado ya salió del pedido, no se descuenta dos veces
  d := pg_get_functiondef('public.gv_imp_recepcion_anular(bigint,text)'::regprocedure);
  if d !~ 'denegado_unidades' then
    n := replace(d, $x$'ajuste', -r.unidades, 'anula recepcion importacion #'$x$,
         $x$'ajuste', -(r.unidades - coalesce((select sum(d2.denegado_unidades) from public."GV_Imp_Recepcion_Destino" d2 where d2.recepcion_id = p_id and d2.denegado_en is not null), 0)), 'anula recepcion importacion #'$x$);
    if n = d then raise exception 'gv_imp_recepcion_anular: el texto no matcheó, no se parcheó'; end if;
    execute n;
  end if;
end $patch$;

-- ---------- 8) centinelas ----------
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_ingreso_virgilio_denegado', 'funcion', $p$estado = 'en_curso'$p$,
   'Si Cervantes dice No a lo que Virgilio le recibió, el pedido vuelve a EN VIAJE en Virgilio (📥 RECIBIR y 📦 Baches) con el chip «Denegado por Cervantes».',
   'dueño (30/09)', 'v25.31'),
  ('gv_ingreso_virgilio_denegado', 'funcion', 'gv_importados_resync_calc',
   'El No de Cervantes recalcula el pedido en curso con la función INTERNA: el operario de Cervantes no es supervisor de Virgilio y gv_importados_resync lo rechazaría.',
   'dueño (30/09)', 'v25.31'),
  ('gv_importados_resync', 'funcion', 'gv_importados_resync_calc',
   'La cuenta del resync vive en UNA función (gv_importados_resync_calc): la usan el resync de supervisor y el No de Cervantes.',
   'dueño (30/09)', 'v25.31'),
  ('gv_imp_recepcion_anular', 'funcion', 'denegado_unidades',
   'Anular una recepción que Cervantes ya denegó no vuelve a descontar lo denegado en Importados_Mov_Stock.',
   'dueño (30/09)', 'v25.31')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);
