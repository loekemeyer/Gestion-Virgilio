-- ============================================================================================
-- v20.86 (Luis, 2026-09-21) — EL PIPELINE DE CLIENTES NUEVOS REEMPLAZA AL SUBMODULO VIEJO
-- ============================================================================================
-- Definiciones de Luis, textuales:
--   1. "cuarentena toma prioridad sobre cliente nuevo (ej, un cliente nuevo con deuda pasa
--      primero por la cuarentena y despues cuando es liberado con «Enviar a Pedidos a
--      programar» va al modulo de clientes nuevos"
--   2. "Deberia poder sacar los telefonos de la tabla mas completa que tengamos en supa"
--   3. "Agregale zona"
--   4. "Despues del analisis solo hay 2 estados que un cliente puede tener: Referenciado y
--      No referenciado. No referenciado se le requiere que pague los primeros 3 pedidos por
--      adelantado y el pipeline contempla todos los casos ahi"
--   5. "La verificacion no se vuelve a hacer... lo unico que queda definir es el contacto por
--      speech. Deberian quedar registrados los «Coment.» a modo de log historico. Si un cliente
--      vuelve a entrar en el modulo de clientes nuevos, deberia traer todo el log anterior"
--
-- Y el corte de salida ya estaba hecho y NO se toca: "despues de que pasan 3 pedidos bien
-- pagando por adelantado ya se considera un cliente normal". `GV_Clientes_Nuevos` solo trae
-- clientes con 1 o 2 pedidos FACTURADOS (medido: 269 con 1, 80 con 2, ninguno con 3), asi que
-- al tercero el cliente sale del reten solo. Un pedido cancelado por no pagar no se factura,
-- de modo que no suma — el contador ya hace exactamente lo que pidio Luis.
--
-- ⚠ NO se migro nada: al aplicar esto, `GV_Cliente_Nuevo_Pipeline` tenia UNA fila y era el
--   cliente de prueba (`__DEMO__`, sin decision). Cero pedidos reales decididos.
-- ⚠ `gv_cuarentena_marcar_calc` LA TOCAN VARIAS SESIONES: mientras se escribia esto, otra
--   sesion la piso y borro este cambio (aparecio su CTE `mismo` de la v20.52). Por eso el
--   bloque de abajo se aplica SOBRE LA DEFINICION VIVA, es idempotente, y las cinco reglas
--   tienen su fila en GV_Reglas_Centinela: si vuelve a pasar, `gv_reglas_perdidas` lo canta.
-- ============================================================================================

-- ── 1. DOS ESTADOS ──────────────────────────────────────────────────────────────────────────
-- backup antes de tocar (protocolo): zz_backups."GV_Backup_ClienteNuevoPipeline_20260921"
alter table public."GV_Cliente_Nuevo_Pipeline" drop constraint if exists gv_clin_decision_valida;
update public."GV_Cliente_Nuevo_Pipeline" set decision = 'no_referenciado' where decision = 'valido';
update public."GV_Cliente_Nuevo_Pipeline" set decision = null, decision_at = null,
       decision_por = null, decision_persona = null where decision = 'no_valido';
alter table public."GV_Cliente_Nuevo_Pipeline" add constraint gv_clin_decision_valida
  check (decision is null or decision = any (array['referenciado','no_referenciado']));

-- La etapa NO se guarda: se DERIVA de los timestamps. Una columna `etapa` escrita a mano se
-- desincroniza el dia que una escritura falla a la mitad, y despues nadie sabe cual miente.
-- El orden de los `when` ES la regla de negocio.
create or replace function public.gv_clin_etapa(
  p_analisis_at timestamptz, p_decision text, p_speech1_at timestamptz,
  p_speech2_at timestamptz, p_pagado_at timestamptz, p_cerrado_at timestamptz,
  p_aprobado boolean default false)
returns text language sql immutable parallel safe as $function$
  select case
    when coalesce(p_aprobado, false) then 'aprobado'
    when p_cerrado_at is not null then 'cancelado'
    when p_decision = 'referenciado' then 'referenciado'
    when p_decision = 'no_referenciado' and p_pagado_at  is not null then 'pagado'
    when p_decision = 'no_referenciado' and p_speech2_at is not null then 'speech2'
    when p_decision = 'no_referenciado' and p_speech1_at is not null then 'speech1'
    when p_decision = 'no_referenciado' then 'no_referenciado'
    when p_analisis_at is not null then 'analisis'
    else 'ingresado' end;
$function$;

-- ── 2. EL LOG ES DEL CLIENTE, NO SOLO DEL PEDIDO ────────────────────────────────────────────
-- backup: zz_backups."GV_Backup_CuarentenaComentarios_20260921"
alter table public."GV_Cuarentena_Comentarios" add column if not exists cod text;
-- backfill: el codigo sale del log del mismo pedido (medido: 70 de 71 recuperables)
update public."GV_Cuarentena_Comentarios" c set cod = l.cod
  from (select distinct on (empresa, clave) empresa, clave, cod
          from public."GV_Cuarentena_Log" where cod is not null
         order by empresa, clave, at desc) l
 where c.cod is null and l.empresa = c.empresa and l.clave = c.order_id;

create or replace function public.gv_clin_comentarios_cliente(
  p_empresa text, p_cod text, p_order_id text default null)
returns table(id bigint, empresa text, order_id text, np text, texto text, por text,
              persona text, creado_at timestamptz, es_este_pedido boolean)
language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select c.id, c.empresa, c.order_id, c.np, c.texto, c.por, c.persona, c.creado_at,
         (public.gv_cuarentena_clave(c.order_id)
            = public.gv_cuarentena_clave(nullif(btrim(p_order_id),''))) as es_este_pedido
    from public."GV_Cuarentena_Comentarios" c
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
     and c.empresa = public.gv_emp_norm(p_empresa)
     and regexp_replace(btrim(coalesce(c.cod,'')),'\.0+$','')
         = regexp_replace(btrim(coalesce(p_cod,'')),'\.0+$','')
     and nullif(btrim(coalesce(p_cod,'')),'') is not null
   order by c.creado_at desc, c.id desc;
$function$;
revoke execute on function public.gv_clin_comentarios_cliente(text,text,text) from public, anon;
grant execute on function public.gv_clin_comentarios_cliente(text,text,text) to authenticated, service_role;

-- ── 3. EL TELEFONO SE BUSCA POR (empresa, cod), NUNCA POR CODIGO SOLO ───────────────────────
-- Medido el 21/09: el Excel del dueno (08/09) YA esta dentro de `whatsapp_clientes` — de los
-- 332 codigos compartidos, 0 tienen telefono distinto, y las dos cargas se escribieron con 12
-- segundos de diferencia. Pero 26 filas del dueno nunca llegaron: son 13 codigos que existen
-- en LK y en CH a la vez, y esa tabla no tiene empresa, asi que se descartaron LOS DOS lados.
-- Los 13 son OTRO cliente y OTRO telefono en cada empresa. Y 257 codigos del padron estan en
-- las dos empresas: para ellos `whatsapp_clientes` no puede decidir nada.
--   GV_Clientes_Whatsapp por (empresa, cod)  -> la unica con empresa. MANDA.
--   whatsapp_clientes por cod                -> solo si el codigo NO existe en las dos.
drop function if exists public.gv_cliente_nuevo_wpp_lote(jsonb);
create function public.gv_cliente_nuevo_wpp_lote(p_pedidos jsonb)
returns table(empresa text, cod text, telefono text, origen text)
language sql stable security definer set search_path to 'public','pg_temp' as $function$
  with i as (
    select distinct lower(coalesce(e->>'empresa','lk')) empresa,
           regexp_replace(nullif(btrim(e->>'cod'),''),'\.0+$','') cod
      from jsonb_array_elements(coalesce(p_pedidos,'[]'::jsonb)) e
     where nullif(btrim(e->>'cod'),'') is not null),
  amb as (
    select i.cod from i
     where exists (select 1 from public."GV_Clientes_Direcciones" d
                    where lower(d.empresa)='lk'
                      and regexp_replace(btrim(d.cod),'\.0+$','') = i.cod)
       and exists (select 1 from public."GV_Clientes_Direcciones" d
                    where lower(d.empresa)='chef'
                      and regexp_replace(btrim(d.cod),'\.0+$','') = i.cod))
  select i.empresa, i.cod,
         coalesce(g.telefono, w.telefono) as telefono,
         case when g.telefono is not null then 'padron_empresa'
              when w.telefono is not null then 'historico'
              when i.cod in (select cod from amb) then 'ambiguo_sin_dato'
              else 'sin_dato' end as origen
    from i
    left join lateral (
      select nullif(btrim(x.telefono),'') telefono from public."GV_Clientes_Whatsapp" x
       where lower(x.empresa) = case when i.empresa='chef' then 'ch' else 'lk' end
         and regexp_replace(btrim(x.cod_cliente),'\.0+$','') = i.cod
         and nullif(btrim(x.telefono),'') is not null limit 1) g on true
    left join lateral (
      select nullif(btrim(y.telefono),'') telefono from public.whatsapp_clientes y
       where regexp_replace(btrim(y.cod_cliente),'\.0+$','') = i.cod
         and nullif(btrim(y.telefono),'') is not null
         and i.cod not in (select cod from amb) limit 1) w on true
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio());
$function$;
revoke execute on function public.gv_cliente_nuevo_wpp_lote(jsonb) from public, anon;
grant execute on function public.gv_cliente_nuevo_wpp_lote(jsonb) to authenticated, service_role;
-- chequeo: el codigo 94 tiene que dar DOS telefonos distintos, uno por empresa
--   select * from public.gv_cliente_nuevo_wpp_lote(
--     '[{"empresa":"lk","cod":"94"},{"empresa":"chef","cod":"94"}]'::jsonb);

-- ── 4. CUARENTENA PRIMERO ───────────────────────────────────────────────────────────────────
-- Se edita SOBRE LA DEFINICION VIVA a proposito (varias sesiones tocan esta funcion) y es
-- idempotente: si ya tiene la regla, no hace nada.
do $$
declare v_def text; v_a text; v_b text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='gv_cuarentena_marcar_calc';
  if position('cliente_nuevo'' = any (lb.motivos)' in v_def) > 0 then
    raise notice 'ya tiene la regla, no se toca'; return;
  end if;

  v_a := '  select e.order_id, e.empresa, e.cod, e.np, e.razon_social, e.motivos_ok,
         case when ''deuda'' = any (e.motivos_ok) then e.deuda end,
         case when e.motivos_ok && array[''suspendido'',''sin_cta_cte''] then e.estado end,
         case when ''cliente_nuevo'' = any (e.motivos_ok) then e.nuevo_pedidos end
  from exc e
  where array_length(e.motivos_ok, 1) >= 1';
  v_b := '  -- ⚠ v20.86 (Luis, 21/09): CUARENTENA PRIMERO. Liberar ya no levanta el candado entero:
  -- se restan SOLO los motivos que esa liberacion resolvio. Si se libero la deuda y el cliente
  -- sigue siendo nuevo, el pedido sale con `cliente_nuevo` solo y cae en el pipeline.
  -- `motivos` en NULL o en ARRAY VACIO = liberacion vieja, sin detalle: libera todo (medido:
  -- el pedido 1368 tiene ''{}'' y sin este guard volvia al reten).
  select e.order_id, e.empresa, e.cod, e.np, e.razon_social, e.motivos_vivos,
         case when ''deuda'' = any (e.motivos_vivos) then e.deuda end,
         case when e.motivos_vivos && array[''suspendido'',''sin_cta_cte''] then e.estado end,
         case when ''cliente_nuevo'' = any (e.motivos_vivos) then e.nuevo_pedidos end
  from (select x.*, coalesce(
                 (select array_agg(m order by m) from unnest(x.motivos_ok) m
                   where lbm.motivos is null or coalesce(array_length(lbm.motivos,1),0) = 0
                      or m <> all (lbm.motivos)),
                 array[]::text[]) as motivos_vivos
          from exc x
          left join lateral (
            select lb.motivos from public."GV_Cuarentena_Liberados" lb
             where lb.empresa = x.empresa
               and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(x.order_id)
             limit 1) lbm on true) e
  where array_length(e.motivos_vivos, 1) >= 1';
  if position(v_a in v_def) = 0 then
    raise exception 'marcar_calc: el select final no matchea — la definicion viva cambio';
  end if;
  v_def := replace(v_def, v_a, v_b);

  v_a := '    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = e.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(e.order_id));';
  v_b := '    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = e.empresa
                       and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(e.order_id)
                       and (lb.motivos is null or coalesce(array_length(lb.motivos,1),0) = 0
                            or ''cliente_nuevo'' <> all (e.motivos_vivos)
                            or ''cliente_nuevo'' = any (lb.motivos)));';
  if position(v_a in v_def) = 0 then
    raise exception 'marcar_calc: el filtro de liberados no matchea';
  end if;
  execute replace(v_def, v_a, v_b);
end $$;

-- ── 5. LOS CENTINELAS ───────────────────────────────────────────────────────────────────────
--   select * from public.gv_reglas_perdidas;   -- vacia = ninguna regla se perdio
-- (las 5 filas de GV_Reglas_Centinela estan cargadas: motivos_vivos, el guard del array vacio,
--  no_referenciado, GV_Clientes_Whatsapp y decision_ef)

-- ── 6. EL EVENTO: dos estados, y el comentario lleva el COD ─────────────────────────────────
-- (cuerpo completo; reemplaza al de sql/gv_clin_pipeline_v2066.sql)
create or replace function public.gv_clin_evento(p_empresa text, p_order_id text, p_evento text,
  p_persona text default null, p_por text default null, p_comentario text default null,
  p_np text default null, p_cod text default null, p_razon_social text default null)
returns table(etapa text, reloj_desde timestamptz)
language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare
  v_emp   text := public.gv_emp_norm(p_empresa);
  v_clave text := public.gv_cuarentena_clave(nullif(btrim(p_order_id), ''));
  v_quien text := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')), '');
  v_pers  text := nullif(btrim(p_persona), '');
  v_ev    text := nullif(btrim(lower(p_evento)), '');
  v_cod   text := regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '');
  v_apro  boolean;
  v_demo  boolean;
  r       public."GV_Cliente_Nuevo_Pipeline"%rowtype;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede mover el pipeline de clientes nuevos.' using errcode='42501';
  end if;
  if v_clave is null then raise exception 'Falta el pedido.' using errcode='22023'; end if;
  -- ⚠ v20.86 (Luis): DESPUES DEL ANALISIS SOLO HAY DOS ESTADOS — referenciado / no_referenciado.
  -- 'valido' y 'no_valido' ya no existen: al que no se le quiere vender se le elimina el pedido.
  if v_ev is null or v_ev not in ('analisis','referenciado','no_referenciado','speech1','speech2','pagado','cancelado','reabrir') then
    raise exception 'Evento desconocido: %', coalesce(v_ev,'(vacío)') using errcode='22023';
  end if;
  if v_ev in ('referenciado','no_referenciado','pagado','cancelado') and v_pers is null then
    raise exception 'Falta indicar quién lo decide.' using errcode='22023';
  end if;

  -- ⚠ EL PEDIDO DE EJEMPLO avanza por las etapas como cualquiera, pero no toca NADA de afuera.
  v_demo := v_clave like '\_\_DEMO%';

  insert into public."GV_Cliente_Nuevo_Pipeline" (empresa, order_id, np, cod, razon_social)
  values (v_emp, v_clave, nullif(btrim(p_np),''), nullif(v_cod,''), nullif(btrim(p_razon_social),''))
  on conflict (empresa, order_id) do update
     set np           = coalesce(excluded.np, "GV_Cliente_Nuevo_Pipeline".np),
         cod          = coalesce(excluded.cod, "GV_Cliente_Nuevo_Pipeline".cod),
         razon_social = coalesce(excluded.razon_social, "GV_Cliente_Nuevo_Pipeline".razon_social);

  update public."GV_Cliente_Nuevo_Pipeline" p set
    analisis_at      = case when v_ev='analisis' then coalesce(p.analisis_at, now()) when v_ev='reabrir' then null else p.analisis_at end,
    analisis_por     = case when v_ev='analisis' and p.analisis_at is null then v_quien when v_ev='reabrir' then null else p.analisis_por end,
    decision         = case when v_ev in ('referenciado','no_referenciado') then v_ev when v_ev='reabrir' then null else p.decision end,
    decision_at      = case when v_ev in ('referenciado','no_referenciado') then now() when v_ev='reabrir' then null else p.decision_at end,
    decision_por     = case when v_ev in ('referenciado','no_referenciado') then v_quien when v_ev='reabrir' then null else p.decision_por end,
    decision_persona = case when v_ev in ('referenciado','no_referenciado') then v_pers when v_ev='reabrir' then null else p.decision_persona end,
    speech1_at       = case when v_ev='speech1' then coalesce(p.speech1_at, now()) when v_ev='reabrir' then null else p.speech1_at end,
    speech1_por      = case when v_ev='speech1' and p.speech1_at is null then v_quien when v_ev='reabrir' then null else p.speech1_por end,
    speech2_at       = case when v_ev='speech2' then coalesce(p.speech2_at, now()) when v_ev='reabrir' then null else p.speech2_at end,
    speech2_por      = case when v_ev='speech2' and p.speech2_at is null then v_quien when v_ev='reabrir' then null else p.speech2_por end,
    pagado_at        = case when v_ev='pagado' then now() when v_ev='reabrir' then null else p.pagado_at end,
    pagado_por       = case when v_ev='pagado' then v_quien when v_ev='reabrir' then null else p.pagado_por end,
    pagado_persona   = case when v_ev='pagado' then v_pers when v_ev='reabrir' then null else p.pagado_persona end,
    cerrado_at       = case when v_ev='cancelado' then now() when v_ev='reabrir' then null else p.cerrado_at end,
    cerrado_motivo   = case when v_ev='cancelado' then coalesce(nullif(btrim(p_comentario),''),'cancelado desde el pipeline') when v_ev='reabrir' then null else p.cerrado_motivo end,
    updated_at       = now()
  where p.empresa = v_emp and p.order_id = v_clave
  returning * into r;

  -- ⚠ REFERENCIADO ES UNA CONDICION DEL CLIENTE, NO DE ESTE PEDIDO (Thomas, 21/09).
  if v_ev = 'referenciado' and nullif(v_cod,'') is not null and not v_demo then
    insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, activo, nota, actualizado_por)
    values (v_emp, v_cod, coalesce(nullif(btrim(p_razon_social),''), r.razon_social),
            array['cliente_nuevo'], 'referenciado', true,
            'Cliente REFERENCIADO por ' || v_pers || ' (pedido ' || coalesce(nullif(btrim(p_np),''), v_clave) ||
            '): no paga por adelantado en sus primeros pedidos.', v_quien)
    on conflict (empresa, cod) do update
       set motivos = (select array_agg(distinct x) from unnest(gv_excepcion_cuarentena.motivos || array['cliente_nuevo']) x),
           activo = true, nota = excluded.nota, actualizado_por = excluded.actualizado_por, actualizado_at = now();
  end if;
  -- ⚠ v20.86: pasar a NO REFERENCIADO le SACA la excepcion si la tenia (cambio de opinion):
  -- el no referenciado paga por adelantado, asi que no puede quedar eximido del reten.
  if v_ev in ('reabrir','no_referenciado') and nullif(v_cod,'') is not null and not v_demo then
    update public.gv_excepcion_cuarentena
       set motivos = array_remove(motivos, 'cliente_nuevo'),
           activo = (coalesce(array_length(array_remove(motivos, 'cliente_nuevo'), 1), 0) >= 1),
           actualizado_por = v_quien, actualizado_at = now()
     where empresa = v_emp and cod = v_cod and origen = 'referenciado';
  end if;

  if v_ev = 'speech1' and not v_demo then
    insert into public."GV_Clientes_Nuevos_Contacto" (empresa, order_id, por)
    values (v_emp, v_clave, v_quien) on conflict (empresa, order_id) do nothing;
  end if;

  -- v20.86: el comentario lleva el COD, para poder leer el historial del CLIENTE
  if coalesce(btrim(p_comentario),'') <> '' and v_ev <> 'cancelado' and not v_demo then
    insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona, cod)
    values (v_emp, v_clave, nullif(btrim(p_np),''), btrim(p_comentario), v_quien, v_pers,
            coalesce(nullif(v_cod,''), r.cod));
  end if;

  if not v_demo then
    insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
    values (v_emp, v_clave, coalesce(nullif(btrim(p_np),''), r.np), coalesce(nullif(v_cod,''), r.cod),
            coalesce(nullif(btrim(p_razon_social),''), r.razon_social),
            'pipeline_' || v_ev, array['cliente_nuevo'], v_pers, v_quien, nullif(btrim(p_comentario),''));
  end if;

  v_apro := (not v_demo) and exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = v_emp and public.gv_cuarentena_clave(lb.order_id) = v_clave);
  etapa := public.gv_clin_etapa(r.analisis_at, r.decision, r.speech1_at, r.speech2_at, r.pagado_at, r.cerrado_at, v_apro);
  reloj_desde := public.gv_clin_reloj(etapa, r.analisis_at, r.speech1_at, r.speech2_at);
  return next;
end;
$function$;

-- ── 7. EL LOTE: la DECISION se hereda del CLIENTE ───────────────────────────────────────────
-- Luis: "la verificacion no se vuelve a hacer... lo unico que queda definir es el contacto por
-- speech". Se hereda el ESTADO, no los timestamps: el pedido nuevo arranca con su speech1_at
-- en null, o sea pidiendo el Speech 1 y el pago por adelantado de ESE pedido.
-- ⚠ cambia el tipo de retorno (agrega `decision_heredada`) -> DROP obligatorio
--   ("cannot change return type of existing function").
drop function if exists public.gv_clin_pipeline_lote(jsonb);
create function public.gv_clin_pipeline_lote(p_pedidos jsonb)
returns table(empresa text, order_id text, etapa text, reloj_desde timestamptz, vencido boolean,
  decision text, decision_persona text, decision_at timestamptz, analisis_at timestamptz,
  speech1_at timestamptz, speech2_at timestamptz, pagado_at timestamptz, cerrado_at timestamptz,
  cerrado_motivo text, aprobado boolean, vinc_empresa text, vinc_cod text, vinc_razon_social text,
  cli_analisis_at timestamptz, cli_analisis_np text, cli_decision text, cli_decision_at timestamptz,
  cli_decision_persona text, cli_decision_np text, analisis_heredado boolean,
  decision_heredada boolean)
language sql stable security definer set search_path to 'public','pg_temp' as $function$
  with cfg as (
    select coalesce((select valor from public."PPP_Web_Config" where clave='clin_speech_horas'), 24)::int   as h_speech,
           coalesce((select valor from public."PPP_Web_Config" where clave='clin_analisis_horas'), 24)::int as h_analisis),
  ped as (
    select lower(coalesce(e->>'empresa','lk')) as empresa,
           public.gv_cuarentena_clave(nullif(btrim(e->>'order_id'),'')) as order_id,
           regexp_replace(btrim(coalesce(e->>'cod','')), '\.0+$', '') as cod
      from jsonb_array_elements(coalesce(p_pedidos,'[]'::jsonb)) e
     where nullif(btrim(e->>'order_id'),'') is not null),
  fila as (
    select p.empresa, p.order_id, p.cod, t.*,
           exists (select 1 from public."GV_Cuarentena_Liberados" lb
                    where lb.empresa = p.empresa
                      and public.gv_cuarentena_clave(lb.order_id) = p.order_id) as aprobado
      from ped p
      left join lateral (
        select x.analisis_at, x.decision, x.decision_at, x.decision_persona,
               x.speech1_at, x.speech2_at, x.pagado_at, x.cerrado_at, x.cerrado_motivo
          from public."GV_Cliente_Nuevo_Pipeline" x
         where x.empresa = p.empresa and x.order_id = p.order_id) t on true),
  hist as (
    select f.*,
           ha.analisis_at as cli_analisis_at, ha.np as cli_analisis_np,
           hd.decision as cli_decision, hd.decision_at as cli_decision_at,
           hd.decision_persona as cli_decision_persona, hd.np as cli_decision_np
      from fila f
      left join lateral (
        select y.analisis_at, y.np from public."GV_Cliente_Nuevo_Pipeline" y
         where y.empresa = f.empresa
           and regexp_replace(btrim(coalesce(y.cod,'')), '\.0+$','') = f.cod
           and y.order_id <> f.order_id and y.analisis_at is not null
         order by y.analisis_at desc limit 1) ha on true
      left join lateral (
        select y.decision, y.decision_at, y.decision_persona, y.np
          from public."GV_Cliente_Nuevo_Pipeline" y
         where y.empresa = f.empresa
           and regexp_replace(btrim(coalesce(y.cod,'')), '\.0+$','') = f.cod
           and y.order_id <> f.order_id and y.decision is not null
         order by y.decision_at desc limit 1) hd on true),
  eta as (
    select h.*, coalesce(h.analisis_at, h.cli_analisis_at) as analisis_ef,
           coalesce(h.decision, h.cli_decision)            as decision_ef,
           (h.analisis_at is null and h.cli_analisis_at is not null) as heredado,
           (h.decision is null and h.cli_decision is not null)       as dec_heredada
      from hist h),
  eta2 as (
    select e.*, public.gv_clin_etapa(e.analisis_ef, e.decision_ef, e.speech1_at,
                                     e.speech2_at, e.pagado_at, e.cerrado_at, e.aprobado) as etapa
      from eta e)
  select e.empresa, e.order_id, e.etapa,
         public.gv_clin_reloj(e.etapa, e.analisis_ef, e.speech1_at, e.speech2_at),
         case when public.gv_clin_reloj(e.etapa, e.analisis_ef, e.speech1_at, e.speech2_at) is null then false
              when e.heredado and e.etapa = 'analisis' then false
              else now() - public.gv_clin_reloj(e.etapa, e.analisis_ef, e.speech1_at, e.speech2_at)
                   > make_interval(hours => case when e.etapa='analisis' then c.h_analisis else c.h_speech end) end,
         e.decision_ef,
         coalesce(e.decision_persona, case when e.dec_heredada then e.cli_decision_persona end),
         coalesce(e.decision_at, case when e.dec_heredada then e.cli_decision_at end),
         e.analisis_ef, e.speech1_at, e.speech2_at, e.pagado_at, e.cerrado_at, e.cerrado_motivo,
         e.aprobado, v.vinc_empresa, v.vinc_cod, v.vinc_razon_social,
         e.cli_analisis_at, e.cli_analisis_np,
         e.cli_decision, e.cli_decision_at, e.cli_decision_persona, e.cli_decision_np,
         e.heredado, e.dec_heredada
    from eta2 e cross join cfg c
    left join public."GV_Cliente_Vinculo" v
      on v.activo and v.empresa = e.empresa and v.cod = e.cod;
$function$;
revoke execute on function public.gv_clin_pipeline_lote(jsonb) from public, anon;
grant execute on function public.gv_clin_pipeline_lote(jsonb) to authenticated, service_role;

-- ── LAS PRUEBAS QUE SE CORRIERON (no leer el codigo: correrlo) ──────────────────────────────
-- a) la herencia, en transaccion abortada: el 2do pedido del mismo cliente arranca en
--    `no_referenciado` con decision_heredada=true, analisis_heredado=true y vencido=false.
-- b) cuarentena primero, con el cliente 4173 (nuevo + deuda de $496.128):
--      sin liberar            -> retenido {cliente_nuevo,deuda}
--      liberado SOLO deuda    -> retenido {cliente_nuevo}          <- cae en el pipeline
--      liberado por los dos   -> SALE DEL RETEN (0 filas)
-- c) no-regresion: de los 38 ya liberados, 2 vuelven al reten con {cliente_nuevo} — 98585 y
--    98586, que se liberaron solo por deuda y siguen siendo cliente nuevo. LOS DOS YA ESTAN
--    PROGRAMADOS, asi que no estan en la lista de pendientes de A Programar: cero impacto visible.
