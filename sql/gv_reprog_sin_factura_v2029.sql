-- ═══════════════════════════════════════════════════════════════════════════════════════
-- CORTE DE LAS 18 HS: lo que no está facturado no sale mañana · v20.29 (2026-09-20)
--
-- Luis, 20/09, textual: *"si a las 18 hs ya no hay facturado algo para que salga al próximo
-- día hábil, se debe reprogramar de manera automática al siguiente día que sale esa zona.
-- Salvo que sea súper. Si es súper, tiene que llegar aviso."*
--
-- Cron **96 `gv-reprog-sin-factura-18hs`**, `0 21 * * 1-5` UTC = **18:00 ART de lunes a
-- viernes**. El viernes a las 18 mira el lunes: `v_obj` es el próximo día HÁBIL, no el
-- siguiente día calendario.
--
-- QUÉ HACE CON CADA TANDA DEL DÍA OBJETIVO QUE NO ESTÁ ENTERA FACTURADA:
--
-- | caso | acción | por qué |
-- |---|---|---|
-- | súper | **aviso**, no se toca | pedido de Luis |
-- | **retira** | **aviso**, no se toca | ⚠ no está en el pedido original, lo agregué: no es un camión nuestro. El cliente eligió el día (v19.52) y viene a buscar. Moverlo solo = llega y el pedido no está. La corrida en seco del 20/09 mostró 4 tandas de Retira que se habrían movido solas |
-- | tanda **mitad facturada** | **aviso**, no se toca | partirla deja la mercadería en la pila de la tanda vieja (guard v20.01 de Thomas, el caso Martinelli de las 92 cajas huérfanas) |
-- | el resto | **se mueve** al siguiente día con camión a esa zona | la regla |
--
-- ⚠ TRABAJA POR TANDA, NUNCA POR NP, por la misma razón que el guard v20.01: el picking vive
--   en la pila de la tanda, no del pedido.
--
-- ⚠ SI NO HAY OTRO DÍA CON CAMIÓN A ESA ZONA va al próximo día con cupo. Suena peor de lo que
--   es: cuando varias tandas de la misma zona caen juntas, la primera funda el día y las
--   siguientes **ya lo encuentran** (el lazo consulta `gv_ppp_web_dias_ancla` en cada vuelta,
--   y con `p_aplicar = true` cada movida ya está escrita). Terminan viajando juntas.
--
-- Todo queda en **`GV_Reprog_Sin_Factura_Log`** y sale un Telegram por corrida, con las tres
-- listas separadas: reprogramadas solas · no se tocaron (hay que decidirlas) · no se pudieron.
--
-- PROBAR SIN ESCRIBIR — y también sirve para correrlo a mano sobre otro día:
--   select * from public.gv_ppp_reprogramar_sin_factura(false, date '2026-09-22');
--
-- Corrida en seco del 20/09 contra el martes 22: 8 tandas se moverían (5,241 m³) y 4 de Retira
-- quedarían avisadas (0,677 m³).
--
-- APAGARLO:  select cron.alter_job(96, active := false);
-- ═══════════════════════════════════════════════════════════════════════════════════════

create table if not exists public."GV_Reprog_Sin_Factura_Log" (
  id bigserial primary key,
  corrida timestamptz not null default now(),
  fecha_objetivo date,
  tanda text, zona text, nps int, facturadas int, m3 numeric,
  es_super boolean, accion text, destino date, detalle text);
alter table public."GV_Reprog_Sin_Factura_Log" enable row level security;
revoke insert, update, delete, truncate on public."GV_Reprog_Sin_Factura_Log" from anon, authenticated;
grant select on public."GV_Reprog_Sin_Factura_Log" to anon, authenticated, service_role;

create or replace function public.gv_ppp_reprogramar_sin_factura(
  p_aplicar boolean default true, p_fecha date default null)
returns table(tanda text, zona text, nps int, facturadas int, m3 numeric,
              es_super boolean, accion text, destino date, detalle text)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_hoy  date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_obj  date; r record; v_dest date; v_det text; v_acc text;
  v_mov int := 0; v_avi int := 0; v_err int := 0; v_msg text := '';
begin
  if p_fecha is not null then
    v_obj := p_fecha;
  else
    v_obj := v_hoy + 1;
    while not public.gv_es_dia_habil(v_obj) loop v_obj := v_obj + 1; end loop;
  end if;

  create temp table if not exists _rsf (
    tanda text, zona text, nps int, facturadas int, m3 numeric,
    es_super boolean, accion text, destino date, detalle text) on commit drop;
  delete from _rsf where true;

  for r in
    select d.tanda, min(d.zona_corta) as zona, count(*)::int as nps,
           count(*) filter (where coalesce(d.facturado,false))::int as fact,
           round(sum(d.m3)::numeric,3) as m3,
           bool_or(public.gv_es_super(d.empresa, d.cod) or public.gv_es_super_np(d.np, d.cod)
                or coalesce(d.zona_corta,'') ~* 'super') as es_super,
           bool_or(coalesce(d.zona_corta,'') ~* 'retira') as es_retira
      from public.gv_ppp_detalle_dia d
     where d.fecha = v_obj and coalesce(nullif(btrim(d.tanda),''),'') <> ''
     group by d.tanda
    having count(*) filter (where coalesce(d.facturado,false)) < count(*)
     order by d.tanda
  loop
    v_dest := null; v_det := null;
    if r.es_super then
      v_acc := 'aviso_super';  v_avi := v_avi + 1;
      v_det := 'SUPER sin facturar. No se reprograma solo: lo decide una persona.';
    elsif r.es_retira then
      v_acc := 'aviso_retira'; v_avi := v_avi + 1;
      v_det := 'RETIRA sin facturar. El cliente eligio el dia y viene a buscar: no se mueve solo.';
    elsif r.fact > 0 then
      v_acc := 'aviso_mixta';  v_avi := v_avi + 1;
      v_det := r.fact || ' de ' || r.nps || ' facturadas. No se puede partir la tanda: la mercaderia vive en su pila.';
    else
      select min(x) into v_dest
        from unnest(public.gv_ppp_web_dias_ancla(r.zona, v_obj + 1, 20)) x where x > v_obj;
      if v_dest is null then
        v_dest := public.gv_ppp_web_proximo_dia_con_cupo(v_obj + 1);
        v_det  := 'Sin otro dia con camion a ' || coalesce(r.zona,'?') || ': va al proximo dia con cupo.';
      else
        v_det  := 'Proximo dia con camion a ' || coalesce(r.zona,'?') || '.';
      end if;
      if p_aplicar then
        begin
          perform public.gv_ppp_tanda_mover(r.tanda, v_dest, 'automatico 18 hs', true, null);
          v_acc := 'movida'; v_mov := v_mov + 1;
        exception when others then
          v_acc := 'no_se_pudo'; v_err := v_err + 1; v_det := left(sqlerrm, 300);
        end;
      else
        v_acc := 'se_moveria';
      end if;
    end if;
    insert into _rsf values (r.tanda, r.zona, r.nps, r.fact, r.m3, r.es_super, v_acc, v_dest, v_det);
  end loop;

  if p_aplicar then
    insert into public."GV_Reprog_Sin_Factura_Log"
      (fecha_objetivo, tanda, zona, nps, facturadas, m3, es_super, accion, destino, detalle)
    select v_obj, z.tanda, z.zona, z.nps, z.facturadas, z.m3, z.es_super, z.accion, z.destino, z.detalle from _rsf z;

    if v_mov + v_avi + v_err > 0 then
      v_msg := E'\U0001F9FE\U0001F4C5 SIN FACTURAR para el ' || to_char(v_obj,'DD/MM') || ' - corte de las 18 hs' || E'\n';
      if v_mov > 0 then
        v_msg := v_msg || E'\n✅ Reprogramadas solas (' || v_mov || '):' ||
          coalesce((select string_agg(E'\n  . '||z.tanda||' '||coalesce(z.zona,'')||' '||z.m3||' m3 -> '||to_char(z.destino,'DD/MM'), '' order by z.tanda)
                      from _rsf z where z.accion = 'movida'), '');
      end if;
      if v_avi > 0 then
        v_msg := v_msg || E'\n\n⚠ NO se tocaron, hay que decidirlas (' || v_avi || '):' ||
          coalesce((select string_agg(E'\n  . '||z.tanda||' '||coalesce(z.zona,'')||' '||z.m3||' m3 - '||z.detalle, '' order by z.tanda)
                      from _rsf z where z.accion like 'aviso%'), '');
      end if;
      if v_err > 0 then
        v_msg := v_msg || E'\n\n❌ No se pudieron mover (' || v_err || '):' ||
          coalesce((select string_agg(E'\n  . '||z.tanda||' - '||z.detalle, '' order by z.tanda)
                      from _rsf z where z.accion = 'no_se_pudo'), '');
      end if;
      perform public.tg_enqueue(v_msg, 'reprog_sinfact_'||to_char(v_obj,'YYYYMMDD'));
      perform public.tg_outbox_flush();
    end if;
  end if;

  return query select z.tanda, z.zona, z.nps, z.facturadas, z.m3, z.es_super, z.accion, z.destino, z.detalle
                 from _rsf z order by z.accion, z.tanda;
end
$function$;

revoke all on function public.gv_ppp_reprogramar_sin_factura(boolean, date) from public;
grant execute on function public.gv_ppp_reprogramar_sin_factura(boolean, date) to service_role;

select cron.schedule('gv-reprog-sin-factura-18hs', '0 21 * * 1-5',
  $cron$select public.gv_ppp_reprogramar_sin_factura(true, null);$cron$);
