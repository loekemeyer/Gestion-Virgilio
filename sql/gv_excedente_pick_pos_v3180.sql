-- gv_excedente_pick_pos — v31.80 (16/10/2026, Luis): DE QUÉ POSICIÓN sacó el operario el excedente.
--
-- Luis: "cuando un operario tiene que pickear un articulo que esta en excedente y esta en mas de una
-- gondola en excedente, que le pregunte al operario de donde lo sacó. esto es con el fin de identificar
-- cuando las gondolas se vacian para liberarlas en el mapa".
--
-- Hasta la v31.77 la salida de excedente del picking (Movimientos_Stock tipo 'picking', la escribe
-- reconciliar_stock_articulo_rt) va SIN ubicación, y gv_excedente_posicion la descontaba de la posición
-- de MENOR orden: si el operario sacaba de otra, el Mapa seguía mostrando ocupada la que vació.
--
-- Ahora el picking (Gestión y Registro 3.0), cuando el excedente del artículo está en 2+ posiciones,
-- pregunta de cuál sacó y lo manda en el 7º campo del PKC:
--   'tanda|codigo|esperadas|reales|excedente|empresa|P18:3;P22:2'
-- Este trigger lo guarda en GV_Excedente_Pick_Pos (una fila por tanda+código) y la vista reparte la
-- salida del picking de esa tanda entre las posiciones declaradas (lo que sobre, como antes: sin
-- ubicación → la de menor orden). NO toca el movimiento ni reconciliar_stock_articulo_rt: el saldo de
-- excedente por código sigue siendo exactamente el mismo; sólo cambia en qué posición vive.
--
-- Rollback: restaurar la vista de sql/gv_excedente_posicion_v3159.sql y
--   quitar el trigger trg_gv_exc_pick_pos de public."Registros_Produccion_Virgilio";

create table if not exists public."GV_Excedente_Pick_Pos" (
  tanda       text not null,
  cod         text not null,          -- normalizado como reconciliar_stock_articulo_rt (equivalencia, sin ceros)
  posiciones  jsonb not null,         -- {"P18": 3, "P22": 2}
  legajo      text,
  client_id   text,
  actualizado timestamptz not null default now(),
  primary key (tanda, cod)
);
alter table public."GV_Excedente_Pick_Pos" enable row level security;
do $p$ begin
  if not exists (select 1 from pg_policies where tablename = 'GV_Excedente_Pick_Pos' and policyname = 'exc_pick_pos_sel') then
    create policy exc_pick_pos_sel on public."GV_Excedente_Pick_Pos" for select to anon, authenticated using (true);
  end if;
end $p$;
grant select on public."GV_Excedente_Pick_Pos" to anon, authenticated;

create or replace function public.trg_gv_exc_pick_pos()
returns trigger language plpgsql security definer set search_path = public as $f$
declare
  v_f7 text; v_tanda text; v_cod text; v_pos jsonb := '{}'::jsonb; v_par text; v_s text; v_n numeric;
begin
  -- v31.80-exc-pick-pos
  v_f7 := btrim(split_part(coalesce(new.texto, ''), '|', 7));
  if v_f7 = '' then return new; end if;
  v_tanda := upper(btrim(split_part(new.texto, '|', 1)));
  v_cod := regexp_replace(upper(btrim(coalesce(
             (select e.cod_real from public."Equivalencias_Codigos" e
               where regexp_replace(upper(btrim(e.cod_pedido)), '^0+(?=.)', '')
                   = regexp_replace(upper(btrim(split_part(new.texto, '|', 2))), '^0+(?=.)', '') limit 1),
             split_part(new.texto, '|', 2)))), '^0+(?=.)', '');
  if v_tanda = '' or v_cod = '' then return new; end if;
  foreach v_par in array string_to_array(v_f7, ';') loop
    v_s := upper(btrim(split_part(v_par, ':', 1)));
    v_n := case when btrim(split_part(v_par, ':', 2)) ~ '^[0-9]+(\.[0-9]+)?$' then btrim(split_part(v_par, ':', 2))::numeric end;
    if v_s ~ '^[A-ZÑ]{1,2}0*[0-9]{1,3}(AD|AT)?$' and v_n > 0 then
      v_s := substring(v_s from '^([A-ZÑ]{1,2})')
             || lpad(regexp_replace(substring(v_s from '^[A-ZÑ]{1,2}([0-9]{1,3})'), '^0+(?=.)', ''), 2, '0')
             || coalesce(substring(v_s from '[0-9](AD|AT)$'), '');
      v_pos := v_pos || jsonb_build_object(v_s, coalesce((v_pos->>v_s)::numeric, 0) + v_n);
    end if;
  end loop;
  if v_pos = '{}'::jsonb then return new; end if;
  insert into public."GV_Excedente_Pick_Pos" (tanda, cod, posiciones, legajo, client_id, actualizado)
  values (v_tanda, v_cod, v_pos, new.legajo::text, new.client_id, now())
  on conflict (tanda, cod) do update set posiciones = excluded.posiciones, legajo = excluded.legajo,
                                         client_id = excluded.client_id, actualizado = now();
  return new;
exception when others then
  return new;   -- nunca frena el PKC: sin la declaración, la vista reparte como antes
end
$f$;

create or replace trigger trg_gv_exc_pick_pos
  after insert or update of texto on public."Registros_Produccion_Virgilio"
  for each row when (new.opcion = 'PKC') execute function public.trg_gv_exc_pick_pos();

create or replace view public.gv_excedente_posicion with (security_invoker = true) as
with cfg as (select (select valor from public."Stock_Config" where clave = 'cutoff_ts' limit 1) as cutoff),
m0 as (
  select m.id, m.cod_art, coalesce(m.empresa, 'Mixto') as emp, m.delta, m.tipo, m.ref,
         upper(nullif(btrim(split_part(regexp_replace(coalesce(m.ubicacion, ''), '[|/,]', '·', 'g'), '·', 1)), '')) as u0
    from public."Movimientos_Stock" m, cfg
   where m.deposito = 'excedente'
     and (cfg.cutoff is null or m.tipo = 'inicial' or m.ts >= cfg.cutoff::timestamptz)
),
-- v31.80-exc-pick-pos: la salida del picking SIN ubicación se reparte entre las posiciones que declaró
-- el operario (GV_Excedente_Pick_Pos), hasta lo que salió. Lo que sobre sigue sin ubicación.
dec as (
  select m0.id, d.key as sector, d.value::numeric as caj,
         coalesce(sum(d.value::numeric) over (partition by m0.id order by d.key
                  rows between unbounded preceding and 1 preceding), 0) as antes
    from m0
    join public."GV_Excedente_Pick_Pos" p
      on p.tanda = upper(btrim(m0.ref))
     and p.cod = regexp_replace(upper(btrim(m0.cod_art)), '^0+(?=.)', '')
    cross join lateral jsonb_each_text(p.posiciones) d
   where m0.tipo = 'picking' and m0.delta < 0 and m0.u0 is null
     and d.value ~ '^[0-9]+(\.[0-9]+)?$'
),
decq as (select d.id, d.sector, greatest(0, least(d.caj, -m0.delta - d.antes)) as q
           from dec d join m0 on m0.id = d.id),
m as (
  select upper(btrim(m0.cod_art)) as c0, m0.emp, m0.delta + coalesce((select sum(q) from decq where decq.id = m0.id), 0) as delta, m0.u0
    from m0
  union all
  select upper(btrim(m0.cod_art)), m0.emp, -q.q, q.sector
    from decq q join m0 on m0.id = q.id
   where q.q > 0
),
k as (
  select case when c0 ~ '^[0-9]+$' then
              case when length(regexp_replace(c0, '^0+(?=.)', '')) >= 3 then regexp_replace(c0, '^0+(?=.)', '')
                   else lpad(regexp_replace(c0, '^0+(?=.)', ''), 3, '0') end
         else c0 end as ckey,
         emp, delta,
         case when u0 ~ '^[A-ZÑ]{1,2}0*[0-9]{1,3}(AD|AT)?$' then
              substring(u0 from '^([A-ZÑ]{1,2})')
              || lpad(regexp_replace(substring(u0 from '^[A-ZÑ]{1,2}([0-9]{1,3})'), '^0+(?=.)', ''), 2, '0')
              || coalesce(substring(u0 from '[0-9](AD|AT)$'), '')
         end as sector
    from m
),
tot as (select ckey, emp, sum(delta) as total from k group by 1, 2),
tag as (select ckey, emp, sector, sum(delta) as neto from k where sector is not null group by 1, 2, 3 having sum(delta) > 0),
ord as (
  select t.ckey, t.emp, t.sector, t.neto, l.orden
    from tag t left join public."GV_Lugar" l on upper(btrim(l.sector)) = t.sector and l.activo
),
alloc as (
  select o.ckey, o.emp, o.sector, o.orden, o.neto, tt.total,
         greatest(0, least(o.neto, greatest(tt.total, 0)
           - coalesce(sum(o.neto) over (partition by o.ckey, o.emp
                                        order by coalesce(o.orden, -1) desc, o.sector desc
                                        rows between unbounded preceding and 1 preceding), 0))) as cajas
    from ord o join tot tt using (ckey, emp)
),
sinpos as (
  select tt.ckey, tt.emp, null::text as sector, null::integer as orden,
         tt.total - coalesce((select sum(a.cajas) from alloc a where a.ckey = tt.ckey and a.emp = tt.emp), 0) as cajas
    from tot tt
)
select x.ckey as cod,
       case when x.emp in ('LK', 'CH') and exists (select 1 from public.codigos_duales d
              where regexp_replace(upper(btrim(d.cod)), '^0+(?=.)', '') = regexp_replace(x.ckey, '^0+(?=.)', ''))
            then x.ckey || ' ' || x.emp else x.ckey end as clave,
       x.emp as empresa, x.sector, x.orden, x.cajas
  from (select ckey, emp, sector, orden, cajas from alloc where cajas > 0
        union all
        select ckey, emp, sector, orden, cajas from sinpos where cajas > 0.0001) x
;
grant select on public.gv_excedente_posicion to anon, authenticated;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version, activo)
select 'gv_excedente_posicion', 'vista', 'GV_Excedente_Pick_Pos',
       'La salida de excedente del picking se reparte entre las posiciones que declaró el operario (no siempre la de menor orden)',
       'Luis', 'v31.80', true
 where not exists (select 1 from public."GV_Reglas_Centinela" where objeto = 'gv_excedente_posicion' and patron = 'GV_Excedente_Pick_Pos');
