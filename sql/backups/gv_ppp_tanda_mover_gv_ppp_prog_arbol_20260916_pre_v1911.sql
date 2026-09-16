-- Backup ANTES de la v19.11 (2026-09-16) — las dos definiciones tal cual estaban en la base.
-- Sacadas con pg_get_functiondef. Correr este archivo entero deja el backend como estaba:
--   · gv_ppp_tanda_mover vuelve a la firma de 3 argumentos y a rechazar TODA tanda empezada
--     (o sea: el botón «Cambiar de día» vuelve a rebotar en los 8/8 días de Pedidos atrasados);
--   · gv_ppp_prog_arbol vuelve a ignorar GV_PPP_Prog_Override en las ramas `fact` y `hist`.
-- Ojo al restaurar: hay que dropear antes la firma de 4 argumentos, si no quedan las dos y toda
-- llamada de 3 argumentos se vuelve ambigua:
--   drop function if exists public.gv_ppp_tanda_mover(text, date, text, boolean);

CREATE OR REPLACE FUNCTION public.gv_ppp_tanda_mover(p_tanda text, p_fecha date, p_por text DEFAULT NULL::text)
 RETURNS TABLE(movidas integer, np_web integer, np_isis integer, m3 numeric, aviso text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_t      text := upper(btrim(coalesce(p_tanda, '')));
  v_ev     int;
  v_web    int := 0;
  v_isis   int := 0;
  v_m3     numeric := 0;
  v_aviso  text := null;
  v_cupo   numeric;
  v_usado  numeric;
  v_nota   text;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden mover tandas.';
  end if;
  if v_t = '' then raise exception 'Falta el código de la tanda.'; end if;
  if p_fecha is null then raise exception 'Falta la fecha nueva.'; end if;

  -- ¿ya la empezaron? (EP, PKC, TP, AP, TAP… cualquier evento con la tanda en el primer campo del texto)
  select count(*) into v_ev
    from public."Registros_Produccion_Virgilio" r
   where upper(btrim(split_part(r.texto, '|', 1))) = v_t;
  if v_ev > 0 then
    raise exception 'La tanda % ya está empezada (% evento(s) de operarios): no se puede mover de día.', v_t, v_ev;
  end if;

  v_nota := 'v13.87 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
            || ' · movida desde la app a ' || to_char(p_fecha, 'DD/MM')
            || coalesce(' por ' || nullif(btrim(p_por), ''), '');

  -- ── tanda WEB ────────────────────────────────────────────────────────────
  update public."PPP_Web_Programacion" w
     set fecha_entrega = p_fecha
   where upper(btrim(coalesce(w.tanda, ''))) = v_t;
  get diagnostics v_web = row_count;
  if v_web > 0 then
    update public."PPP_Web_Tandas" t set fecha_entrega = p_fecha
     where upper(btrim(t.codigo)) = v_t;
  end if;

  -- ── tanda de ISIS: se pisa fila por fila en el override ───────────────────
  insert into public."GV_PPP_Prog_Override" (np, fecha_entrega, nota)
  select d.np, p_fecha, v_nota
    from public.gv_ppp_programacion_diaria d
   where upper(btrim(coalesce(d.tanda, ''))) = v_t
     and d.np is not null
     and not exists (select 1 from public."PPP_Web_Programacion" w
                      where upper(btrim(coalesce(w.tanda, ''))) = v_t and w.np::text = d.np)
  on conflict (np) do update
     set fecha_entrega = excluded.fecha_entrega, nota = excluded.nota;
  get diagnostics v_isis = row_count;

  if v_web = 0 and v_isis = 0 then
    raise exception 'No encontré la tanda %.', v_t;
  end if;

  -- m³ de lo movido (ya con la fecha nueva)
  select coalesce(round(sum(x.m3), 3), 0) into v_m3 from (
    select w.m3 from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda,''))) = v_t
    union all
    select d.m3 from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda,''))) = v_t
  ) x;

  -- avisos del día destino (no bloquean: los muestra el front)
  v_cupo := public.gv_ppp_web_cupo(p_fecha);
  select coalesce(sum(g.m3), 0) into v_usado
    from public."PPP_Web_Programacion" g
   where g.fecha_entrega = p_fecha and coalesce(nullif(trim(g.tanda), ''), '') <> '';
  v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);
  if v_usado > v_cupo then
    v_aviso := 'El ' || to_char(p_fecha, 'DD/MM') || ' queda con ' || round(v_usado, 3)
               || ' m³, por encima del cupo de ' || v_cupo || ' m³.';
  end if;
  if not public.gv_es_dia_habil(p_fecha) then
    v_aviso := coalesce(v_aviso || ' ', '') || 'Ojo: el ' || to_char(p_fecha, 'DD/MM')
               || ' no es día hábil (fin de semana o feriado).';
  end if;

  return query select (v_web + v_isis), v_web, v_isis, v_m3, v_aviso;
end $function$;

CREATE OR REPLACE FUNCTION public.gv_ppp_prog_arbol(p_desde date, p_hasta date)
 RETURNS TABLE(fecha date, tanda text, np text, np_num numeric, cod text, razon_social text, localidad text, zona text, zona_corta text, empresa text, origen text, m3 numeric, estado text, estado_orden integer, clave text, pide_horario boolean, horario_fecha date, horario_franja text, horario_origen text, barrio text, fecha_pedido date)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with fuentes as (
  select 1 as pri,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as np,
         upper(btrim(coalesce(p.tanda, '')))                               as tanda,
         coalesce(p.m3, 0)::numeric                                        as m3,
         nullif(left(btrim(p.fecha_entrega), 10), '')::date                as fe,
         coalesce(btrim(p.cod), '')                                        as cod,
         coalesce(btrim(p.razon_social), '')                               as razon_social,
         coalesce(nullif(btrim(coalesce(p.barrio, '')), ''),
                  btrim(coalesce(p.direccion, '')))                        as localidad,
         coalesce(btrim(p.zona), '')                                       as zona,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as clave,
         nullif(btrim(coalesce(p.barrio, '')), '')                         as barrio,
         case when left(btrim(coalesce(p.fecha_recep, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(p.fecha_recep), 10)::date end                as fecha_pedido,
         'isis'::text                                                      as origen
    from public.gv_ppp_programacion_diaria p
   where left(btrim(coalesce(p.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
  union all
  select 2,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         upper(btrim(coalesce(w.tanda, ''))),
         coalesce(w.m3, 0)::numeric,
         w.fecha_entrega,
         coalesce(btrim(w.cod_cliente), ''),
         coalesce(btrim(w.razon_social), ''),
         coalesce(nullif(btrim(coalesce(w.barrio, '')), ''), btrim(coalesce(w.direccion, ''))),
         coalesce(btrim(w.zona), ''),
         w.order_id::text,
         nullif(btrim(coalesce(w.barrio, '')), ''),
         w.fecha_recep::date,
         'web'
    from public."PPP_Web_Programacion" w
   where w.tanda is not null and btrim(w.tanda) <> ''
  union all
  select 3,
         regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         upper(btrim(coalesce(f.tanda, ''))),
         coalesce(f.m3, 0)::numeric,
         f.fecha_salida,
         coalesce(btrim(f.cod_cliente), ''),
         coalesce(btrim(f.razon_social), ''),
         '', '', regexp_replace(upper(btrim(f.np)), '\.0+$', ''), null::text, null::date, 'fact'
    from public."Facturacion_NP" f
   where f.fecha_salida is not null
  union all
  select 4,
         regexp_replace(btrim(h.np), '\.0+$', ''),
         upper(btrim(coalesce(h.tanda, ''))),
         coalesce(h.m3, 0)::numeric,
         case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(h.fecha_entrega), 10)::date end,
         coalesce(btrim(h.cod), ''),
         coalesce(btrim(h.rs), ''),
         '', '', regexp_replace(btrim(h.np), '\.0+$', ''), null::text, null::date, 'hist'
    from public."GV_PPP_Entregados_Historico" h
),
fuera as (
  select o.np
    from public."GV_PPP_Prog_Override" o
   where coalesce(o.oculto, false) or coalesce(o.desprogramada, false)
  union
  select regexp_replace(btrim(coalesce(c.np, '')), '\.0+$', '')
    from public."NP_Canceladas" c
),
uni as (
  select distinct on (f.np) f.*
    from fuentes f
   where f.np <> '' and f.fe is not null
     and not exists (select 1 from fuera x where x.np = f.np)
   order by f.np, f.pri, f.m3 desc
),
dia as (select * from uni where fe between p_desde and p_hasta),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP')
     and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
     and r.ts_cliente >= (p_desde - interval '60 days')
),
pick as (select distinct on (tanda) tanda, opcion from ev where opcion in ('EP','TP') order by tanda, ts_cliente desc),
arm  as (select distinct on (tanda) tanda, opcion from ev where opcion in ('AP','TAP') order by tanda, ts_cliente desc),
salio as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
fact as (select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f),
est as (
  select d.fe, d.np, d.tanda, d.m3, d.cod, d.razon_social, d.localidad, d.zona, d.origen, d.clave, d.barrio, d.fecha_pedido,
         (fc.np is not null)                          as b_fact,
         (s.np is not null or a.opcion = 'TAP')       as b_arm,
         (a.opcion = 'AP' or p.opcion in ('TP','EP')) as b_curso
    from dia d
    left join salio s on s.np = upper(d.np)
    left join fact fc on fc.np = upper(d.np)
    left join pick  p on p.tanda = d.tanda and d.tanda <> ''
    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
)
select e.fe,
       coalesce(nullif(e.tanda, ''), '—'),
       e.np,
       nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric,
       e.cod, e.razon_social, e.localidad, e.zona,
       case when e.zona ~* 'retira'                                    then 'Retira'
            when public.gv_es_super_np(e.np, e.cod)
              or e.zona ~* 'super|coto|carrefour|chango|krikos'        then 'Súper'
            else coalesce(substring(e.zona, '^(Zona\s*[0-9]+)'), nullif(btrim(e.zona), ''), 'Sin zona') end,
       case when upper(e.np) like 'LK%' then 'LK'
            when upper(e.np) like 'CH%' then 'CH'
            when coalesce(nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric, 0) > 90000 then 'LK'
            else 'CH' end,
       e.origen, e.m3,
       case when e.b_fact then 'facturado' when e.b_arm then 'armado'
            when e.b_curso then 'proceso' else 'pendiente' end,
       case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end,
       e.clave,
       public.gv_pide_horario_np(e.np, e.cod, e.zona),
       h.fecha, h.franja, h.origen,
       e.barrio, e.fecha_pedido
  from est e
  left join public."GV_Pedido_Horario" h
    on h.empresa = public.gv_emp_de_np(e.np)
   and h.clave in (e.clave, regexp_replace(upper(btrim(e.np)), '\.0+$', ''))
 order by e.fe, coalesce(nullif(e.tanda, ''), '—'),
          nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric nulls last, e.np;
$function$;
