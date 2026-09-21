-- ═══════════════════════════════════════════════════════════════════════════════════════
-- PIPELINE DE CLIENTES NUEVOS · v20.65 (2026-09-21, pedido de Luis)
--
-- ⚠ Este archivo es la definición VIVA, volcada de la base con pg_get_functiondef /
--   pg_get_viewdef después de aplicarla y probarla. No es "lo que se quiso escribir".
--
-- Luis, textual: *"Una persona/empresa se contacta con nosotros y nos dice que quiere ser
-- cliente … Entra el pedido, entra en la PPP y queda con el flag de cliente nuevo … se le
-- tiene que hacer un analisis crediticio … el analisis se le presenta a la direccion y define
-- que se hace con el cliente"*.
--
-- QUÉ ES: una PESTAÑA NUEVA del módulo PPP (🧭 Pipeline clientes) que lleva cada pedido de
-- cliente nuevo por sus etapas, con el reloj de cada paso y el log de todo lo que pasó:
--
--   ingresado → [🔎 Análisis Cred.] abre Equifax y arranca el reloj
--     → analisis → la dirección define: Referenciado · Válido · No válido
--         · Referenciado → cuenta como habitual, se le da crédito → Aprobar y programar
--           (Thomas, 21/09: es una condición del CLIENTE — *"clientes que no requerimos ni
--            para el primer pedido, ni para el segundo, ni para el tercero, que paguen de
--            manera anticipada"*: un cliente muy grande, un amigo de la empresa, o el que
--            compra por una razón social nueva de un cliente ya activo, como Hirohiro. Por eso
--            el evento exime al cliente entero, no sólo al pedido que está en pantalla.)
--         · Válido       → Speech 1 (pagar por adelantado) → Speech 2 (24 h) → Pagó → Aprobar
--         · No válido    → se descarta el pedido
--
-- ⚠ CONVIVE CON EL SUBMÓDULO 🆕 Clientes nuevos, y el VIEJO SIGUE SIENDO EL PRINCIPAL
--   (Luis, 21/09: *"De momento convive y el viejo sigue siendo el principal que se usa.
--   Cuando verifiquemos que el nuevo va, cambiamos"*). Ése es el riesgo entero de que
--   convivan: si cada uno tuviera su propia verdad, alguien aprueba de un lado y el otro
--   sigue mostrando el pedido. Por eso el pipeline NO tiene camino propio para nada que ya
--   existiera:
--     · aprobar llama a `gv_cuarentena_liberar`, la MISMA función del submódulo viejo;
--     · el Speech 1 sella `GV_Clientes_Nuevos_Contacto`, que es de donde el viejo saca su
--       timer — si no, los dos mostrarían tiempos distintos del mismo pedido;
--     · todos los eventos y comentarios van al MISMO log (`GV_Cuarentena_Log`, prefijo
--       `pipeline_`), así Config. Cuarentena sigue siendo el único lugar donde se lee la
--       historia de un pedido.
--   Lo sostiene `tests/pipe-clientes-nuevos.cjs`, con el candado invertido incluido.
--
-- LA ETAPA NO SE GUARDA: SE DERIVA de los timestamps (`gv_clin_etapa`). Una columna `etapa`
-- escrita a mano se desincroniza de los hechos el día que una escritura falla a la mitad, y
-- después nadie sabe cuál de las dos miente. Los hechos son las fechas; la etapa las lee.
--
-- EL VÍNCULO NO TOCA NINGUNA FUNCIÓN VIVA. Medido el 21/09 sobre la definición viva de
-- `gv_cuarentena_marcar_calc`: su CTE `exc` ya filtra TODOS los motivos con
-- `gv_cuarentena_exento(emp, cod, motivo)`, `cliente_nuevo` incluido. Alcanza con insertar la
-- excepción en `gv_excepcion_cuarentena` — mecanismo que ya existe y ya está probado
-- (v19.16/v19.17). Cero `CREATE OR REPLACE` sobre la marcación.
--
-- ⚠ EL VÍNCULO NO DESTRABA EL PEDIDO EN CURSO, a propósito. Cambia la antigüedad del CLIENTE
--   hacia adelante (sus próximos pedidos dejan de caer acá). El pedido que está en pantalla
--   sigue su camino hasta que una persona lo apruebe: el pop-up del vínculo aparece cuando ya
--   se decidió Referenciado/Válido, así que destrabarlo de arriba sería aprobarlo dos veces.
--
-- PROBADO CORRIÉNDOLO, no leyéndolo (21/09):
--   · el flujo entero sobre un pedido de prueba: analisis → valido → speech1 → speech2 →
--     pagado devolvió las 5 etapas en orden y terminó en `pagado`. Borrado después.
--   · el vínculo, sobre un cliente REAL (LK 4281 Biaggio Valentin → LK 45 Distribuidora
--     Cuyana), midiendo `gv_cuarentena_marcar_calc` en los tres momentos:
--         antes        → {cliente_nuevo}, 1 fila
--         vinculado    → 0 filas  ← deja de retener
--         desvinculado → {cliente_nuevo}, 1 fila
--     y revertido en el mismo paso (vínculo, excepción y log borrados).
--
-- LO QUE HAY QUE PEDIRLE A LK (no se resuelve acá): `gv_clientes_nuevos_calc` de LK cuenta la
-- antigüedad con `customer_grupos` + `clientes_lk_ch_links`, que viven allá. Mientras el
-- vínculo no llegue a esas tablas, LK va a seguir empujando al cliente en `GV_Clientes_Nuevos`;
-- lo que lo mantiene fuera del retén es la excepción local. Queda en el Planify de Luis.
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1. El estado del pipeline, un pedido por fila ──────────────────────────────────────
-- Guarda HECHOS (timestamps), nunca la etapa: la etapa la deriva gv_clin_etapa.
create table if not exists public."GV_Cliente_Nuevo_Pipeline" (
  empresa            text not null,
  order_id           text not null,          -- clave canónica (gv_cuarentena_clave)
  np                 text,
  cod                text,
  razon_social       text,
  analisis_at        timestamptz,            -- se apretó «Análisis Cred.» → arranca el reloj
  analisis_por       text,
  decision           text,                   -- referenciado | valido | no_valido
  decision_at        timestamptz,
  decision_por       text,
  decision_persona   text,                   -- quién de la dirección lo definió
  speech1_at         timestamptz,
  speech1_por        text,
  speech2_at         timestamptz,
  speech2_por        text,
  pagado_at          timestamptz,            -- el Válido pagó por adelantado
  pagado_por         text,
  pagado_persona     text,
  cerrado_at         timestamptz,            -- cancelado desde el pipeline
  cerrado_motivo     text,
  creado_at          timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  primary key (empresa, order_id),
  constraint gv_clin_decision_valida
    check (decision is null or decision in ('referenciado','valido','no_valido')),
  constraint gv_clin_clave_canonica check (order_id !~ '^np[0-9]+$')
);
alter table public."GV_Cliente_Nuevo_Pipeline" enable row level security;
revoke insert, update, delete, truncate on public."GV_Cliente_Nuevo_Pipeline" from anon, authenticated;

-- ── 2. El vínculo de antigüedad con una razón social que YA es cliente ─────────────────
create table if not exists public."GV_Cliente_Vinculo" (
  empresa            text not null,          -- el cliente NUEVO
  cod                text not null,
  razon_social       text,
  vinc_empresa       text not null,          -- el cliente VIEJO al que se lo vincula
  vinc_cod           text not null,
  vinc_razon_social  text,
  vinc_cuit          text,
  order_id           text,                   -- desde qué pedido se vinculó
  nota               text,
  por                text,
  persona            text,
  activo             boolean not null default true,
  creado_at          timestamptz not null default now(),
  actualizado_at     timestamptz not null default now(),
  primary key (empresa, cod),
  constraint gv_clin_vinc_no_mismo check (not (empresa = vinc_empresa and cod = vinc_cod))
);
alter table public."GV_Cliente_Vinculo" enable row level security;
revoke insert, update, delete, truncate on public."GV_Cliente_Vinculo" from anon, authenticated;

-- ── 3. Config: los relojes y la URL de Equifax, sin deploy ─────────────────────────────
-- Para cambiarlas es un update, no un deploy:
--   update public."PPP_Web_Config" set valor = 48 where clave = 'clin_speech_horas';
--   update public."PPP_Web_Config" set valor_texto = '<url>' where clave = 'clin_equifax_url';
insert into public."PPP_Web_Config" (clave, valor, valor_texto, descripcion)
select * from (values
  ('clin_speech_horas',   24, null::text,
   'Horas que puede estar un Speech sin respuesta antes de que el pipeline lo marque vencido (Luis, 21/09: 24 h).'),
  ('clin_analisis_horas', 24, null::text,
   'Horas que puede estar abierto el analisis crediticio sin decision antes de marcarse vencido.'),
  ('clin_prioridad_dias',  2, null::text,
   'Dias habiles como maximo para programar un pedido de cliente nuevo ya aprobado (Luis, 21/09).'),
  ('clin_equifax_url',  null, 'https://www.equifax.com.ar/',
   'A donde abre el boton «Analisis Cred.». Si la URL trae {cuit} se le pega el CUIT del cliente.')
) v(clave, valor, valor_texto, descripcion)
where not exists (select 1 from public."PPP_Web_Config" c where c.clave = v.clave);

-- ── 3.b El CHECK de `origen` de gv_excepcion_cuarentena acepta un valor más ────────────
-- Sólo aceptaba 'super' y 'manual', así que el vínculo no podía dejar su marca propia — y sin
-- marca propia, desvincular pisaría las excepciones que puso una persona a mano.
-- Se AGREGA un valor: las 25 filas que había siguen siendo válidas.
-- Backup previo: zz_backups."GV_Backup_excepcion_cuarentena_20260921" (25 filas).
alter table public.gv_excepcion_cuarentena drop constraint if exists gv_excepcion_cuarentena_origen_check;
alter table public.gv_excepcion_cuarentena add  constraint gv_excepcion_cuarentena_origen_check
  check (origen = any (array['super','manual','vinculo','referenciado']));

-- ── 4. La ETAPA y su RELOJ, derivados de los hechos ────────────────────────────────────
-- El orden de los `when` ES la regla: lo cerrado gana sobre lo abierto, y dentro de la rama
-- «valido» gana el paso más avanzado.
CREATE OR REPLACE FUNCTION public.gv_clin_etapa(p_analisis_at timestamp with time zone, p_decision text, p_speech1_at timestamp with time zone, p_speech2_at timestamp with time zone, p_pagado_at timestamp with time zone, p_cerrado_at timestamp with time zone, p_aprobado boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select case
    when coalesce(p_aprobado, false) then 'aprobado'
    when p_cerrado_at is not null then 'cancelado'
    when p_decision = 'no_valido' then 'no_valido'
    when p_decision = 'referenciado' then 'referenciado'
    when p_decision = 'valido' and p_pagado_at  is not null then 'pagado'
    when p_decision = 'valido' and p_speech2_at is not null then 'speech2'
    when p_decision = 'valido' and p_speech1_at is not null then 'speech1'
    when p_decision = 'valido' then 'valido'
    when p_analisis_at is not null then 'analisis'
    else 'ingresado' end;
$function$;

-- Desde cuándo corre el reloj de la etapa actual (null = no hay reloj corriendo).
CREATE OR REPLACE FUNCTION public.gv_clin_reloj(p_etapa text, p_analisis_at timestamp with time zone, p_speech1_at timestamp with time zone, p_speech2_at timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select case p_etapa when 'analisis' then p_analisis_at
                      when 'speech1'  then p_speech1_at
                      when 'speech2'  then p_speech2_at else null end;
$function$;

-- ── 5. Lectura: el estado de un lote de pedidos ────────────────────────────────────────
-- Un pedido sin fila devuelve 'ingresado' igual: el pipeline los muestra a todos.
-- ⚠ Los coalesce de config van casteados a ::int — `PPP_Web_Config.valor` es numeric y
--   `make_interval(hours => numeric)` NO existe. El CREATE sale limpio y explota al ejecutarse.
CREATE OR REPLACE FUNCTION public.gv_clin_pipeline_lote(p_pedidos jsonb)
 RETURNS TABLE(empresa text, order_id text, etapa text, reloj_desde timestamp with time zone, vencido boolean, decision text, decision_persona text, decision_at timestamp with time zone, analisis_at timestamp with time zone, speech1_at timestamp with time zone, speech2_at timestamp with time zone, pagado_at timestamp with time zone, cerrado_at timestamp with time zone, cerrado_motivo text, aprobado boolean, vinc_empresa text, vinc_cod text, vinc_razon_social text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with cfg as (
    select coalesce((select valor from public."PPP_Web_Config" where clave='clin_speech_horas'), 24)::int   as h_speech,
           coalesce((select valor from public."PPP_Web_Config" where clave='clin_analisis_horas'), 24)::int as h_analisis),
  ped as (
    select lower(coalesce(e->>'empresa','lk')) as empresa,
           public.gv_cuarentena_clave(nullif(btrim(e->>'order_id'),'')) as order_id,
           nullif(btrim(e->>'cod'),'') as cod
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
  eta as (
    select f.*, public.gv_clin_etapa(f.analisis_at, f.decision, f.speech1_at,
                                     f.speech2_at, f.pagado_at, f.cerrado_at, f.aprobado) as etapa
      from fila f)
  select e.empresa, e.order_id, e.etapa,
         public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at),
         case when public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at) is null then false
              else now() - public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at)
                   > make_interval(hours => case when e.etapa='analisis' then c.h_analisis else c.h_speech end) end,
         e.decision, e.decision_persona, e.decision_at,
         e.analisis_at, e.speech1_at, e.speech2_at, e.pagado_at, e.cerrado_at, e.cerrado_motivo,
         e.aprobado, v.vinc_empresa, v.vinc_cod, v.vinc_razon_social
    from eta e cross join cfg c
    left join public."GV_Cliente_Vinculo" v
      on v.activo and v.empresa = e.empresa
     and v.cod = regexp_replace(btrim(coalesce(e.cod,'')), '\.0+$', '');
$function$;

-- ── 6. Escritura: UNA sola puerta para todos los pasos ─────────────────────────────────
-- Cada evento escribe su hecho, deja su línea en el log de Cuarentena y devuelve el estado
-- nuevo. ⚠ `speech1` sella también GV_Clientes_Nuevos_Contacto (el timer del submódulo viejo).
CREATE OR REPLACE FUNCTION public.gv_clin_evento(p_empresa text, p_order_id text, p_evento text, p_persona text DEFAULT NULL::text, p_por text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text, p_np text DEFAULT NULL::text, p_cod text DEFAULT NULL::text, p_razon_social text DEFAULT NULL::text)
 RETURNS TABLE(etapa text, reloj_desde timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_emp   text := public.gv_emp_norm(p_empresa);
  v_clave text := public.gv_cuarentena_clave(nullif(btrim(p_order_id), ''));
  v_quien text := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')), '');
  v_pers  text := nullif(btrim(p_persona), '');
  v_ev    text := nullif(btrim(lower(p_evento)), '');
  v_cod   text := regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '');
  v_apro  boolean;
  r       public."GV_Cliente_Nuevo_Pipeline"%rowtype;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede mover el pipeline de clientes nuevos.' using errcode='42501';
  end if;
  if v_clave is null then raise exception 'Falta el pedido.' using errcode='22023'; end if;
  if v_ev is null or v_ev not in ('analisis','referenciado','valido','no_valido','speech1','speech2','pagado','cancelado','reabrir') then
    raise exception 'Evento desconocido: %', coalesce(v_ev,'(vacío)') using errcode='22023';
  end if;
  if v_ev in ('referenciado','valido','no_valido','pagado','cancelado') and v_pers is null then
    raise exception 'Falta indicar quién lo decide.' using errcode='22023';
  end if;

  insert into public."GV_Cliente_Nuevo_Pipeline" (empresa, order_id, np, cod, razon_social)
  values (v_emp, v_clave, nullif(btrim(p_np),''), nullif(v_cod,''), nullif(btrim(p_razon_social),''))
  on conflict (empresa, order_id) do update
     set np           = coalesce(excluded.np, "GV_Cliente_Nuevo_Pipeline".np),
         cod          = coalesce(excluded.cod, "GV_Cliente_Nuevo_Pipeline".cod),
         razon_social = coalesce(excluded.razon_social, "GV_Cliente_Nuevo_Pipeline".razon_social);

  update public."GV_Cliente_Nuevo_Pipeline" p set
    analisis_at      = case when v_ev='analisis' then coalesce(p.analisis_at, now()) when v_ev='reabrir' then null else p.analisis_at end,
    analisis_por     = case when v_ev='analisis' and p.analisis_at is null then v_quien when v_ev='reabrir' then null else p.analisis_por end,
    decision         = case when v_ev in ('referenciado','valido','no_valido') then v_ev when v_ev='reabrir' then null else p.decision end,
    decision_at      = case when v_ev in ('referenciado','valido','no_valido') then now() when v_ev='reabrir' then null else p.decision_at end,
    decision_por     = case when v_ev in ('referenciado','valido','no_valido') then v_quien when v_ev='reabrir' then null else p.decision_por end,
    decision_persona = case when v_ev in ('referenciado','valido','no_valido') then v_pers when v_ev='reabrir' then null else p.decision_persona end,
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

  -- ⚠ REFERENCIADO ES UNA CONDICION DEL CLIENTE, NO DE ESTE PEDIDO (Thomas, 21/09):
  -- *"clientes que no requerimos ni para el primer pedido, ni para el segundo, ni para el
  -- tercero, que paguen de manera anticipada"*. Asi que se exime al CLIENTE, no solo al pedido
  -- que esta en pantalla: sus proximos pedidos tampoco caen en el pipeline. Mismo mecanismo que
  -- el vinculo, con `origen` propio para poder revertir uno sin tocar el otro.
  if v_ev = 'referenciado' and nullif(v_cod,'') is not null then
    insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, activo, nota, actualizado_por)
    values (v_emp, v_cod, coalesce(nullif(btrim(p_razon_social),''), r.razon_social),
            array['cliente_nuevo'], 'referenciado', true,
            'Cliente REFERENCIADO por ' || v_pers || ' (pedido ' || coalesce(nullif(btrim(p_np),''), v_clave) ||
            '): no paga por adelantado en sus primeros pedidos.', v_quien)
    on conflict (empresa, cod) do update
       set motivos = (select array_agg(distinct x) from unnest(gv_excepcion_cuarentena.motivos || array['cliente_nuevo']) x),
           activo = true, nota = excluded.nota, actualizado_por = excluded.actualizado_por, actualizado_at = now();
  end if;
  -- y al reabrir se saca, o el cliente quedaria referenciado para siempre por un click deshecho
  if v_ev = 'reabrir' and nullif(v_cod,'') is not null then
    update public.gv_excepcion_cuarentena
       set motivos = array_remove(motivos, 'cliente_nuevo'),
           activo = (coalesce(array_length(array_remove(motivos, 'cliente_nuevo'), 1), 0) >= 1),
           actualizado_por = v_quien, actualizado_at = now()
     where empresa = v_emp and cod = v_cod and origen = 'referenciado';
  end if;

  if v_ev = 'speech1' then
    insert into public."GV_Clientes_Nuevos_Contacto" (empresa, order_id, por)
    values (v_emp, v_clave, v_quien) on conflict (empresa, order_id) do nothing;
  end if;

  if coalesce(btrim(p_comentario),'') <> '' and v_ev <> 'cancelado' then
    insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
    values (v_emp, v_clave, nullif(btrim(p_np),''), btrim(p_comentario), v_quien, v_pers);
  end if;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
  values (v_emp, v_clave, coalesce(nullif(btrim(p_np),''), r.np), coalesce(nullif(v_cod,''), r.cod),
          coalesce(nullif(btrim(p_razon_social),''), r.razon_social),
          'pipeline_' || v_ev, array['cliente_nuevo'], v_pers, v_quien, nullif(btrim(p_comentario),''));

  v_apro := exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = v_emp and public.gv_cuarentena_clave(lb.order_id) = v_clave);
  etapa := public.gv_clin_etapa(r.analisis_at, r.decision, r.speech1_at, r.speech2_at, r.pagado_at, r.cerrado_at, v_apro);
  reloj_desde := public.gv_clin_reloj(etapa, r.analisis_at, r.speech1_at, r.speech2_at);
  return next;
end;
$function$;

-- ── 7. El vínculo: buscar una razón social que ya sea cliente ──────────────────────────
-- Busca en las DOS empresas por razón social, CUIT y código: el cliente nuevo puede venir por
-- LK y ser el mismo que ya compra por Chef (y al revés).
-- ⚠ La clave de un cliente es (empresa, cod), nunca `cod` solo: el mismo número es otra
--   persona en la otra empresa (114 de 115 códigos compartidos, medido el 16/09).
-- ⚠ El guard va con un IF de plpgsql, NO colgado del FROM/WHERE de una función SQL: Postgres
--   elimina una subconsulta cuyas columnas no se referencian y el guard nunca se evalúa (es
--   la lección de `gv_es_admin`, que así bloqueaba 0 de 5).
CREATE OR REPLACE FUNCTION public.gv_clin_vinculo_buscar(p_q text, p_limit integer DEFAULT 20)
 RETURNS TABLE(empresa text, cod text, razon_social text, cuit text, es_nuevo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_t text := nullif(btrim(coalesce(p_q,'')), '');
        v_d text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede buscar clientes para vincular.' using errcode='42501';
  end if;
  if v_t is null then return; end if;
  v_d := nullif(regexp_replace(v_t, '\D', '', 'g'), '');
  return query
    select c.empresa, c.cod, c.razon_social, c.cuit,
           exists (select 1 from public."GV_Clientes_Nuevos" cn
                    where cn.empresa = c.empresa and cn.cod = c.cod)
      from public."GV_Cliente_Cuit" c
     where ( c.razon_social ilike '%' || v_t || '%'
          or c.cod = regexp_replace(v_t, '\.0+$', '')
          or (v_d is not null and length(v_d) >= 6
              and regexp_replace(coalesce(c.cuit,''), '\D', '', 'g') like '%' || v_d || '%') )
     order by (exists (select 1 from public."GV_Clientes_Nuevos" cn
                        where cn.empresa = c.empresa and cn.cod = c.cod)),
              (c.razon_social ilike v_t || '%') desc, c.razon_social
     limit greatest(1, least(coalesce(p_limit, 20), 50));
end;
$function$;

-- ── 8. El vínculo: crearlo / sacarlo ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.gv_clin_vincular(p_empresa text, p_cod text, p_vinc_empresa text, p_vinc_cod text, p_persona text DEFAULT NULL::text, p_por text DEFAULT NULL::text, p_order_id text DEFAULT NULL::text, p_nota text DEFAULT NULL::text)
 RETURNS TABLE(vinc_empresa text, vinc_cod text, vinc_razon_social text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_emp   text := public.gv_emp_norm(p_empresa);
  v_cod   text := regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '');
  v_vemp  text := public.gv_emp_norm(p_vinc_empresa);
  v_vcod  text := regexp_replace(btrim(coalesce(p_vinc_cod,'')), '\.0+$', '');
  v_quien text := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')), '');
  v_pers  text := nullif(btrim(p_persona), '');
  v_rs text; v_vrs text; v_vcuit text; v_clave text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede vincular clientes.' using errcode='42501'; end if;
  if v_cod = '' or v_vcod = '' then raise exception 'Faltan los códigos de cliente.' using errcode='22023'; end if;
  if v_pers is null then raise exception 'Falta indicar quién vincula.' using errcode='22023'; end if;
  if v_emp = v_vemp and v_cod = v_vcod then
    raise exception 'No se puede vincular un cliente consigo mismo.' using errcode='22023'; end if;
  if exists (select 1 from public."GV_Clientes_Nuevos" cn where cn.empresa = v_vemp and cn.cod = v_vcod) then
    raise exception 'El cliente elegido también figura como cliente nuevo: vincularlo no le da antigüedad.' using errcode='22023'; end if;

  select c.razon_social into v_rs from public."GV_Cliente_Cuit" c where c.empresa = v_emp and c.cod = v_cod;
  select c.razon_social, c.cuit into v_vrs, v_vcuit from public."GV_Cliente_Cuit" c where c.empresa = v_vemp and c.cod = v_vcod;
  v_clave := public.gv_cuarentena_clave(nullif(btrim(p_order_id),''));

  insert into public."GV_Cliente_Vinculo"
    (empresa, cod, razon_social, vinc_empresa, vinc_cod, vinc_razon_social, vinc_cuit, order_id, nota, por, persona, activo)
  values (v_emp, v_cod, v_rs, v_vemp, v_vcod, v_vrs, v_vcuit, v_clave, nullif(btrim(p_nota),''), v_quien, v_pers, true)
  on conflict (empresa, cod) do update
     set vinc_empresa = excluded.vinc_empresa, vinc_cod = excluded.vinc_cod,
         vinc_razon_social = excluded.vinc_razon_social, vinc_cuit = excluded.vinc_cuit,
         order_id = coalesce(excluded.order_id, "GV_Cliente_Vinculo".order_id),
         nota = excluded.nota, por = excluded.por, persona = excluded.persona,
         activo = true, actualizado_at = now();

  -- Lo que lo hace OPERAR: gv_cuarentena_marcar_calc ya filtra TODOS los motivos por
  -- gv_cuarentena_exento, asi que con esta fila el cliente deja de caer como cliente nuevo.
  insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, activo, nota, actualizado_por)
  values (v_emp, v_cod, v_rs, array['cliente_nuevo'], 'vinculo', true,
          'Vinculado a ' || upper(v_vemp) || ' ' || v_vcod || ' (' || coalesce(v_vrs,'sin razón social') || ') por ' || v_pers, v_quien)
  on conflict (empresa, cod) do update
     set motivos = (select array_agg(distinct x) from unnest(gv_excepcion_cuarentena.motivos || array['cliente_nuevo']) x),
         activo = true, nota = excluded.nota, actualizado_por = excluded.actualizado_por, actualizado_at = now();

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
  values (v_emp, coalesce(v_clave, 'cliente:' || v_cod), null, v_cod, v_rs,
          'pipeline_vinculado', array['cliente_nuevo'], v_pers, v_quien,
          'Vinculado a ' || upper(v_vemp) || ' ' || v_vcod || ' — ' || coalesce(v_vrs, 'sin razón social'));

  vinc_empresa := v_vemp; vinc_cod := v_vcod; vinc_razon_social := v_vrs; return next;
end;
$function$;

-- ⚠ `array_length` de un array vacío devuelve NULL, no 0: sin el coalesce, sacarle el último
--   motivo a una excepción dejaría `activo` en null en vez de false.
CREATE OR REPLACE FUNCTION public.gv_clin_desvincular(p_empresa text, p_cod text, p_persona text DEFAULT NULL::text, p_por text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_emp text := public.gv_emp_norm(p_empresa);
        v_cod text := regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '');
        v_quien text := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')), '');
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede desvincular clientes.' using errcode='42501'; end if;
  update public."GV_Cliente_Vinculo" set activo = false, actualizado_at = now()
   where empresa = v_emp and cod = v_cod;
  -- se saca SÓLO el motivo que puso el vínculo; si la fila tenía otros motivos, quedan
  update public.gv_excepcion_cuarentena
     set motivos = array_remove(motivos, 'cliente_nuevo'),
         activo = (coalesce(array_length(array_remove(motivos, 'cliente_nuevo'), 1), 0) >= 1),
         actualizado_por = v_quien, actualizado_at = now()
   where empresa = v_emp and cod = v_cod and origen = 'vinculo';
  insert into public."GV_Cuarentena_Log" (empresa, clave, cod, evento, motivos, persona, por, comentario)
  values (v_emp, 'cliente:' || v_cod, v_cod, 'pipeline_desvinculado', array['cliente_nuevo'],
          nullif(btrim(p_persona),''), v_quien, 'Vínculo dado de baja');
end;
$function$;

-- ── 9. Qué pedidos tienen que salir YA (la prioridad de Luis) ──────────────────────────
-- Luis, 21/09: el cliente nuevo aprobado se programa dentro de los 2 días hábiles y, si en su
-- zona no hay camión, **se le funda uno**. Esta vista es el insumo: dice cuáles están en esa
-- condición y hasta cuándo. `via` dice por dónde llegó (referenciado, o válido ya pagado).
create or replace view public.gv_clin_prioritarios with (security_invoker = true) as
 WITH cfg AS (
         SELECT COALESCE(( SELECT "PPP_Web_Config".valor
                   FROM "PPP_Web_Config"
                  WHERE "PPP_Web_Config".clave = 'clin_prioridad_dias'::text), 2::numeric)::integer AS d
        )
 SELECT p.empresa,
    p.order_id,
    p.np,
    p.cod,
    p.razon_social,
    p.decision AS via,
    COALESCE(p.pagado_at, p.decision_at) AS listo_desde,
    lb.liberado_at,
    ( SELECT max(q.d) AS max
           FROM ( SELECT g.g::date AS d,
                    row_number() OVER (ORDER BY g.g) AS rn
                   FROM generate_series(COALESCE(lb.liberado_at, now())::date::timestamp with time zone, (COALESCE(lb.liberado_at, now())::date + 20)::timestamp with time zone, '1 day'::interval) g(g)
                  WHERE gv_es_dia_habil(g.g::date)) q,
            cfg
          WHERE q.rn <= cfg.d) AS salir_antes_de
   FROM "GV_Cliente_Nuevo_Pipeline" p
     JOIN "GV_Cuarentena_Liberados" lb ON lb.empresa = p.empresa AND gv_cuarentena_clave(lb.order_id) = p.order_id
  WHERE p.cerrado_at IS NULL AND (p.decision = ANY (ARRAY['referenciado'::text, 'valido'::text])) AND (p.decision = 'referenciado'::text OR p.pagado_at IS NOT NULL);

-- ── 10. Centinela: lo que está esperando hace demasiado ────────────────────────────────
-- vacía = todo bien. Es lo que alimenta el badge rojo de la pestaña. ⚠ El pedido NO se
-- cancela solo (Luis, 21/09: *"No se cancela solo pero sale un badge en la pestaña"*): no hay
-- ni un cron tocando esto, y el test lo verifica.
create or replace view public.gv_clin_vencidos with (security_invoker = true) as
 WITH cfg AS (
         SELECT COALESCE(( SELECT "PPP_Web_Config".valor
                   FROM "PPP_Web_Config"
                  WHERE "PPP_Web_Config".clave = 'clin_speech_horas'::text), 24::numeric)::integer AS h_speech,
            COALESCE(( SELECT "PPP_Web_Config".valor
                   FROM "PPP_Web_Config"
                  WHERE "PPP_Web_Config".clave = 'clin_analisis_horas'::text), 24::numeric)::integer AS h_analisis
        ), eta AS (
         SELECT p.empresa, p.order_id, p.np, p.cod, p.razon_social,
            p.analisis_at, p.analisis_por, p.decision, p.decision_at, p.decision_por, p.decision_persona,
            p.speech1_at, p.speech1_por, p.speech2_at, p.speech2_por,
            p.pagado_at, p.pagado_por, p.pagado_persona, p.cerrado_at, p.cerrado_motivo,
            p.creado_at, p.updated_at,
            gv_clin_etapa(p.analisis_at, p.decision, p.speech1_at, p.speech2_at, p.pagado_at, p.cerrado_at, (EXISTS ( SELECT 1
                   FROM "GV_Cuarentena_Liberados" lb
                  WHERE lb.empresa = p.empresa AND gv_cuarentena_clave(lb.order_id) = p.order_id))) AS etapa
           FROM "GV_Cliente_Nuevo_Pipeline" p
        )
 SELECT e.empresa, e.order_id, e.np, e.cod, e.razon_social, e.etapa,
    gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at) AS espera_desde,
    round(EXTRACT(epoch FROM now() - gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at)) / 3600.0, 1) AS horas,
        CASE e.etapa
            WHEN 'analisis'::text THEN c.h_analisis
            ELSE c.h_speech
        END AS tope_horas
   FROM eta e
     CROSS JOIN cfg c
  WHERE (e.etapa = ANY (ARRAY['analisis'::text, 'speech1'::text, 'speech2'::text])) AND gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at) < (now() - make_interval(hours =>
        CASE
            WHEN e.etapa = 'analisis'::text THEN c.h_analisis
            ELSE c.h_speech
        END));

-- ⚠ Se REAFIRMAN las opciones aunque el CREATE ya las traiga: un `create or replace view` sin
--   `WITH (...)` las resetea a null sin decir nada, y una vista sin security_invoker corre
--   como postgres y saltea la RLS (la filtración que costó caro el 2026-09-04).
alter view public.gv_clin_prioritarios set (security_invoker = true);
alter view public.gv_clin_vencidos     set (security_invoker = true);

-- ── 11. Permisos ───────────────────────────────────────────────────────────────────────
-- Las vistas son security_invoker y las tablas tienen RLS sin policy: `anon` no ve nada
-- directo. Todo pasa por las RPC, que llevan el guard de supervisor adentro — el MISMO que
-- usa `gv_cuarentena_liberar` en producción.
revoke all on public.gv_clin_prioritarios from anon, authenticated;
revoke all on public.gv_clin_vencidos     from anon, authenticated;
grant execute on function public.gv_clin_pipeline_lote(jsonb)                                 to anon, authenticated;
grant execute on function public.gv_clin_evento(text,text,text,text,text,text,text,text,text)  to anon, authenticated;
grant execute on function public.gv_clin_vinculo_buscar(text,int)                             to anon, authenticated;
grant execute on function public.gv_clin_vincular(text,text,text,text,text,text,text,text)     to anon, authenticated;
grant execute on function public.gv_clin_desvincular(text,text,text,text)                     to anon, authenticated;

-- ── 12. Centinelas de las reglas que no se pueden perder ───────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_clin_evento', 'funcion', 'GV_Clientes_Nuevos_Contacto',
   'El Speech 1 del pipeline sella tambien el timer del submodulo viejo: mientras convivan, los dos cuentan lo mismo.',
   'Luis', 'v20.65'),
  ('gv_clin_vincular', 'funcion', 'gv_excepcion_cuarentena',
   'El vinculo opera escribiendo la excepcion de cuarentena; sin eso el pop-up es decorativo y el proximo pedido vuelve a caer.',
   'Luis', 'v20.65'),
  ('gv_clin_vincular', 'funcion', 'GV_Clientes_Nuevos',
   'No se puede vincular a otro cliente nuevo: heredar de alguien sin antiguedad es heredar cero.',
   'Luis', 'v20.65')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c
                   where c.objeto = v.objeto and c.patron = v.patron);

-- ── CHEQUEOS ───────────────────────────────────────────────────────────────────────────
--   select * from public.gv_reglas_perdidas;    -- vacía = ninguna regla se perdió
--   select * from public.gv_clin_vencidos;      -- lo que espera hace demasiado (badge rojo)
--   select * from public.gv_clin_prioritarios;  -- lo aprobado que tiene que salir en 2 días
--   select empresa, cod, vinc_empresa, vinc_cod, activo from public."GV_Cliente_Vinculo";
--   -- y la pregunta que importa: ¿el vínculo saca al cliente del retén?
--   select motivos from public.gv_cuarentena_marcar_calc(
--     '[{"order_id":"<pedido>","empresa":"lk","cod":"<cod>"}]'::jsonb);
--
-- ROLLBACK (el log no se borra: es la historia de los pedidos):
--   drop view if exists public.gv_clin_vencidos, public.gv_clin_prioritarios;
--   drop function if exists public.gv_clin_evento(text,text,text,text,text,text,text,text,text);
--   drop function if exists public.gv_clin_pipeline_lote(jsonb);
--   drop function if exists public.gv_clin_vincular(text,text,text,text,text,text,text,text);
--   drop function if exists public.gv_clin_desvincular(text,text,text,text);
--   drop function if exists public.gv_clin_vinculo_buscar(text,int);
--   drop function if exists public.gv_clin_etapa(timestamptz,text,timestamptz,timestamptz,timestamptz,timestamptz,boolean);
--   drop function if exists public.gv_clin_reloj(text,timestamptz,timestamptz,timestamptz);
--   -- las excepciones que puso el vínculo (los clientes vuelven a caer como nuevos):
--   update public.gv_excepcion_cuarentena set activo = false where origen in ('vinculo','referenciado');
--   -- y el CHECK, si se quisiera volver atrás del todo:
--   -- alter table public.gv_excepcion_cuarentena drop constraint gv_excepcion_cuarentena_origen_check;
--   -- alter table public.gv_excepcion_cuarentena add  constraint gv_excepcion_cuarentena_origen_check
--   --   check (origen = any (array['super','manual']));
