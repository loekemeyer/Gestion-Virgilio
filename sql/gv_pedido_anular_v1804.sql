-- v18.04 — ANULAR UN PEDIDO desde A Programar / Cuarentena (Luis, 2026-09-15)
--
-- Pedido textual: *"Agrega un botón que sea para anular el pedido (lo saca de «a programar»), a
-- usarse para pedidos que entran erróneos, que quede el log de pedidos que se anulan y que
-- requiera confirmación y comentario (quién lo hace y por qué)"*.
--
-- ⚠ NO es lo mismo que BORRAR un pedido. Borrar es la regla del `CLAUDE.md` (se borra de la
-- página, de la NP y de la programación, en los dos proyectos Supabase). Anular acá es sacarlo
-- de la producción de Virgilio y dejarlo anotado: el pedido sigue existiendo en la página.
--
-- ⚠ TAMPOCO es DESARMAR (`gv_ppp_np_desarmar`). Desarmar es para un pedido ya pickeado/armado y
-- mueve stock. Anular es para uno que TODAVÍA NO SE TOCÓ: si la tanda ya se empezó a trabajar,
-- esta función se niega y manda a desarmar.
--
-- ══ 1. El log: `GV_Pedidos_Anulados` ═════════════════════════════════════════════════════════
-- Tabla NUEVA, con snapshot completo (quién, por qué, qué pedido y de cuánto era), porque los
-- dos lugares donde hoy queda el efecto guardan la mitad: `GV_Web_Cancelados` no tiene ni el
-- cliente ni el m³, y `NP_Canceladas` sólo tiene np/motivo/legajo. Ninguna de las dos guarda la
-- PERSONA (Vivi / Marian / …), que es distinta del usuario de la sesión.
--
-- ══ 2. El efecto ═════════════════════════════════════════════════════════════════════════════
-- Se usan los mecanismos que ya existen, para no inventar un tercero:
--   · ISIS → `NP_Canceladas` (que ya excluye `gv_ppp_isis_sin_tanda`) + `GV_PPP_Prog_Override.oculto`
--   · web  → `GV_Web_Cancelados` + se le saca la tanda a `PPP_Web_Programacion` + se lo saca de
--            `GV_PPP_Web_Retenido`
--
-- ══ 3. ⚠ Y el agujero que había en el lado web (problema 213) ════════════════════════════════
-- `GV_Web_Cancelados` NO LA LEÍA NADIE. `gv_ppp_np_cancelar` (v15.55) escribía ahí, ponía
-- tanda=null y contestaba *"fuera de la PPP; no vuelve a entrar"* — pero con tanda=null el
-- pedido vuelve a contar como pendiente y el cron lo re-arma en la corrida siguiente.
-- Caso vivo medido el 15/09: el pedido web LK 1375 (Andser Química SRL) se canceló el 11/09
-- "Cancelado por el cliente" y hoy tiene NP LK 0052, tanda E22A y entrega el 28/09.
-- Por eso `gv_pedidos_web_excluidos` suma el motivo `anulado` (archivo aparte,
-- `sql/gv_pedidos_web_excluidos_v1804.sql`). Con eso el anulado no vuelve ni a la pantalla ni al
-- cron — y de paso deja de volver lo cancelado con `gv_ppp_np_cancelar` y lo desarmado.

-- ── El log ───────────────────────────────────────────────────────────────────────────────────
create table if not exists public."GV_Pedidos_Anulados" (
  id            bigserial primary key,
  empresa       text        not null,
  clave         text        not null,   -- order_id del pedido de la página, o la NP de ISIS
  es_isis       boolean     not null default false,
  np_label      text,                   -- lo que se leía en pantalla: "web LK 1416" / "NP 98587"
  order_id      bigint,
  cod           text,
  razon_social  text,
  m3            numeric,
  fecha_recep   date,
  zona          text,
  motivo        text        not null,   -- POR QUÉ se anula (obligatorio)
  persona       text        not null,   -- QUIÉN lo hace (Vivi / Marian / lo que escriban)
  por           text,                   -- el usuario de la sesión, que es otra cosa
  anulado_at    timestamptz not null default now()
);
create index if not exists "GV_Pedidos_Anulados_clave_idx"
  on public."GV_Pedidos_Anulados" (empresa, clave);
create index if not exists "GV_Pedidos_Anulados_fecha_idx"
  on public."GV_Pedidos_Anulados" (anulado_at desc);

-- RLS prendida y SIN policies: nadie la lee por PostgREST. Se entra por las RPC de abajo, que
-- son security definer y chequean supervisor. Mismo patrón que GV_Cuarentena_Comentarios.
alter table public."GV_Pedidos_Anulados" enable row level security;
revoke all on public."GV_Pedidos_Anulados" from anon, authenticated;
revoke all on sequence public."GV_Pedidos_Anulados_id_seq" from anon, authenticated;

-- ── Anular ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_pedido_anular(
  p_empresa text, p_clave text, p_motivo text, p_persona text,
  p_por text default null, p_es_isis boolean default null, p_datos jsonb default null)
 returns table(tipo text, np text, detalle text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  v_emp    text := lower(nullif(btrim(p_empresa), ''));
  v_clave  text := nullif(btrim(p_clave), '');
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_quien  text := nullif(btrim(coalesce(p_persona, '')), '');
  v_d      jsonb := coalesce(p_datos, '{}'::jsonb);
  v_isis   boolean;
  v_np     text;
  v_oid    bigint;
  v_label  text;
  v_cod    text;
  v_rs     text;
  v_m3     numeric;
  v_fr     date;
  v_zona   text;
  v_tanda  text;
  v_n      int := 0;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede anular un pedido.' using errcode='42501';
  end if;
  if v_emp is null or v_clave is null then
    raise exception 'Falta la empresa o el pedido.' using errcode='22023';
  end if;
  if v_motivo is null then
    raise exception 'Falta el motivo: anular un pedido pide explicar por que.' using errcode='22023';
  end if;
  if v_quien is null then
    raise exception 'Falta quien lo anula.' using errcode='22023';
  end if;

  -- Una NP de ISIS entra a A Programar disfrazada de pedido con order_id = 'np' + NP.
  v_isis := coalesce(p_es_isis, v_clave ~* '^np[0-9]+$');
  v_np   := public.gv_cuarentena_clave(v_clave);   -- 'np98587' -> '98587'

  -- Datos que manda la pantalla (es lo que el supervisor tenia delante al apretar el boton).
  v_label := nullif(btrim(coalesce(v_d->>'np_label', '')), '');
  v_cod   := nullif(btrim(coalesce(v_d->>'cod', '')), '');
  v_rs    := nullif(btrim(coalesce(v_d->>'razon_social', '')), '');
  v_m3    := nullif(v_d->>'m3', '')::numeric;
  v_fr    := nullif(left(coalesce(v_d->>'fecha_recep',''), 10), '')::date;
  v_zona  := nullif(btrim(coalesce(v_d->>'zona', '')), '');

  if v_isis then
    -- Lo que sepa la programacion gana sobre lo que mando la pantalla (por si vino incompleto).
    select coalesce(nullif(btrim(p.cod),''), v_cod), coalesce(nullif(btrim(p.razon_social),''), v_rs),
           coalesce(p.m3, v_m3), regexp_replace(btrim(coalesce(p.tanda,'')), '\s+$','')
      into v_cod, v_rs, v_m3, v_tanda
      from public.gv_ppp_programacion_diaria p
     where regexp_replace(btrim(p.np), '\.0+$','') = v_np
     limit 1;
    -- la que pudo haberla trabajado antes de que la desprogramaran
    if nullif(v_tanda,'') is null then
      select nullif(btrim(coalesce(o.tanda_previa,'')), '') into v_tanda
        from public."GV_PPP_Prog_Override" o where o.np = v_np limit 1;
    end if;
  else
    v_oid := v_clave::bigint;
    -- Un pedido de la pagina puede salir en VARIAS NP (bloques), asi que se agrega: el m3 es la
    -- suma y la tanda que interesa para el guard es cualquiera que ya se haya tocado.
    select coalesce(nullif(btrim(max(w.cod_cliente)),''), v_cod),
           coalesce(nullif(btrim(max(w.razon_social)),''), v_rs),
           coalesce(sum(w.m3), v_m3),
           max(w.tanda) filter (where public.gv_ppp_tanda_tocada(w.tanda))
      into v_cod, v_rs, v_m3, v_tanda
      from public."PPP_Web_Programacion" w
     where w.empresa = v_emp and w.order_id = v_oid;
  end if;

  -- ⚠ Si la tanda ya se empezo a trabajar, esto NO alcanza: hay mercaderia movida y el stock hay
  -- que devolverlo. Para eso esta Desarmar, que es otra funcion y otra pantalla.
  if nullif(v_tanda,'') is not null and public.gv_ppp_tanda_tocada(v_tanda) then
    raise exception 'La tanda % ya se empezo a trabajar: este pedido se saca con Desarmar, no con Anular.', v_tanda;
  end if;

  if v_isis then
    insert into public."NP_Canceladas" (np, motivo, legajo)
    values (v_np, 'anulado: ' || v_motivo || ' (' || v_quien || ')',
            coalesce(nullif(btrim(p_por),''), 'supervisor'))
    on conflict (np) do update set motivo = excluded.motivo, legajo = excluded.legajo;
    insert into public."GV_PPP_Prog_Override" (np, oculto, nota)
    values (v_np, true, 'v18.04 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI')
                        || ' · ANULADO desde A Programar por ' || v_quien || ': ' || v_motivo
                        || coalesce(' · ' || nullif(btrim(p_por),''), ''))
    on conflict (np) do update set oculto = true, nota = excluded.nota;
  else
    insert into public."GV_Web_Cancelados" (empresa, order_id, np_label, motivo, por)
    values (v_emp, v_oid, coalesce(v_label, v_np),
            'anulado: ' || v_motivo || ' (' || v_quien || ')', nullif(btrim(p_por),''))
    on conflict on constraint "GV_Web_Cancelados_pkey" do update
       set motivo = excluded.motivo, por = excluded.por,
           np_label = coalesce(excluded.np_label, "GV_Web_Cancelados".np_label),
           creado_at = now();
    update public."PPP_Web_Programacion" w
       set tanda = null, fecha_entrega = null, actualizado_at = now()
     where w.empresa = v_emp and w.order_id = v_oid and w.tanda is not null;
    get diagnostics v_n = row_count;
    delete from public."GV_PPP_Web_Retenido" t where t.empresa = v_emp and t.order_id = v_oid;
  end if;

  insert into public."GV_Pedidos_Anulados"
    (empresa, clave, es_isis, np_label, order_id, cod, razon_social, m3, fecha_recep, zona,
     motivo, persona, por)
  values (v_emp, v_clave, v_isis, coalesce(v_label, v_np), v_oid, v_cod, v_rs, v_m3, v_fr, v_zona,
          v_motivo, v_quien, nullif(btrim(p_por),''));

  return query select
    case when v_isis then 'isis' else 'web' end,
    coalesce(v_label, v_np),
    case when v_isis
         then 'NP ' || v_np || ' anulada: sale de A Programar (NP_Canceladas + oculta en la PPP)'
         else 'pedido ' || v_oid || ' anulado: sale de A Programar y el armado automatico ya no lo toma'
              || case when v_n > 0 then ' (se le saco la tanda a ' || v_n || ' NP)' else '' end
    end::text;
end;
$function$;

revoke all on function public.gv_pedido_anular(text, text, text, text, text, boolean, jsonb) from public, anon;
grant execute on function public.gv_pedido_anular(text, text, text, text, text, boolean, jsonb) to authenticated, service_role;

-- ── Leer el log ──────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_pedidos_anulados(p_dias integer default 90)
 returns table(id bigint, empresa text, clave text, es_isis boolean, np_label text,
               cod text, razon_social text, m3 numeric, fecha_recep date, zona text,
               motivo text, persona text, por text, anulado_at timestamptz)
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select a.id, a.empresa, a.clave, a.es_isis, a.np_label, a.cod, a.razon_social, a.m3,
         a.fecha_recep, a.zona, a.motivo, a.persona, a.por, a.anulado_at
    from public."GV_Pedidos_Anulados" a
   where a.anulado_at >= now() - make_interval(days => greatest(coalesce(p_dias, 90), 1))
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by a.anulado_at desc;
$function$;

revoke all on function public.gv_pedidos_anulados(integer) from public, anon;
grant execute on function public.gv_pedidos_anulados(integer) to authenticated, service_role;
