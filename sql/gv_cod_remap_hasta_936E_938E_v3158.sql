-- v31.58 · proyecto Gestión (hrxfctzncixxqmpfhskv) · Luis, 16/10/2026 (D3)
-- «fueron pedidos para el 936E pero deberían pesar para el 938E hasta hoy».
-- Mismo criterio que sales_item_remap_hasta en LK (sql/lk_remap_hasta_936E_938E_v3155.sql), del lado de los
-- PEDIDOS: lo pedido como from_code antes de `hasta` cuenta como to_code en las ESTADÍSTICAS (no en el pedido:
-- picking, factura y PPP siguen con el código del pedido). Lo usan:
--   gv_pedidos_mensuales_cod            (columna «pedidos» del pop-up de Proyección)
--   gv_isis_estad_pedidos               (Pedidos LK/CH, manual 31, bajada de la Est. Madre)
--   gv_isis_estad_pedidos_disruptivos   (historia web y de facturas ISIS de los disruptivos)
-- Se aplica sobre la definición VIVA con replace() + chequeo de que cada ancla aparezca UNA vez.
-- Rollback: quitar el envoltorio public.gv_cod_remap_hasta(<expr>, <fecha>) de las 3 funciones (definición viva),
-- o vaciar la tabla: con GV_Cod_Remap_Hasta sin filas la función devuelve el código igual.

create table if not exists public."GV_Cod_Remap_Hasta" (
  from_code text not null,
  to_code   text not null,
  hasta     date not null,          -- lo pedido con fecha < hasta va a to_code
  motivo    text,
  creado    timestamptz not null default now(),
  primary key (from_code, hasta)
);
alter table public."GV_Cod_Remap_Hasta" enable row level security;
revoke all on public."GV_Cod_Remap_Hasta" from anon, authenticated;

insert into public."GV_Cod_Remap_Hasta" (from_code, to_code, hasta, motivo)
values ('936E', '938E', date '2026-10-16', 'Luis 16/10/2026: los pedidos del 936E hasta el 15/10 pesan para el 938E')
on conflict (from_code, hasta) do nothing;

-- 936E → 938E, 936EL → 938EL; cualquier otro código (o fecha ≥ hasta) vuelve igual.
create or replace function public.gv_cod_remap_hasta(p_cod text, p_fecha date)
returns text language sql stable set search_path to 'public', 'pg_temp' as $f$
  select coalesce((select case when n.l then r.to_code || 'L' else r.to_code end
                     from public."GV_Cod_Remap_Hasta" r
                    where r.from_code = n.base and p_fecha < r.hasta
                    order by r.hasta limit 1), p_cod)
    from (select regexp_replace(regexp_replace(upper(btrim(coalesce(p_cod, ''))), '^0+(?=.)', ''), '([0-9E])L$', '\1') base,
                 upper(btrim(coalesce(p_cod, ''))) ~ '[0-9E]L$' l) n
$f$;
revoke execute on function public.gv_cod_remap_hasta(text, date) from anon;

do $do$
declare
  r record;
  d text;
  n int;
  fn_act text;
begin
  for r in
    select * from (values
      ('gv_pedidos_mensuales_cod(text,integer,text)',
       $a$regexp_replace(regexp_replace(regexp_replace(regexp_replace($a$,
       $b$public.gv_cod_remap_hasta(regexp_replace(regexp_replace(regexp_replace(regexp_replace($b$),
      ('gv_pedidos_mensuales_cod(text,integer,text)',
       $a$'([0-9E])L$', '\1') as cod,$a$,
       $b$'([0-9E])L$', '\1'), m.fecha_pedido::date) as cod,$b$),
      ('gv_isis_estad_pedidos(text,date,date)',
       $a$select regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', '') cod,$a$,
       $b$select public.gv_cod_remap_hasta(regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', ''), m.fecha_pedido::date) cod,$b$),
      ('gv_isis_estad_pedidos_disruptivos(text,date,date)',
       $a$regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', '') cod, (z.r[2])::numeric cajas$a$,
       $b$public.gv_cod_remap_hasta(regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', ''), m.fecha_pedido::date) cod, (z.r[2])::numeric cajas$b$),
      ('gv_isis_estad_pedidos_disruptivos(text,date,date)',
       $a$upper(btrim(fi.codigo_articulo)) cod, fd.id pedido$a$,
       $b$public.gv_cod_remap_hasta(upper(btrim(fi.codigo_articulo)), fd.fecha::date) cod, fd.id pedido$b$)
    ) v(fn, a, b)
    order by fn
  loop
    if r.fn is distinct from fn_act then
      if fn_act is not null and d is distinct from pg_get_functiondef(fn_act::regprocedure) then execute d; end if;
      fn_act := r.fn;
      d := pg_get_functiondef(r.fn::regprocedure);
    end if;
    if position(r.b in d) > 0 then continue; end if;   -- ya aplicado
    n := (length(d) - length(replace(d, r.a, ''))) / length(r.a);
    if n <> 1 then
      raise exception 'v31.58: el ancla aparece % veces en % (se esperaba 1): %', n, r.fn, r.a;
    end if;
    d := replace(d, r.a, r.b);
  end loop;
  if fn_act is not null and d is distinct from pg_get_functiondef(fn_act::regprocedure) then execute d; end if;
end $do$;
