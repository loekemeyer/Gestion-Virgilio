-- gv_excedente_posicion — v31.59 (16/10/2026, Giuliana): DÓNDE está hoy cada excedente (neto por posición).
--
-- La zona P (y cualquier lugar de excedente) NO es una asignación fija: el código X está en PX
-- mientras tenga saldo ahí. Se calcula de Movimientos_Stock (deposito excedente):
--   * entradas/salidas CON ubicación → neto por (código, empresa, posición);
--   * salidas SIN ubicación (el picking no anota de qué posición sacó) → se descuentan de la
--     posición que el picking manda primero: la de MENOR orden del recorrido (GV_Lugar.orden).
--     O sea, el saldo que queda vive en las posiciones de MAYOR orden.
--   * lo que entró sin ubicación y no se puede ubicar sale con sector NULL («sin posición»).
-- Cuando el saldo de X en PX llega a 0, X deja de figurar en PX. Mismo corte (cutoff_ts) y misma
-- clave (clave = código canónico, «438E LK» en los duales) que vista_saldos_stock.
-- La leen: el picking (pkFetchExcedente, Gestión y Registro 3.0), el Mapa de góndolas (zona P) y
-- el pop-up de Excedente de Stocks.
-- Rollback: drop view public.gv_excedente_posicion;  (nadie depende de ella en la base)
create or replace view public.gv_excedente_posicion with (security_invoker = true) as
with cfg as (select (select valor from public."Stock_Config" where clave = 'cutoff_ts' limit 1) as cutoff),
m as (
  select upper(btrim(m.cod_art)) as c0, coalesce(m.empresa, 'Mixto') as emp, m.delta,
         upper(nullif(btrim(split_part(regexp_replace(coalesce(m.ubicacion, ''), '[|/,]', '·', 'g'), '·', 1)), '')) as u0
    from public."Movimientos_Stock" m, cfg
   where m.deposito = 'excedente'
     and (cfg.cutoff is null or m.tipo = 'inicial' or m.ts >= cfg.cutoff::timestamptz)
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
