-- REGLA_CONFIRMADA_POR_USUARIO
-- gv_excedente_cartel — v31.82 (16/10/2026, Luis): el excedente SIN posición registrada se registra con el cartel.
--
-- Luis: "Todos los articulos que tienen excedentes ya deberían tener registrada la gondola donde esta el excedente.
-- Si hay alguno que tiene excedente y no esta registrado, que le pida al operario marcar en qué gondola esta el
-- excedente (en que gondola dice el cartel que esta y que, cuando llegue ahi, confirme si esta o no)".
--
-- El picking, en un paso de excedente sin posición, pregunta la posición del cartel; cuando el operario llega y
-- confirma que está, el PKC lleva un 8º campo con esa posición. Este trigger la guarda en
-- GV_Excedente_Ubic_Declarada (una por código, la última) y gv_excedente_posicion pone ahí el saldo que no se
-- podía ubicar (antes salía con sector NULL). No toca Movimientos_Stock: el saldo por código es el mismo.
-- Al 16/10: 0 códigos sin posición, pero 120 ajustes de excedente entraron sin ubicación en 60 días.
-- Sobre sql/gv_excedente_pick_pos_v3180.sql (rollback: volver a correr ese archivo).

create table if not exists public."GV_Excedente_Ubic_Declarada" (
  cod         text primary key,      -- normalizado como reconciliar_stock_articulo_rt (equivalencia, sin ceros)
  sector      text not null,         -- P13 (formato de GV_Lugar)
  tanda       text,
  legajo      text,
  client_id   text,
  actualizado timestamptz not null default now()
);
alter table public."GV_Excedente_Ubic_Declarada" enable row level security;
do $p$ begin
  if not exists (select 1 from pg_policies where tablename = 'GV_Excedente_Ubic_Declarada' and policyname = 'exc_ubic_decl_sel') then
    create policy exc_ubic_decl_sel on public."GV_Excedente_Ubic_Declarada" for select to anon, authenticated using (true);
  end if;
end $p$;
grant select on public."GV_Excedente_Ubic_Declarada" to anon, authenticated;

create or replace function public.trg_gv_exc_pick_pos()
returns trigger language plpgsql security definer set search_path = public as $f$
declare
  v_f7 text; v_f8 text; v_tanda text; v_cod text; v_pos jsonb := '{}'::jsonb; v_par text; v_s text; v_n numeric;
begin
  -- v31.78-exc-pick-pos · v31.82-exc-cartel (8º campo = posición que dice el cartel, confirmada por el operario)
  v_f7 := btrim(split_part(coalesce(new.texto, ''), '|', 7));
  v_f8 := upper(btrim(split_part(coalesce(new.texto, ''), '|', 8)));
  if v_f7 = '' and v_f8 = '' then return new; end if;
  v_tanda := upper(btrim(split_part(new.texto, '|', 1)));
  v_cod := regexp_replace(upper(btrim(coalesce(
             (select e.cod_real from public."Equivalencias_Codigos" e
               where regexp_replace(upper(btrim(e.cod_pedido)), '^0+(?=.)', '')
                   = regexp_replace(upper(btrim(split_part(new.texto, '|', 2))), '^0+(?=.)', '') limit 1),
             split_part(new.texto, '|', 2)))), '^0+(?=.)', '');
  if v_tanda = '' or v_cod = '' then return new; end if;
  if v_f8 ~ '^[A-ZÑ]{1,2}0*[0-9]{1,3}(AD|AT)?$' then
    v_s := substring(v_f8 from '^([A-ZÑ]{1,2})')
           || lpad(regexp_replace(substring(v_f8 from '^[A-ZÑ]{1,2}([0-9]{1,3})'), '^0+(?=.)', ''), 2, '0')
           || coalesce(substring(v_f8 from '[0-9](AD|AT)$'), '');
    insert into public."GV_Excedente_Ubic_Declarada" (cod, sector, tanda, legajo, client_id, actualizado)
    values (v_cod, v_s, v_tanda, new.legajo::text, new.client_id, now())
    on conflict (cod) do update set sector = excluded.sector, tanda = excluded.tanda, legajo = excluded.legajo,
                                    client_id = excluded.client_id, actualizado = now();
  end if;
  if v_f7 = '' then return new; end if;
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
  return new;   -- nunca frena el PKC
end
$f$;

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
  -- v31.82-exc-cartel: lo que no se puede ubicar va a la posición que el operario leyó en el cartel
  -- (GV_Excedente_Ubic_Declarada, la última). Sin declaración, sector NULL como siempre.
  select tt.ckey, tt.emp, dd.sector, l.orden,
         tt.total - coalesce((select sum(a.cajas) from alloc a where a.ckey = tt.ckey and a.emp = tt.emp), 0) as cajas
    from tot tt
    left join public."GV_Excedente_Ubic_Declarada" dd on dd.cod = regexp_replace(tt.ckey, '^0+(?=.)', '')
    left join public."GV_Lugar" l on upper(btrim(l.sector)) = dd.sector and l.activo
)
select x.ckey as cod,
       case when x.emp in ('LK', 'CH') and exists (select 1 from public.codigos_duales d
              where regexp_replace(upper(btrim(d.cod)), '^0+(?=.)', '') = regexp_replace(x.ckey, '^0+(?=.)', ''))
            then x.ckey || ' ' || x.emp else x.ckey end as clave,
       x.emp as empresa, x.sector, x.orden, x.cajas
  from (select y.ckey, y.emp, y.sector, min(y.orden) as orden, sum(y.cajas) as cajas
          from (select ckey, emp, sector, orden, cajas from alloc where cajas > 0
                union all
                select ckey, emp, sector, orden, cajas from sinpos where cajas > 0.0001) y
         group by y.ckey, y.emp, y.sector) x
;
grant select on public.gv_excedente_posicion to anon, authenticated;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version, activo)
select 'gv_excedente_posicion', 'vista', 'GV_Excedente_Ubic_Declarada',
       'El excedente que no se puede ubicar va a la posición que el operario leyó en el cartel y confirmó en el picking',
       'Luis', 'v31.82', true
 where not exists (select 1 from public."GV_Reglas_Centinela" where objeto = 'gv_excedente_posicion' and patron = 'GV_Excedente_Ubic_Declarada');
