-- =====================================================================================
-- v17.53 (Luis, 2026-09-14) — la clave única se normaliza AL ESCRIBIR, y la base lo exige.
--
-- PEDIDO: *"fijate que no haya más pedidos duplicados en el log — arreglá el problema que
-- lo causaba"*.
--
-- QUÉ FALTABA. La v17.50 normalizó la clave **en la lectura** (`gv_cuarentena_clave`), así
-- que el log dejó de mostrar duplicados. Pero eso tapa el síntoma: las dos formas del mismo
-- pedido de ISIS —`np98587` desde "A Programar", donde la NP se disfraza de pedido con
-- `order_id = 'np' + np`, y `98587` desde la lista de ya programados— **se seguían
-- escribiendo**. Medido antes de esto: `GV_Cuarentena_Log` tenía **32 claves distintas para
-- 26 pedidos** (6 con prefijo) y `GV_Cuarentena_Liberados` 2 más. Cada vez que alguien
-- abriera una pantalla, la deuda crecía.
--
-- QUÉ SE HIZO, en tres capas — porque con una sola esto vuelve:
--
--   1. **Las 5 RPC que escriben normalizan la clave**: `gv_cuarentena_marcar`,
--      `_log_registrar`, `_liberar`, `_devolver` y `_comentar`. De acá en adelante sólo se
--      guarda la forma canónica (sin el prefijo `np`).
--      · `marcar` y `log_registrar` además **deduplican el payload** (`distinct on` por
--        empresa + clave normalizada): si en UNA misma llamada llegaran las dos formas, el
--        `left join lateral` que decide si hay novedad no ve la fila que se está insertando
--        en esa misma pasada y escribiría dos eventos `entro`. Verificado: antes del
--        `distinct on` esa llamada escribía 2 filas, después escribe 1.
--      · `devolver` compara normalizado al borrar de `GV_Cuarentena_Liberados`, si no una
--        fila vieja con prefijo no se borraba y el pedido quedaba aprobado para siempre.
--
--   2. **Un CHECK en las tres tablas** (`gv_cuar_*_clave_canonica`) que rechaza la forma
--      vieja. Esto es lo que convierte "arreglado" en "no puede volver a pasar": si mañana
--      aparece otra puerta de entrada —otra RPC, un script, un cron— **falla en el insert**
--      en vez de duplicar en silencio. Probado: un `insert` con `np99999` es rechazado.
--
--   3. **Un centinela**, `gv_cuarentena_claves_sueltas`, para mirarlo de un vistazo:
--      `select * from public.gv_cuarentena_claves_sueltas;` — vacío = todo bien.
--
-- MIGRACIÓN DE LO YA ESCRITO (autorizada por Luis, 2026-09-14). Las 8 filas que quedaban
-- con la forma vieja (6 en `GV_Cuarentena_Log`, 2 en `GV_Cuarentena_Liberados`, 0 en
-- `_Comentarios`) se pasaron a la clave canónica. **Backup previo** en
-- `zz_backups."GV_Backup_Cuarentena_Log_20260914"` (36 filas) y
-- `zz_backups."GV_Backup_Cuarentena_Liberados_20260914"` (10 filas) — la tabla entera, no
-- sólo lo tocado. Antes de migrar se verificó que ninguna clave canónica ya existiera junto
-- a su prefijada (chocaría con la PK `(empresa, order_id)` de Liberados): 0 casos.
-- Recién con las filas migradas se pudieron **validar** los tres CHECK, que hasta entonces
-- eran `NOT VALID` (sólo para lo nuevo).
--
-- MEDICIÓN FINAL: `gv_cuarentena_claves_sueltas` **vacío**; log 26 pedidos y **0 repetidos**;
-- filas intactas (36 y 10 — sólo cambió el valor de la clave, no se borró ni se creó nada).
-- Auditadas las otras dos vías posibles de duplicado, las dos en 0: una misma clave con dos
-- empresas, y una misma NP mostrada en dos filas.
--
-- ROLLBACK: `alter table ... drop constraint gv_cuar_*_clave_canonica` (los tres),
-- `drop view public.gv_cuarentena_claves_sueltas`, sacar `gv_cuarentena_clave(...)` de las 5
-- RPC, y para los datos restaurar desde las dos tablas de `zz_backups` por `id` / `(empresa,
-- order_id)`. La normalización de LECTURA (v17.50, `sql/gv_cuarentena_identidad_v1750.sql`)
-- es independiente y puede quedarse: con ella puesta, revertir esto no vuelve a mostrar
-- duplicados, sólo los vuelve a escribir.
-- =====================================================================================

-- ── 1) las 5 RPC que escriben ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.gv_cuarentena_marcar(p_pedidos jsonb)
 RETURNS TABLE(order_id text, empresa text, motivos text[], deuda numeric, estado text, nuevo_pedidos integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.53 (Luis): la clave se normaliza AL ESCRIBIR (gv_cuarentena_clave), no solo al leer.
begin
  -- v17.23 (pedido de Luis, 2026-09-14): el cálculo se mudó tal cual a gv_cuarentena_marcar_calc
  -- y acá sólo se le suma el REGISTRO en GV_Cuarentena_Log, para que el submódulo de Config.
  -- Cuarentena pueda contar cuándo entró cada pedido y con qué motivos. Se escribe sólo cuando
  -- hay novedad (primera vez, re-entrada después de aprobado/devuelto, o cambio de motivos):
  -- esta función la llama el front en CADA carga de A Programar.
  create temp table _calc on commit drop as
    select * from public.gv_cuarentena_marcar_calc(p_pedidos);

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, deuda)
  select c.empresa, public.gv_cuarentena_clave(c.order_id), c.np, c.cod, c.razon_social,
         case when u.evento is null or u.evento in ('aprobado','devuelto') then 'entro' else 'motivos' end,
         c.motivos, c.deuda
    from (select distinct on (c0.empresa, public.gv_cuarentena_clave(c0.order_id)) c0.*
            from _calc c0
           order by c0.empresa, public.gv_cuarentena_clave(c0.order_id), c0.np nulls last) c
    left join lateral (
      select l.evento, l.motivos from public."GV_Cuarentena_Log" l
       where l.empresa = c.empresa and l.clave = public.gv_cuarentena_clave(c.order_id)
       order by l.at desc, l.id desc limit 1) u on true
   where u.evento is null
      or u.evento in ('aprobado','devuelto')
      or u.motivos is distinct from c.motivos;

  return query select c.order_id, c.empresa, c.motivos, c.deuda, c.estado, c.nuevo_pedidos from _calc c;
end;
$function$;

CREATE OR REPLACE FUNCTION public.gv_cuarentena_log_registrar(p_filas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.53 (Luis): la clave se normaliza AL ESCRIBIR (gv_cuarentena_clave), no solo al leer.
declare v_n integer := 0;
begin
  -- v17.23 (pedido de Luis) — registra en el log los pedidos que están retenidos pero NO pasan
  -- por gv_cuarentena_marcar: los que YA tienen tanda (la lista "Ya programados y el cliente está
  -- en cuarentena"). Sin esto, el log sólo vería la aprobación, sin saber cuándo había entrado.
  -- Mismo criterio de novedad que marcar: primera vez, re-entrada, o cambio de motivos.
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor.' using errcode='42501';
  end if;
  with f as (
    select distinct on (lower(coalesce(e->>'empresa','lk')),
                        public.gv_cuarentena_clave(nullif(btrim(e->>'clave'),'')))
           lower(coalesce(e->>'empresa','lk')) empresa,
           public.gv_cuarentena_clave(nullif(btrim(e->>'clave'),'')) clave,
           nullif(btrim(e->>'np'),'') np,
           nullif(btrim(e->>'cod'),'') cod,
           nullif(btrim(e->>'razon_social'),'') razon_social,
           case when jsonb_typeof(e->'motivos') = 'array'
                then array(select jsonb_array_elements_text(e->'motivos')) end motivos,
           (e->>'deuda')::numeric deuda
      from jsonb_array_elements(coalesce(p_filas,'[]'::jsonb)) e
  ),
  ins as (
    insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, deuda)
    select f.empresa, f.clave, f.np, f.cod, f.razon_social,
           case when u.evento is null or u.evento in ('aprobado','devuelto') then 'entro' else 'motivos' end,
           f.motivos, f.deuda
      from f
      left join lateral (
        select l.evento, l.motivos from public."GV_Cuarentena_Log" l
         where l.empresa = f.empresa and l.clave = f.clave
         order by l.at desc, l.id desc limit 1) u on true
     where f.clave is not null
       and (u.evento is null or u.evento in ('aprobado','devuelto') or u.motivos is distinct from f.motivos)
    returning 1)
  select count(*)::int into v_n from ins;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.gv_cuarentena_liberar(p_empresa text, p_order_id text, p_motivos text[] DEFAULT NULL::text[], p_comentario text DEFAULT NULL::text, p_por text DEFAULT NULL::text, p_persona text DEFAULT NULL::text, p_np text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.53 (Luis): la clave se normaliza AL ESCRIBIR (gv_cuarentena_clave), no solo al leer.
declare
  v_quien text; v_persona text; v_clave text := public.gv_cuarentena_clave(nullif(trim(p_order_id),''));
  v_np text; v_cod text; v_rs text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede liberar pedidos de cuarentena.' using errcode='42501';
  end if;
  -- v17.23 (pedido de Luis): además del usuario logueado se guarda QUIÉN aprobó (Vivi, Marian, o
  -- lo que hayan escrito en "Otro"). Las dos cosas: `por` es trazabilidad técnica (el mail de la
  -- sesión) y `persona` es la respuesta a "¿quién lo autorizó?", que es lo que se mira después.
  v_quien   := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  v_persona := nullif(btrim(p_persona),'');
  if v_persona is null then
    raise exception 'Falta indicar quién aprueba el pedido.' using errcode='22023';
  end if;

  insert into public."GV_Cuarentena_Liberados" (empresa, order_id, motivos, liberado_por, persona)
  values (lower(p_empresa), v_clave, p_motivos, coalesce(v_quien,''), v_persona)
  on conflict (empresa, order_id) do update
     set motivos = excluded.motivos, liberado_at = now(),
         liberado_por = excluded.liberado_por, persona = excluded.persona;

  -- el comentario de la aprobación es una línea más del mismo log del pedido
  if coalesce(btrim(p_comentario),'') <> '' then
    insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
    values (lower(p_empresa), v_clave, nullif(btrim(p_np),''), btrim(p_comentario), v_quien, v_persona);
  end if;

  select l.np, l.cod, l.razon_social into v_np, v_cod, v_rs
    from public."GV_Cuarentena_Log" l
   where l.empresa = lower(p_empresa) and l.clave = v_clave
   order by l.at desc, l.id desc limit 1;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
  values (lower(p_empresa), v_clave, coalesce(nullif(btrim(p_np),''), v_np), v_cod, v_rs,
          'aprobado', p_motivos, v_persona, v_quien, nullif(btrim(p_comentario),''));
end;
$function$;

CREATE OR REPLACE FUNCTION public.gv_cuarentena_devolver(p_empresa text, p_np text, p_clave text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text, p_por text DEFAULT NULL::text, p_persona text DEFAULT NULL::text)
 RETURNS TABLE(np_sacadas integer, detalle text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.53 (Luis): la clave se normaliza AL ESCRIBIR (gv_cuarentena_clave), no solo al leer.
declare
  v_np text := btrim(coalesce(p_np,''));
  v_clave text := public.gv_cuarentena_clave(nullif(btrim(coalesce(p_clave, p_np, '')), ''));
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
  -- v17.38 (Luis): devolver también deja una línea en el log, así que también lleva identidad.
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
   where lb.empresa = lower(p_empresa) and public.gv_cuarentena_clave(lb.order_id) = v_clave;

  insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
  values (lower(p_empresa), v_clave, v_np,
          '↩ Vuelto a Cuarentena (sacado de la programación)' ||
          coalesce(': ' || nullif(btrim(p_comentario),''), '.'), v_quien, v_persona);

  select l.cod, l.razon_social into v_cod, v_rs
    from public."GV_Cuarentena_Log" l
   where l.empresa = lower(p_empresa) and public.gv_cuarentena_clave(l.clave) = v_clave
   order by l.at desc, l.id desc limit 1;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, persona, por, comentario)
  values (lower(p_empresa), v_clave, v_np, v_cod, v_rs, 'devuelto', v_persona, v_quien,
          nullif(btrim(p_comentario),''));

  return query select coalesce(v_n,0), coalesce(v_det, v_np);
end;
$function$;

CREATE OR REPLACE FUNCTION public.gv_cuarentena_comentar(p_empresa text, p_order_id text, p_texto text, p_np text DEFAULT NULL::text, p_por text DEFAULT NULL::text, p_persona text DEFAULT NULL::text)
 RETURNS TABLE(id bigint, creado_at timestamp with time zone, persona text, por text, texto text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.53 (Luis): la clave se normaliza AL ESCRIBIR (gv_cuarentena_clave), no solo al leer.
declare v_persona text; v_quien text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede comentar en cuarentena.' using errcode='42501';
  end if;
  if coalesce(btrim(p_texto),'') = '' then
    raise exception 'El comentario no puede estar vacío.' using errcode='22023';
  end if;
  -- v17.38 (Luis, 2026-09-14): "para alguien que deja un comentario, siempre tiene que estar
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
  values (lower(p_empresa), public.gv_cuarentena_clave(nullif(btrim(p_order_id),'')), nullif(btrim(p_np),''), btrim(p_texto),
          v_quien, v_persona)
  returning "GV_Cuarentena_Comentarios".id, "GV_Cuarentena_Comentarios".creado_at,
            "GV_Cuarentena_Comentarios".persona, "GV_Cuarentena_Comentarios".por,
            "GV_Cuarentena_Comentarios".texto;
end;
$function$;

-- ── 2) el candado: que la base no acepte más la forma vieja ──────────────────────────
-- Se crean NOT VALID y se validan DESPUÉS de migrar (paso 4). Sin esto, el arreglo depende
-- de que toda escritura futura pase por las 5 RPC de arriba — y eso no se puede prometer.
alter table public."GV_Cuarentena_Log"
  add constraint gv_cuar_log_clave_canonica check (clave !~ '^np[0-9]+$') not valid;
alter table public."GV_Cuarentena_Liberados"
  add constraint gv_cuar_lib_clave_canonica check (order_id !~ '^np[0-9]+$') not valid;
alter table public."GV_Cuarentena_Comentarios"
  add constraint gv_cuar_com_clave_canonica check (order_id !~ '^np[0-9]+$') not valid;

-- ── 3) el centinela ──────────────────────────────────────────────────────────────────
create or replace view public.gv_cuarentena_claves_sueltas
with (security_invoker = true) as
  select 'GV_Cuarentena_Log' as tabla, l.empresa, l.clave,
         public.gv_cuarentena_clave(l.clave) as canonica, count(*)::int as filas
    from public."GV_Cuarentena_Log" l where l.clave ~ '^np[0-9]+$'
   group by 1,2,3,4
  union all
  select 'GV_Cuarentena_Liberados', b.empresa, b.order_id,
         public.gv_cuarentena_clave(b.order_id), count(*)::int
    from public."GV_Cuarentena_Liberados" b where b.order_id ~ '^np[0-9]+$'
   group by 1,2,3,4
  union all
  select 'GV_Cuarentena_Comentarios', c.empresa, c.order_id,
         public.gv_cuarentena_clave(c.order_id), count(*)::int
    from public."GV_Cuarentena_Comentarios" c where c.order_id ~ '^np[0-9]+$'
   group by 1,2,3,4;

revoke all on public.gv_cuarentena_claves_sueltas from anon;
grant select on public.gv_cuarentena_claves_sueltas to authenticated, service_role;

-- ── 4) migración de lo ya escrito (autorizada por Luis) ──────────────────────────────
-- BACKUP PRIMERO — la tabla entera, no sólo lo que se toca:
--   create table zz_backups."GV_Backup_Cuarentena_Log_20260914" as
--     select * from public."GV_Cuarentena_Log";
--   create table zz_backups."GV_Backup_Cuarentena_Liberados_20260914" as
--     select * from public."GV_Cuarentena_Liberados";
--   alter table zz_backups."GV_Backup_Cuarentena_Log_20260914" enable row level security;
--   alter table zz_backups."GV_Backup_Cuarentena_Liberados_20260914" enable row level security;
--   revoke insert, update, delete, truncate on zz_backups."GV_Backup_Cuarentena_Log_20260914"
--     from anon, authenticated;
--   revoke insert, update, delete, truncate on zz_backups."GV_Backup_Cuarentena_Liberados_20260914"
--     from anon, authenticated;
--
-- Y CHEQUEAR que ninguna canónica ya exista junto a su prefijada (la PK de Liberados es
-- (empresa, order_id), así que chocaría):
--   select b.empresa, b.order_id,
--          exists (select 1 from public."GV_Cuarentena_Liberados" x
--                   where x.empresa = b.empresa
--                     and x.order_id = public.gv_cuarentena_clave(b.order_id)) ya_existe
--     from public."GV_Cuarentena_Liberados" b where b.order_id ~ '^np[0-9]+$';
--   -- 2026-09-14: 2 filas, las dos en ya_existe = false.
begin;
update public."GV_Cuarentena_Log" set clave = public.gv_cuarentena_clave(clave)
 where clave ~ '^np[0-9]+$';
update public."GV_Cuarentena_Liberados" set order_id = public.gv_cuarentena_clave(order_id)
 where order_id ~ '^np[0-9]+$';
update public."GV_Cuarentena_Comentarios" set order_id = public.gv_cuarentena_clave(order_id)
 where order_id ~ '^np[0-9]+$';
alter table public."GV_Cuarentena_Log"          validate constraint gv_cuar_log_clave_canonica;
alter table public."GV_Cuarentena_Liberados"    validate constraint gv_cuar_lib_clave_canonica;
alter table public."GV_Cuarentena_Comentarios"  validate constraint gv_cuar_com_clave_canonica;
commit;

-- ── verificación ─────────────────────────────────────────────────────────────────────
select (select count(*) from public.gv_cuarentena_claves_sueltas) sueltas,          -- 0
       (select count(*) from public."GV_Cuarentena_Log") log_filas,                 -- 36, intactas
       (select count(*) from public."GV_Cuarentena_Liberados") lib_filas,           -- 10, intactas
       (select count(*) from public.gv_cuarentena_log(365)) pedidos,                -- 26
       (select count(*) - count(distinct (empresa, clave))
          from public.gv_cuarentena_log(365)) repetidos;                            -- 0

-- las otras dos vías posibles de duplicado, las dos en 0
select 'misma clave, dos empresas' chequeo, count(*) casos from (
  select clave from public."GV_Cuarentena_Log" group by clave having count(distinct empresa) > 1) x
union all
select 'misma NP mostrada, dos filas', count(*) from (
  select empresa, np from public.gv_cuarentena_log(365)
   where np is not null group by empresa, np having count(*) > 1) y;
