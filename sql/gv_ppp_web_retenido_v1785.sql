-- v17.85 (Luis, 2026-09-14) — "ENVIAR A PROGRAMAR" desde la tabla de Programación.
--
-- Pedido: *"un botón que sea una flecha para atrás y que sea «Enviar a programar» en caso de que
-- se tenga que reprogramar la fecha de entrega. Atento a que, si es uno de los que se programan
-- automáticamente (zona 1 y zona 2 creo que eran), tiene que quedar en «A programar» (quedan en
-- el estado que estaban (armado o facturado o pendiente, o sea, el sistema tiene memoria para no
-- mandar a armar algo dos veces o no mandar algo a armar que no estaba armado))"*.
--
-- El lado de ISIS ya existía desde la v16.03 (`gv_ppp_isis_desprogramar` guarda `tanda_previa` en
-- GV_PPP_Prog_Override y `gv_ppp_isis_programar` REUSA esa tanda). Esto le arma el espejo al lado
-- WEB, que no lo tenía y encima estaba bloqueado.
--
-- Qué cambia:
--   1) GV_PPP_Web_Retenido — la tabla nueva: qué pedido web sacó un supervisor de su tanda, de
--      qué tanda y qué fecha venía, y si esa tanda ya estaba pickeada / armada.
--   2) gv_ppp_web_desprogramar v2 — deja de rechazar el pedido cuya tanda ya se tocó (esa era la
--      regla vieja; Thomas ya la había sacado del lado de ISIS en la v16.03) y anota la retención.
--      La ÚNICA guarda que queda es la misma que la de ISIS: si la NP ya tiene Carga Camión o
--      Recepción Remitos, salió, y lo que salió se cierra con el remito.
--   3) gv_ppp_web_armar_pendientes — el automático SALTEA lo retenido. Sin esto el cron de las
--      zonas 1-3 (jobs 71 y 73, cada 15 min) lo reprograma solo en la corrida siguiente y el
--      botón no sirve para nada: es exactamente lo que avisó Luis.
--   4) gv_ppp_web_retenido — la vista que lee A Programar para pintarlo en rojo con su tanda.
--   5) gv_ppp_web_tanda_reusar — reprogramar a MANO en la MISMA tanda de antes. Ésa es la
--      "memoria": si vuelve a su tanda, el estado (pickeado / armado / facturado) vuelve con
--      ella, porque el estado se deriva de los eventos de esa tanda, no de una columna.
--
-- ROLLBACK al final del archivo.

begin;

-- ───────────────────────────────────────────────────────────── 1) la tabla
create table if not exists public."GV_PPP_Web_Retenido" (
  empresa      text    not null,
  order_id     bigint  not null,
  np_idx       int     not null,
  np           int,
  tanda_previa text,
  fecha_previa date,
  ya_pickeada  boolean not null default false,
  ya_armada    boolean not null default false,
  motivo       text,
  por          text,
  creado_at    timestamptz not null default now(),
  primary key (empresa, order_id, np_idx)
);

alter table public."GV_PPP_Web_Retenido" enable row level security;

-- lee todo el mundo (A Programar corre con la anon key); escribe SOLO la RPC, que es
-- SECURITY DEFINER y tiene el gate de supervisor adentro.
revoke insert, update, delete, truncate on public."GV_PPP_Web_Retenido" from anon, authenticated;
grant select on public."GV_PPP_Web_Retenido" to anon, authenticated;
do $$
begin
  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'GV_PPP_Web_Retenido'
                    and policyname = 'gv_ppp_web_retenido_read') then
    create policy gv_ppp_web_retenido_read on public."GV_PPP_Web_Retenido"
      for select to anon, authenticated using (true);
  end if;
end $$;

-- ──────────────────────────────────────────── 2) desprogramar: con memoria y sin el bloqueo
create or replace function public.gv_ppp_web_desprogramar(p_np text, p_por text default null::text)
returns table(np_sacadas integer, order_id bigint)
language plpgsql
security definer
set search_path to 'public'
as $function$
-- ⚠ SIN esto no compila al primer intento: `order_id` es a la vez PARÁMETRO DE SALIDA de la
-- función y COLUMNA de GV_PPP_Web_Retenido, y el INSERT de abajo la nombra → "column reference
-- order_id is ambiguous". Con use_column, adentro de una consulta gana la columna.
#variable_conflict use_column
declare
  v_np text := btrim(p_np); v_emp text; v_num int; v_oid bigint; v_n int; v_sal text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede devolver un pedido a A Programar.' using errcode='42501';
  end if;
  if v_np !~* '^(LK|CH)\s*\d+' then
    raise exception '% no es una NP web: las de ISIS se sacan con gv_ppp_isis_desprogramar.', v_np;
  end if;
  v_emp := case when upper(left(v_np,2)) = 'CH' then 'chef' else 'lk' end;
  v_num := (regexp_match(v_np, '(\d+)'))[1]::int;
  select n.order_id into v_oid from public."PPP_Web_NP" n where n.empresa = v_emp and n.np = v_num limit 1;
  if v_oid is null then raise exception 'No encuentro el pedido web de %.', v_np; end if;

  -- ÚNICA guarda, la misma que la de ISIS: si ya salió, no se saca de la programación.
  -- v17.85: se retiró el rechazo por "la tanda ya se empezó a trabajar". Thomas ya lo había
  -- retirado del lado de ISIS en la v16.03 ("No. Que vayan a programar") y el riesgo de
  -- re-pickear lo cubre `tanda_previa`: al reprogramarlo vuelve a SU tanda.
  select string_agg(distinct upper(btrim(split_part(r.texto,'|',1))), ', ')
    into v_sal
    from public."Registros_Produccion_Virgilio" r
    join public."PPP_Web_Programacion" w
      on w.empresa = v_emp and w.order_id = v_oid
     and upper(btrim(split_part(r.texto,'|',1)))
         = upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
   where r.opcion in ('CCN','CRN') and not public.es_legajo_test(r.legajo);
  if v_sal is not null then
    raise exception 'Estas NP ya tienen Carga Camion o Recepcion Remitos: %. Salieron, no se sacan de la programacion.', v_sal;
  end if;

  -- la memoria: de qué tanda y fecha venía cada bloque, y si esa tanda ya se había trabajado
  insert into public."GV_PPP_Web_Retenido" as t
    (empresa, order_id, np_idx, np, tanda_previa, fecha_previa, ya_pickeada, ya_armada, motivo, por)
  select w.empresa, w.order_id, w.np_idx, w.np,
         nullif(btrim(w.tanda), ''), w.fecha_entrega,
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where r.opcion in ('EP','TP')
                    and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                    and not public.es_legajo_test(r.legajo)),
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where r.opcion in ('AP','TAP')
                    and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                    and not public.es_legajo_test(r.legajo)),
         'sacado de la programacion desde la tabla de Programacion', nullif(btrim(p_por), '')
    from public."PPP_Web_Programacion" w
   where w.empresa = v_emp and w.order_id = v_oid
     and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
  on conflict (empresa, order_id, np_idx) do update
     set tanda_previa = coalesce(excluded.tanda_previa, t.tanda_previa),
         fecha_previa = coalesce(excluded.fecha_previa, t.fecha_previa),
         ya_pickeada  = excluded.ya_pickeada or t.ya_pickeada,
         ya_armada    = excluded.ya_armada   or t.ya_armada,
         motivo = excluded.motivo, por = excluded.por, creado_at = now();

  update public."PPP_Web_Programacion" w
     set tanda = null, fecha_entrega = null, actualizado_at = now()
   where w.empresa = v_emp and w.order_id = v_oid and coalesce(nullif(btrim(w.tanda),''),'') <> '';
  get diagnostics v_n = row_count;
  return query select v_n, v_oid;
end;
$function$;

-- ───────────────────────────────────── 4) la vista que lee A Programar (una fila por bloque)
create or replace view public.gv_ppp_web_retenido
with (security_invoker = true) as
select t.empresa, t.order_id, t.np_idx, t.np,
       t.tanda_previa, t.fecha_previa, t.ya_pickeada, t.ya_armada, t.motivo, t.por, t.creado_at,
       case when t.np is not null then public.gv_ppp_web_np_label(t.empresa, t.np, t.np_idx) end as np_label
  from public."GV_PPP_Web_Retenido" t;
grant select on public.gv_ppp_web_retenido to anon, authenticated;

-- ────────────────── 5) reprogramar a MANO en la MISMA tanda de antes (la "memoria" de Luis)
create or replace function public.gv_ppp_web_tanda_reusar(
  p_empresa text, p_order_id bigint, p_fecha date, p_por text default null::text)
returns table(np_programadas integer, tanda text, fecha date)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_emp text := lower(btrim(coalesce(p_empresa,'lk'))); v_t text; v_n int;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede reprogramar un pedido.' using errcode='42501';
  end if;
  if p_fecha is null then raise exception 'Falta el dia de entrega.'; end if;

  select distinct t.tanda_previa into v_t
    from public."GV_PPP_Web_Retenido" t
   where t.empresa = v_emp and t.order_id = p_order_id and nullif(btrim(t.tanda_previa),'') is not null
   limit 1;
  if v_t is null then
    raise exception 'Ese pedido no quedo retenido con una tanda anterior: programalo como uno nuevo.';
  end if;

  update public."PPP_Web_Programacion" w
     set tanda = v_t, fecha_entrega = p_fecha, actualizado_at = now()
   where w.empresa = v_emp and w.order_id = p_order_id
     and coalesce(nullif(btrim(w.tanda), ''), '') = '';
  get diagnostics v_n = row_count;

  delete from public."GV_PPP_Web_Retenido" t
   where t.empresa = v_emp and t.order_id = p_order_id;

  return query select v_n, v_t, p_fecha;
end;
$function$;
revoke all on function public.gv_ppp_web_tanda_reusar(text,bigint,date,text) from public;
grant execute on function public.gv_ppp_web_tanda_reusar(text,bigint,date,text) to anon, authenticated;

-- ───────────────── 3) el automático SALTEA lo retenido (el parche de gv_ppp_web_armar_pendientes)
--
-- La función es de 13.668 caracteres y lo único que cambia son 11 líneas, así que se parcha
-- sobre su propia definición y se vuelve a ejecutar entera, en UNA transacción y con guardas:
-- si el ancla no aparece exactamente una vez, no se toca nada. La definición PREVIA quedó
-- guardada en zz_backups."GV_Backup_Funcdefs_20260914" (junto con la de gv_ppp_web_desprogramar),
-- que es de dónde se restaura si hay que volver atrás.
--
-- `gv_ppp_web_armar_pendientes_simular` NO hay que tocarla: llama a ésta.

do $do$
declare v_def text; v_new text; v_anchor text; v_add text;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if v_def like '%GV_PPP_Web_Retenido%' then
    raise notice 'ya estaba parchada'; return;
  end if;
  v_anchor := '                          and d.no_antes_de > v_min)), ''[]''::jsonb);';
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'el ancla no aparece exactamente una vez';
  end if;
  v_add := v_anchor || E'\n\n' ||
'  -- (a0b) v17.85 (Luis) -- RETENIDO A MANO: lo que un supervisor saco de su tanda con el boton
  --   "Enviar a programar" NO lo vuelve a agarrar el automatico. Queda en A Programar hasta que
  --   alguien lo programe a mano (gv_ppp_web_tanda_reusar, que lo devuelve a SU tanda de antes).
  --   Sin esto el cron de las zonas 1-3 (jobs 71 y 73, cada 15 min) lo reprograma solo en la
  --   corrida siguiente y el boton no sirve de nada: es lo que aviso Luis al pedirlo.
  p_filas := coalesce((
    select jsonb_agg(x)
      from jsonb_array_elements(p_filas) x
     where not exists (select 1 from public."GV_PPP_Web_Retenido" t
                        where t.empresa  = p_empresa
                          and t.order_id = (x->>''order_id'')::bigint
                          and t.np_idx   = (x->>''np_idx'')::int)), ''[]''::jsonb);';
  v_new := replace(v_def, v_anchor, v_add);
  execute v_new;
end $do$;

commit;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- drop function if exists public.gv_ppp_web_tanda_reusar(text,bigint,date,text);
-- drop view   if exists public.gv_ppp_web_retenido;
-- drop table  if exists public."GV_PPP_Web_Retenido";
-- -- y volver gv_ppp_web_desprogramar a la v15.55 (con el bloqueo por tanda tocada) y
-- -- gv_ppp_web_armar_pendientes a la copia de sql/backups/gv_ppp_web_armar_pendientes_pre_v1785.sql
