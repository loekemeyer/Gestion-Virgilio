-- ============================================================================
-- v17.39 (2026-09-14, pedido de Luis) — TODO comentario lleva IDENTIDAD
-- ============================================================================
-- Luis: *"para alguien que deja un comentario, siempre tiene que estar vinculado con una
-- identidad (Vivi, Marian, Otro — y si marcan Otro, que tenga un cuadro de texto)"*.
--
-- Hasta la v17.34 la identidad se pedía sólo al APROBAR. Pero el log lo escriben tres
-- acciones —aprobar, devolver a Cuarentena y comentar— y las tres dejan una línea que alguien
-- va a leer después. **Una línea sin nombre no sirve: no se le puede volver a preguntar a
-- nadie.** Así que ahora la identidad es obligatoria en las tres, y no sólo en el navegador:
-- las funciones la exigen, porque una validación que vive sólo en el front no es validación.
--
-- `persona` y `por` son dos cosas distintas y se guardan separadas: `por` es el mail de la
-- sesión que apretó el botón (sale solo del JWT) y `persona` es quién lo dijo. Al leer el log
-- lo que se busca es la segunda.
--
-- ⚠ ESTE ARCHIVO REEMPLAZA a `gv_cuarentena_comentar` / `gv_cuarentena_comentarios` de
-- `sql/gv_cuarentena_comentarios_v1715.sql` y a `gv_cuarentena_devolver` de
-- `sql/gv_cuarentena_log_v1723.sql`. El resto de esos archivos sigue vigente.
--
-- ⚠⚠ UNA TRAMPA QUE MORDIÓ ACÁ, y está documentada en el CLAUDE.md: el primer intento agregó
-- la validación con un `replace()` sobre `pg_get_functiondef`, y le metió una referencia a
-- `p_persona`… que NO estaba en la firma de `gv_cuarentena_comentar`. **plpgsql no valida el
-- cuerpo al crear la función**, así que el CREATE salió sin un solo error y la función quedó
-- rota, lista para explotar en la primera llamada. Se descubrió al mirar la definición viva.
-- Por eso abajo va el CREATE completo (firma incluida) y por eso se probó LLAMÁNDOLAS.
--
-- PROBADO (2026-09-14, en un DO con `raise exception` final para revertir):
--   1. `gv_cuarentena_comentar` sin persona → falla con "Falta indicar quién deja el comentario".
--   2. con persona → inserta y devuelve la fila con `persona = 'Vivi'`.
--   3. `gv_cuarentena_devolver` sin persona → falla con "Falta indicar quién devuelve…".
--   Las tres pasaron y no quedó nada escrito.
--
-- ROLLBACK: reaplicar las definiciones de `sql/gv_cuarentena_comentarios_v1715.sql` (comentar y
-- comentarios) y el bloque de `devolver` de `sql/gv_cuarentena_log_v1723.sql`.
-- ============================================================================

-- ── comentar: la identidad es obligatoria y se guarda ──────────────────────
drop function if exists public.gv_cuarentena_comentar(text,text,text,text,text);
create function public.gv_cuarentena_comentar(
  p_empresa text, p_order_id text, p_texto text, p_np text default null,
  p_por text default null, p_persona text default null)
returns table(id bigint, creado_at timestamptz, persona text, por text, texto text)
language plpgsql security definer set search_path to 'public'
as $function$
declare v_persona text; v_quien text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede comentar en cuarentena.' using errcode='42501';
  end if;
  if coalesce(btrim(p_texto),'') = '' then
    raise exception 'El comentario no puede estar vacío.' using errcode='22023';
  end if;
  -- v17.39 (Luis, 2026-09-14): "para alguien que deja un comentario, siempre tiene que estar
  -- vinculado con una identidad". Un comentario sin nombre no sirve para nada después: no se
  -- puede volver a preguntar. `por` (el mail de la sesión) no alcanza — dice quién tipeó, no
  -- quién lo dijo, que es lo que se mira cuando alguien revisa por qué salió un pedido.
  v_persona := nullif(btrim(p_persona),'');
  if v_persona is null then
    raise exception 'Falta indicar quién deja el comentario.' using errcode='22023';
  end if;
  v_quien := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  return query
  insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
  values (lower(p_empresa), nullif(btrim(p_order_id),''), nullif(btrim(p_np),''), btrim(p_texto),
          v_quien, v_persona)
  returning "GV_Cuarentena_Comentarios".id, "GV_Cuarentena_Comentarios".creado_at,
            "GV_Cuarentena_Comentarios".persona, "GV_Cuarentena_Comentarios".por,
            "GV_Cuarentena_Comentarios".texto;
end;
$function$;
revoke all on function public.gv_cuarentena_comentar(text,text,text,text,text,text) from public, anon;
grant execute on function public.gv_cuarentena_comentar(text,text,text,text,text,text) to authenticated, service_role;


-- ── leer el log de un pedido: ahora devuelve la identidad ──────────────────
drop function if exists public.gv_cuarentena_comentarios(text,text);
create function public.gv_cuarentena_comentarios(p_empresa text, p_order_id text)
returns table(id bigint, creado_at timestamptz, persona text, por text, texto text)
language sql stable security definer set search_path to 'public'
as $function$
  -- v17.39 (Luis, 2026-09-14): devuelve también `persona` — la identidad de quien dejó el
  -- comentario (Vivi / Marian / lo que escribieron en "Otro"), que es distinta del `por`
  -- (el mail de la sesión que lo tipeó) y es la que se busca al leer el log.
  select c.id, c.creado_at, c.persona, c.por, c.texto
    from public."GV_Cuarentena_Comentarios" c
   where c.empresa = lower(p_empresa) and c.order_id = nullif(btrim(p_order_id),'')
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by c.creado_at;
$function$;
revoke all on function public.gv_cuarentena_comentarios(text,text) from public, anon;
grant execute on function public.gv_cuarentena_comentarios(text,text) to authenticated, service_role;


-- ── devolver a Cuarentena: también exige identidad ─────────────────────────
drop function if exists public.gv_cuarentena_devolver(text,text,text,text,text);
create or replace function public.gv_cuarentena_devolver(
  p_empresa text, p_np text, p_clave text default null,
  p_comentario text default null, p_por text default null, p_persona text default null)
returns table(np_sacadas integer, detalle text)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_np text := btrim(coalesce(p_np,''));
  v_clave text := nullif(btrim(coalesce(p_clave, p_np, '')), '');
  v_quien text; v_persona text; v_n integer := 0; v_det text; v_cod text; v_rs text;
begin
  -- v17.20 — "Enviar a → Cuarentena": devolver el pedido a Cuarentena de verdad, no sólo despintar
  -- la marca de aprobado. Si sólo se borrara la fila de GV_Cuarentena_Liberados, el pedido seguiría
  -- en su tanda y saliendo igual: el botón sería mentiroso. Así que además se lo SACA DE LA
  -- PROGRAMACIÓN, que es lo que lo devuelve a "A Programar" — y ahí gv_cuarentena_marcar lo vuelve
  -- a retener solo. Las guardas fuertes las ponen las funciones que ya existían y acá se reusan:
  -- web → gv_ppp_web_desprogramar (falla si alguna tanda ya se empezó a trabajar);
  -- ISIS → gv_ppp_isis_desprogramar (falla si la NP ya tuvo Carga Camión o Recepción Remitos).
  -- v17.23: queda registrado en GV_Cuarentena_Log con la persona que lo devolvió.
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede devolver un pedido a cuarentena.' using errcode='42501';
  end if;
  if v_np = '' then raise exception 'No me pasaste la NP.'; end if;
  v_quien   := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  v_persona := nullif(btrim(p_persona),'');
  -- v17.39 (Luis): devolver también deja una línea en el log, así que también lleva identidad.
  if v_persona is null then
    raise exception 'Falta indicar quién devuelve el pedido a cuarentena.' using errcode='22023';
  end if;

  if v_np ~* '^(LK|CH)\s*\d+' then
    select w.np_sacadas into v_n from public.gv_ppp_web_desprogramar(v_np, v_quien) w;
    v_det := v_np;
  else
    select i.np_sacadas, i.detalle into v_n, v_det
      from public.gv_ppp_isis_desprogramar(array[v_np],
             'vuelta a Cuarentena' || coalesce(': ' || nullif(btrim(p_comentario),''), ''), v_quien) i;
  end if;

  delete from public."GV_Cuarentena_Liberados" lb
   where lb.empresa = lower(p_empresa) and lb.order_id = v_clave;

  insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
  values (lower(p_empresa), v_clave, v_np,
          '↩ Vuelto a Cuarentena (sacado de la programación)' ||
          coalesce(': ' || nullif(btrim(p_comentario),''), '.'), v_quien, v_persona);

  select l.cod, l.razon_social into v_cod, v_rs
    from public."GV_Cuarentena_Log" l
   where l.empresa = lower(p_empresa) and l.clave = v_clave
   order by l.at desc, l.id desc limit 1;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, persona, por, comentario)
  values (lower(p_empresa), v_clave, v_np, v_cod, v_rs, 'devuelto', v_persona, v_quien,
          nullif(btrim(p_comentario),''));

  return query select coalesce(v_n,0), coalesce(v_det, v_np);
end;
$function$;
revoke all on function public.gv_cuarentena_devolver(text,text,text,text,text,text) from public, anon;
grant execute on function public.gv_cuarentena_devolver(text,text,text,text,text,text) to authenticated, service_role;
-- Chequeo (no deja nada escrito):
--   do $$ declare r record; begin
--     begin perform public.gv_cuarentena_comentar('lk','<clave>','x',null,'t',null);
--     exception when others then raise notice 'sin persona falla: %', sqlerrm; end;
--     select * into r from public.gv_cuarentena_comentar('lk','<clave>','x',null,'t','Vivi');
--     raise notice 'con persona: %', r.persona;
--     raise exception 'ROLLBACK DE PRUEBA';
--   end $$;
