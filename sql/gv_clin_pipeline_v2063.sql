-- ═══════════════════════════════════════════════════════════════════════════════════════
-- PIPELINE DE CLIENTES NUEVOS · v20.63 (2026-09-21, pedido de Luis)
--
-- Luis, textual: *"Una persona/empresa se contacta con nosotros y nos dice que quiere ser
-- cliente … Entra el pedido, entra en la PPP y queda con el flag de cliente nuevo … se le
-- tiene que hacer un analisis crediticio … el analisis se le presenta a la direccion y define
-- que se hace con el cliente"*.
--
-- QUÉ ES: una PESTAÑA NUEVA del módulo PPP (🧭 Pipeline clientes) que lleva cada pedido de
-- cliente nuevo por sus etapas, con el timer de cada paso y el log de todo lo que pasó.
--
-- ⚠ CONVIVE CON EL SUBMÓDULO 🆕 Clientes nuevos, y el VIEJO SIGUE SIENDO EL PRINCIPAL
--   (Luis, 21/09: *"De momento convive y el viejo sigue siendo el principal que se usa.
--   Cuando verifiquemos que el nuevo va, cambiamos"*). Por eso:
--     · el pipeline NO tiene botón propio de aprobar-a-ciegas: llama a `gv_cuarentena_liberar`,
--       la MISMA función del submódulo viejo, así el pedido sale por un solo camino;
--     · el Speech 1 del pipeline sella TAMBIÉN `GV_Clientes_Nuevos_Contacto`, que es de donde
--       el submódulo viejo saca su timer — si no, los dos mostrarían cosas distintas del mismo
--       pedido, que es el riesgo entero de que convivan;
--     · todos los eventos van al MISMO log (`GV_Cuarentena_Log`), así Config. Cuarentena
--       sigue siendo el único lugar donde se lee la historia de un pedido.
--
-- LA ETAPA NO SE GUARDA: SE DERIVA de los timestamps (`gv_clin_etapa`). Una columna `etapa`
-- escrita a mano se desincroniza de los hechos el día que una escritura falla a la mitad, y
-- después nadie sabe cuál de las dos miente. Los hechos son las fechas; la etapa es una
-- lectura de esas fechas.
--
-- EL VÍNCULO NO TOCA NINGUNA FUNCIÓN VIVA. Medido el 21/09 sobre la definición viva de
-- `gv_cuarentena_marcar_calc`: su CTE `exc` ya filtra TODOS los motivos con
-- `gv_cuarentena_exento(emp, cod, motivo)`, `cliente_nuevo` incluido. Así que alcanza con
-- insertar la excepción en `gv_excepcion_cuarentena` — mecanismo que ya existe y ya está
-- probado (v19.16/v19.17). Cero `CREATE OR REPLACE` sobre la marcación.
--
-- ⚠ EL VÍNCULO NO DESTRABA EL PEDIDO EN CURSO, a propósito. Cambia la antigüedad del CLIENTE
--   hacia adelante (sus próximos pedidos dejan de caer en el pipeline). El pedido que está en
--   la pantalla sigue su camino hasta que una persona lo apruebe: el pop-up del vínculo
--   aparece cuando ya se decidió Referenciado/Válido, o sea que la decisión ya está tomada y
--   destrabarlo de arriba sería aprobarlo dos veces.
--
-- LO QUE HAY QUE PEDIRLE A LK (no se resuelve acá): `gv_clientes_nuevos_calc` de LK cuenta la
-- antigüedad con `customer_grupos` + `clientes_lk_ch_links`, que viven allá. Mientras el
-- vínculo no llegue a esas tablas, LK va a seguir contando al cliente como nuevo y va a
-- seguir empujándolo en `GV_Clientes_Nuevos`; lo que lo mantiene fuera del retén es la
-- excepción local. Queda anotado en el Planify de Luis.
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1. El estado del pipeline, un pedido por fila ──────────────────────────────────────
create table if not exists public."GV_Cliente_Nuevo_Pipeline" (
  empresa            text not null,
  order_id           text not null,          -- clave canónica (gv_cuarentena_clave)
  np                 text,
  cod                text,
  razon_social       text,
  -- los HECHOS, que es lo único que se guarda
  analisis_at        timestamptz,            -- se apretó «Análisis Cred.» → arranca el timer
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
  cerrado_at         timestamptz,            -- pedido cancelado desde el pipeline
  cerrado_motivo     text,
  creado_at          timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  primary key (empresa, order_id),
  constraint gv_clin_decision_valida
    check (decision is null or decision in ('referenciado','valido','no_valido')),
  -- misma clave canónica que el resto del módulo de cuarentena
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

-- ── 3. Config: las horas de cada timer y la URL de Equifax, sin deploy ─────────────────
-- Para cambiarlas: update public."PPP_Web_Config" set valor = 48 where clave = 'clin_speech_horas';
insert into public."PPP_Web_Config" (clave, valor, valor_texto, descripcion)
select * from (values
  ('clin_speech_horas',   24, null::text,
   'Horas que puede estar un Speech sin respuesta antes de que el pipeline lo marque vencido (Luis, 21/09: 24 h).'),
  ('clin_analisis_horas', 24, null::text,
   'Horas que puede estar abierto el analisis crediticio sin decision antes de marcarse vencido.'),
  ('clin_prioridad_dias',  2, null::text,
   'Dias habiles como maximo para programar un pedido de cliente nuevo ya aprobado (Luis, 21/09).'),
  ('clin_equifax_url',  null, 'https://www.equifax.com.ar/',
   'A donde abre el boton «Analisis Cred.». Se le agrega ?cuit=<cuit> si la URL trae {cuit}.')
) v(clave, valor, valor_texto, descripcion)
where not exists (select 1 from public."PPP_Web_Config" c where c.clave = v.clave);

-- ── 4. La ETAPA se deriva de los hechos ────────────────────────────────────────────────
-- El orden de los `when` ES la regla de negocio: lo cerrado gana sobre lo abierto, y dentro
-- de la rama «valido» gana el paso más avanzado.
create or replace function public.gv_clin_etapa(
  p_analisis_at timestamptz, p_decision text, p_speech1_at timestamptz,
  p_speech2_at timestamptz, p_pagado_at timestamptz, p_cerrado_at timestamptz,
  p_aprobado boolean default false)
returns text
language sql immutable parallel safe
as $function$
  select case
    when coalesce(p_aprobado, false)              then 'aprobado'
    when p_cerrado_at is not null                 then 'cancelado'
    when p_decision = 'no_valido'                 then 'no_valido'
    when p_decision = 'referenciado'              then 'referenciado'
    when p_decision = 'valido' and p_pagado_at  is not null then 'pagado'
    when p_decision = 'valido' and p_speech2_at is not null then 'speech2'
    when p_decision = 'valido' and p_speech1_at is not null then 'speech1'
    when p_decision = 'valido'                    then 'valido'
    when p_analisis_at is not null                then 'analisis'
    else 'ingresado'
  end;
$function$;

-- Desde cuándo corre el reloj de la etapa actual (null = no hay reloj corriendo).
create or replace function public.gv_clin_reloj(
  p_etapa text, p_analisis_at timestamptz, p_speech1_at timestamptz, p_speech2_at timestamptz)
returns timestamptz
language sql immutable parallel safe
as $function$
  select case p_etapa
    when 'analisis' then p_analisis_at
    when 'speech1'  then p_speech1_at
    when 'speech2'  then p_speech2_at
    else null end;
$function$;

-- ── 5. Lectura: el estado de un lote de pedidos ────────────────────────────────────────
-- Un pedido que todavía no tiene fila devuelve etapa 'ingresado' igual: el pipeline los
-- muestra a todos, tengan historia o no.
create or replace function public.gv_clin_pipeline_lote(p_pedidos jsonb)
returns table(empresa text, order_id text, etapa text, reloj_desde timestamptz,
              vencido boolean, decision text, decision_persona text, decision_at timestamptz,
              analisis_at timestamptz, speech1_at timestamptz, speech2_at timestamptz,
              pagado_at timestamptz, cerrado_at timestamptz, cerrado_motivo text,
              aprobado boolean, vinc_empresa text, vinc_cod text, vinc_razon_social text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with cfg as (
    select coalesce((select valor from public."PPP_Web_Config" where clave='clin_speech_horas'), 24)   as h_speech,
           coalesce((select valor from public."PPP_Web_Config" where clave='clin_analisis_horas'), 24) as h_analisis
  ),
  ped as (
    select lower(coalesce(e->>'empresa','lk'))                        as empresa,
           public.gv_cuarentena_clave(nullif(btrim(e->>'order_id'),'')) as order_id,
           nullif(btrim(e->>'cod'),'')                                as cod
      from jsonb_array_elements(coalesce(p_pedidos,'[]'::jsonb)) e
     where nullif(btrim(e->>'order_id'),'') is not null
  ),
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
         where x.empresa = p.empresa and x.order_id = p.order_id) t on true
  ),
  eta as (
    select f.*, public.gv_clin_etapa(f.analisis_at, f.decision, f.speech1_at,
                                     f.speech2_at, f.pagado_at, f.cerrado_at, f.aprobado) as etapa
      from fila f
  )
  select e.empresa, e.order_id, e.etapa,
         public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at) as reloj_desde,
         case when public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at) is null
              then false
              else now() - public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at)
                   > make_interval(hours => case when e.etapa = 'analisis' then c.h_analisis else c.h_speech end)
         end as vencido,
         e.decision, e.decision_persona, e.decision_at,
         e.analisis_at, e.speech1_at, e.speech2_at, e.pagado_at, e.cerrado_at, e.cerrado_motivo,
         e.aprobado,
         v.vinc_empresa, v.vinc_cod, v.vinc_razon_social
    from eta e
    cross join cfg c
    left join public."GV_Cliente_Vinculo" v
      on v.activo and v.empresa = e.empresa
     and v.cod = regexp_replace(btrim(coalesce(e.cod,'')), '\.0+$', '');
$function$;

-- ── 6. Escritura: un evento del pipeline ───────────────────────────────────────────────
-- UNA sola puerta para todos los pasos. Cada evento escribe su hecho, deja su línea en el
-- log de Cuarentena y devuelve el estado nuevo, así el front no tiene que recargar todo.
--
-- ⚠ El evento `speech1` sella también GV_Clientes_Nuevos_Contacto (el timer del submódulo
--   viejo). Mientras los dos módulos convivan, tienen que contar el mismo tiempo.
create or replace function public.gv_clin_evento(
  p_empresa text, p_order_id text, p_evento text,
  p_persona text default null, p_por text default null, p_comentario text default null,
  p_np text default null, p_cod text default null, p_razon_social text default null)
returns table(etapa text, reloj_desde timestamptz)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  if v_clave is null then
    raise exception 'Falta el pedido.' using errcode='22023';
  end if;
  if v_ev not in ('analisis','referenciado','valido','no_valido','speech1','speech2','pagado','cancelado','reabrir') then
    raise exception 'Evento desconocido: %', coalesce(v_ev,'(vacío)') using errcode='22023';
  end if;
  -- Las decisiones y el pago los firma una persona; apretar «Análisis Cred.» o un Speech no.
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
    -- el análisis se sella UNA vez: el timer cuenta desde el primer click, no desde el último
    analisis_at      = case when v_ev = 'analisis'  then coalesce(p.analisis_at, now())
                            when v_ev = 'reabrir'   then null else p.analisis_at end,
    analisis_por     = case when v_ev = 'analisis' and p.analisis_at is null then v_quien
                            when v_ev = 'reabrir'   then null else p.analisis_por end,
    decision         = case when v_ev in ('referenciado','valido','no_valido') then v_ev
                            when v_ev = 'reabrir'   then null else p.decision end,
    decision_at      = case when v_ev in ('referenciado','valido','no_valido') then now()
                            when v_ev = 'reabrir'   then null else p.decision_at end,
    decision_por     = case when v_ev in ('referenciado','valido','no_valido') then v_quien
                            when v_ev = 'reabrir'   then null else p.decision_por end,
    decision_persona = case when v_ev in ('referenciado','valido','no_valido') then v_pers
                            when v_ev = 'reabrir'   then null else p.decision_persona end,
    speech1_at       = case when v_ev = 'speech1'   then coalesce(p.speech1_at, now())
                            when v_ev = 'reabrir'   then null else p.speech1_at end,
    speech1_por      = case when v_ev = 'speech1' and p.speech1_at is null then v_quien
                            when v_ev = 'reabrir'   then null else p.speech1_por end,
    speech2_at       = case when v_ev = 'speech2'   then coalesce(p.speech2_at, now())
                            when v_ev = 'reabrir'   then null else p.speech2_at end,
    speech2_por      = case when v_ev = 'speech2' and p.speech2_at is null then v_quien
                            when v_ev = 'reabrir'   then null else p.speech2_por end,
    pagado_at        = case when v_ev = 'pagado'    then now()
                            when v_ev = 'reabrir'   then null else p.pagado_at end,
    pagado_por       = case when v_ev = 'pagado'    then v_quien
                            when v_ev = 'reabrir'   then null else p.pagado_por end,
    pagado_persona   = case when v_ev = 'pagado'    then v_pers
                            when v_ev = 'reabrir'   then null else p.pagado_persona end,
    cerrado_at       = case when v_ev = 'cancelado' then now()
                            when v_ev = 'reabrir'   then null else p.cerrado_at end,
    cerrado_motivo   = case when v_ev = 'cancelado' then coalesce(nullif(btrim(p_comentario),''), 'cancelado desde el pipeline')
                            when v_ev = 'reabrir'   then null else p.cerrado_motivo end,
    updated_at       = now()
  where p.empresa = v_emp and p.order_id = v_clave
  returning * into r;

  -- el timer del submódulo VIEJO: mientras convivan, los dos cuentan lo mismo
  if v_ev = 'speech1' then
    insert into public."GV_Clientes_Nuevos_Contacto" (empresa, order_id, por)
    values (v_emp, v_clave, v_quien)
    on conflict (empresa, order_id) do nothing;
  end if;

  -- el comentario, si lo hubo, es una línea más del MISMO log del pedido
  if coalesce(btrim(p_comentario),'') <> '' and v_ev <> 'cancelado' then
    insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
    values (v_emp, v_clave, nullif(btrim(p_np),''), btrim(p_comentario), v_quien, v_pers);
  end if;

  insert into public."GV_Cuarentena_Log"
    (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
  values (v_emp, v_clave, coalesce(nullif(btrim(p_np),''), r.np), coalesce(nullif(v_cod,''), r.cod),
          coalesce(nullif(btrim(p_razon_social),''), r.razon_social),
          'pipeline_' || v_ev, array['cliente_nuevo'], v_pers, v_quien,
          nullif(btrim(p_comentario),''));

  v_apro := exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = v_emp and public.gv_cuarentena_clave(lb.order_id) = v_clave);
  etapa := public.gv_clin_etapa(r.analisis_at, r.decision, r.speech1_at, r.speech2_at,
                                r.pagado_at, r.cerrado_at, v_apro);
  reloj_desde := public.gv_clin_reloj(etapa, r.analisis_at, r.speech1_at, r.speech2_at);
  return next;
end;
$function$;

-- ── 7. El vínculo: buscar una razón social que ya sea cliente ──────────────────────────
-- Busca en las DOS empresas por razón social, CUIT y código, porque el cliente nuevo puede
-- venir por LK y ser el mismo que ya compra por Chef (y al revés).
-- ⚠ La clave de un cliente es (empresa, cod), nunca cod solo: el mismo número es otra
--   persona en la otra empresa (114 de 115 códigos compartidos, medido el 16/09).
create or replace function public.gv_clin_vinculo_buscar(p_q text, p_limit int default 20)
returns table(empresa text, cod text, razon_social text, cuit text, es_nuevo boolean)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with q as (select nullif(btrim(coalesce(p_q,'')), '') as t),
  qd as (select t, nullif(regexp_replace(coalesce(t,''), '\D', '', 'g'), '') as d from q)
  select c.empresa, c.cod, c.razon_social, c.cuit,
         exists (select 1 from public."GV_Clientes_Nuevos" cn
                  where cn.empresa = c.empresa and cn.cod = c.cod) as es_nuevo
    from public."GV_Cliente_Cuit" c, qd
   where qd.t is not null
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
     and ( c.razon_social ilike '%' || qd.t || '%'
        or c.cod = regexp_replace(qd.t, '\.0+$', '')
        or (qd.d is not null and length(qd.d) >= 6
            and regexp_replace(coalesce(c.cuit,''), '\D', '', 'g') like '%' || qd.d || '%') )
   order by
     -- primero los que YA son clientes de verdad: vincular a otro cliente nuevo no da antigüedad
     (exists (select 1 from public."GV_Clientes_Nuevos" cn
               where cn.empresa = c.empresa and cn.cod = c.cod)),
     (c.razon_social ilike qd.t || '%') desc,
     c.razon_social
   limit greatest(1, least(coalesce(p_limit, 20), 50));
$function$;

-- ── 8. El vínculo: crearlo / sacarlo ───────────────────────────────────────────────────
-- Escribe el vínculo Y la excepción de cuarentena, que es lo que lo hace operar: a partir de
-- acá los PRÓXIMOS pedidos del cliente no caen más como cliente nuevo.
create or replace function public.gv_clin_vincular(
  p_empresa text, p_cod text, p_vinc_empresa text, p_vinc_cod text,
  p_persona text default null, p_por text default null,
  p_order_id text default null, p_nota text default null)
returns table(vinc_empresa text, vinc_cod text, vinc_razon_social text)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_emp   text := public.gv_emp_norm(p_empresa);
  v_cod   text := regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '');
  v_vemp  text := public.gv_emp_norm(p_vinc_empresa);
  v_vcod  text := regexp_replace(btrim(coalesce(p_vinc_cod,'')), '\.0+$', '');
  v_quien text := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')), '');
  v_pers  text := nullif(btrim(p_persona), '');
  v_rs    text; v_vrs text; v_vcuit text; v_clave text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede vincular clientes.' using errcode='42501';
  end if;
  if v_cod = '' or v_vcod = '' then
    raise exception 'Faltan los códigos de cliente.' using errcode='22023';
  end if;
  if v_pers is null then
    raise exception 'Falta indicar quién vincula.' using errcode='22023';
  end if;
  if v_emp = v_vemp and v_cod = v_vcod then
    raise exception 'No se puede vincular un cliente consigo mismo.' using errcode='22023';
  end if;
  -- vincular a otro cliente nuevo no da antigüedad: sería heredar cero
  if exists (select 1 from public."GV_Clientes_Nuevos" cn where cn.empresa = v_vemp and cn.cod = v_vcod) then
    raise exception 'El cliente elegido también figura como cliente nuevo: vincularlo no le da antigüedad.'
      using errcode='22023';
  end if;

  select c.razon_social into v_rs   from public."GV_Cliente_Cuit" c where c.empresa = v_emp  and c.cod = v_cod;
  select c.razon_social, c.cuit into v_vrs, v_vcuit
    from public."GV_Cliente_Cuit" c where c.empresa = v_vemp and c.cod = v_vcod;

  insert into public."GV_Cliente_Vinculo"
    (empresa, cod, razon_social, vinc_empresa, vinc_cod, vinc_razon_social, vinc_cuit,
     order_id, nota, por, persona, activo)
  values (v_emp, v_cod, v_rs, v_vemp, v_vcod, v_vrs, v_vcuit,
          public.gv_cuarentena_clave(nullif(btrim(p_order_id),'')), nullif(btrim(p_nota),''),
          v_quien, v_pers, true)
  on conflict (empresa, cod) do update
     set vinc_empresa = excluded.vinc_empresa, vinc_cod = excluded.vinc_cod,
         vinc_razon_social = excluded.vinc_razon_social, vinc_cuit = excluded.vinc_cuit,
         order_id = coalesce(excluded.order_id, "GV_Cliente_Vinculo".order_id),
         nota = excluded.nota, por = excluded.por, persona = excluded.persona,
         activo = true, actualizado_at = now();

  -- Lo que lo hace OPERAR. `gv_cuarentena_marcar_calc` ya filtra todos los motivos por
  -- gv_cuarentena_exento, así que con esta fila el cliente deja de caer como cliente nuevo.
  insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, activo, nota, actualizado_por)
  values (v_emp, v_cod, v_rs, array['cliente_nuevo'], 'vinculo', true,
          'Vinculado a ' || upper(v_vemp) || ' ' || v_vcod || ' (' || coalesce(v_vrs,'sin razón social') ||
          ') por ' || v_pers, v_quien)
  on conflict (empresa, cod) do update
     set motivos = (select array_agg(distinct x)
                      from unnest(gv_excepcion_cuarentena.motivos || array['cliente_nuevo']) x),
         activo = true, nota = excluded.nota, actualizado_por = excluded.actualizado_por,
         actualizado_at = now();

  v_clave := public.gv_cuarentena_clave(nullif(btrim(p_order_id),''));
  insert into public."GV_Cuarentena_Log"
    (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
  values (v_emp, coalesce(v_clave, 'cliente:' || v_cod), null, v_cod, v_rs,
          'pipeline_vinculado', array['cliente_nuevo'], v_pers, v_quien,
          'Vinculado a ' || upper(v_vemp) || ' ' || v_vcod || ' — ' || coalesce(v_vrs, 'sin razón social'));

  vinc_empresa := v_vemp; vinc_cod := v_vcod; vinc_razon_social := v_vrs;
  return next;
end;
$function$;

create or replace function public.gv_clin_desvincular(
  p_empresa text, p_cod text, p_persona text default null, p_por text default null)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_emp   text := public.gv_emp_norm(p_empresa);
  v_cod   text := regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', '');
  v_quien text := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')), '');
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede desvincular clientes.' using errcode='42501';
  end if;
  update public."GV_Cliente_Vinculo" set activo = false, actualizado_at = now()
   where empresa = v_emp and cod = v_cod;
  -- se saca SÓLO el motivo que puso el vínculo; si la fila tenía otros motivos, quedan.
  update public.gv_excepcion_cuarentena
     set motivos = array_remove(motivos, 'cliente_nuevo'),
         activo = (array_length(array_remove(motivos, 'cliente_nuevo'), 1) >= 1),
         actualizado_por = v_quien, actualizado_at = now()
   where empresa = v_emp and cod = v_cod and origen = 'vinculo';
  insert into public."GV_Cuarentena_Log" (empresa, clave, cod, evento, motivos, persona, por, comentario)
  values (v_emp, 'cliente:' || v_cod, v_cod, 'pipeline_desvinculado', array['cliente_nuevo'],
          nullif(btrim(p_persona),''), v_quien, 'Vínculo dado de baja');
end;
$function$;

-- ── 9. Qué pedidos tienen que salir YA (la prioridad de Luis) ──────────────────────────
-- Luis, 21/09: el cliente nuevo aprobado se programa dentro de los 2 días hábiles y, si en su
-- zona no hay camión, **se le funda uno**. Esta vista es el insumo: dice qué pedidos están en
-- esa condición y hasta cuándo. Quien la consume decide (hoy: la pestaña la pinta en rojo).
create or replace view public.gv_clin_prioritarios
with (security_invoker = true) as
with cfg as (
  select coalesce((select valor from public."PPP_Web_Config" where clave='clin_prioridad_dias'), 2) as d
)
select p.empresa, p.order_id, p.np, p.cod, p.razon_social,
       p.decision                                           as via,
       coalesce(p.pagado_at, p.decision_at)                  as listo_desde,
       lb.liberado_at,
       (select max(d) from (
          select g::date d, row_number() over (order by g) rn
            from generate_series(coalesce(lb.liberado_at, now())::date,
                                 coalesce(lb.liberado_at, now())::date + 20, interval '1 day') g
           where public.gv_es_dia_habil(g::date)) q, cfg
         where q.rn <= cfg.d)                                as salir_antes_de
  from public."GV_Cliente_Nuevo_Pipeline" p
  join public."GV_Cuarentena_Liberados" lb
    on lb.empresa = p.empresa and public.gv_cuarentena_clave(lb.order_id) = p.order_id
 where p.cerrado_at is null
   and p.decision in ('referenciado','valido')
   and (p.decision = 'referenciado' or p.pagado_at is not null);

-- ── 10. Centinela: lo que está esperando hace demasiado ────────────────────────────────
-- vacía = todo bien. Es lo que alimenta el badge rojo de la pestaña (Luis, 21/09: el pedido
-- NO se cancela solo, *"sale un badge en la pestaña"*).
create or replace view public.gv_clin_vencidos
with (security_invoker = true) as
with cfg as (
  select coalesce((select valor from public."PPP_Web_Config" where clave='clin_speech_horas'), 24)   as h_speech,
         coalesce((select valor from public."PPP_Web_Config" where clave='clin_analisis_horas'), 24) as h_analisis
),
eta as (
  select p.*, public.gv_clin_etapa(p.analisis_at, p.decision, p.speech1_at, p.speech2_at,
                                   p.pagado_at, p.cerrado_at,
                                   exists (select 1 from public."GV_Cuarentena_Liberados" lb
                                            where lb.empresa = p.empresa
                                              and public.gv_cuarentena_clave(lb.order_id) = p.order_id)) as etapa
    from public."GV_Cliente_Nuevo_Pipeline" p
)
select e.empresa, e.order_id, e.np, e.cod, e.razon_social, e.etapa,
       public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at) as espera_desde,
       round(extract(epoch from (now() - public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at)))/3600.0, 1) as horas,
       case e.etapa when 'analisis' then c.h_analisis else c.h_speech end as tope_horas
  from eta e cross join cfg c
 where e.etapa in ('analisis','speech1','speech2')
   and public.gv_clin_reloj(e.etapa, e.analisis_at, e.speech1_at, e.speech2_at)
       < now() - make_interval(hours => case when e.etapa = 'analisis' then c.h_analisis else c.h_speech end);

-- ── 11. Permisos ───────────────────────────────────────────────────────────────────────
-- Las vistas son security_invoker y las tablas tienen RLS sin policy: `anon` no ve nada
-- directo. Todo pasa por las RPC, que llevan el guard de supervisor adentro.
revoke all on public.gv_clin_prioritarios from anon, authenticated;
revoke all on public.gv_clin_vencidos     from anon, authenticated;
grant execute on function public.gv_clin_pipeline_lote(jsonb)                             to anon, authenticated;
grant execute on function public.gv_clin_evento(text,text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.gv_clin_vinculo_buscar(text,int)                         to anon, authenticated;
grant execute on function public.gv_clin_vincular(text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.gv_clin_desvincular(text,text,text,text)                 to anon, authenticated;

-- ── 12. Centinelas de las reglas que no se pueden perder ───────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_clin_evento', 'funcion', 'GV_Clientes_Nuevos_Contacto',
   'El Speech 1 del pipeline sella tambien el timer del submodulo viejo: mientras convivan los dos cuentan lo mismo.',
   'Luis', 'v20.63'),
  ('gv_clin_vincular', 'funcion', 'gv_excepcion_cuarentena',
   'El vinculo opera escribiendo la excepcion de cuarentena; sin eso el pop-up es decorativo y el proximo pedido vuelve a caer.',
   'Luis', 'v20.63'),
  ('gv_clin_vincular', 'funcion', 'GV_Clientes_Nuevos',
   'No se puede vincular a otro cliente nuevo: heredar de alguien sin antiguedad es heredar cero.',
   'Luis', 'v20.63')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c
                   where c.objeto = v.objeto and c.patron = v.patron);

-- ── CHEQUEOS ───────────────────────────────────────────────────────────────────────────
--   select * from public.gv_reglas_perdidas;    -- vacía = ninguna regla se perdió
--   select * from public.gv_clin_vencidos;      -- lo que espera hace demasiado (badge rojo)
--   select * from public.gv_clin_prioritarios;  -- lo aprobado que tiene que salir en 2 días
--   select empresa, cod, vinc_cod, activo from public."GV_Cliente_Vinculo";
--
-- ROLLBACK (no borra la historia del log, que no se borra nunca):
--   drop view if exists public.gv_clin_vencidos, public.gv_clin_prioritarios;
--   drop function if exists public.gv_clin_evento(text,text,text,text,text,text,text,text,text);
--   drop function if exists public.gv_clin_pipeline_lote(jsonb);
--   drop function if exists public.gv_clin_vincular(text,text,text,text,text,text,text,text);
--   drop function if exists public.gv_clin_desvincular(text,text,text,text);
--   drop function if exists public.gv_clin_vinculo_buscar(text,int);
--   drop function if exists public.gv_clin_etapa(timestamptz,text,timestamptz,timestamptz,timestamptz,timestamptz,boolean);
--   drop function if exists public.gv_clin_reloj(text,timestamptz,timestamptz,timestamptz);
--   -- las excepciones que puso el vínculo:
--   update public.gv_excepcion_cuarentena set activo = false where origen = 'vinculo';
