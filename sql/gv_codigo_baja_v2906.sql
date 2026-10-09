-- v29.06 (Luis, 09/10/2026): un CÓDIGO DADO DE BAJA no aparece en el front ni recibe movimientos nuevos.
-- Caso 865ED: se unificó en 865E (12 u) el 07/10 (v27.74) y seguía en la tabla de Stocks con todo en 0.
-- La historia NO se toca (Luis: "no hace falta limpiarlo de todas las bases porque tiene registros históricos").
--
--  1) GV_Codigo_Baja (cod, reemplazo): la lista. Agregar otro = un insert.
--  2) gv_codigo_baja_de(cod) -> el reemplazo (anon; lo usa Stocks -> Ajustar/Fijar para frenar).
--  3) gv_stock_cod_conocido y refresh_stocks_carga_rapida (v_conocidos) lo tratan como desconocido:
--     visible_en_stock = false -> no sale en Stocks ni en la Est. Madre (sin saldo ni pedidos).
--  4) trigger aa_gv_codigo_baja en Movimientos_Stock: un movimiento NUEVO a mano con el código dado
--     de baja se graba con el reemplazo. No toca el pipeline (picking/separado/facturado, legajo
--     pipeline/sistema): reescribe historia por tanda y desviarlo partiría una fila en dos.
--
-- Rollback:
--   alter table public."Movimientos_Stock" disable trigger aa_gv_codigo_baja;
--   (las funciones: sacar la línea "v29.06-baja" con el mismo patrón de replace, al revés)

create table if not exists public."GV_Codigo_Baja" (
  cod        text primary key,
  reemplazo  text,
  desde      date not null default current_date,
  motivo     text,
  quien      text,
  creado     timestamptz not null default now()
);
alter table public."GV_Codigo_Baja" enable row level security;
revoke all on public."GV_Codigo_Baja" from anon, authenticated;

insert into public."GV_Codigo_Baja" (cod, reemplazo, desde, motivo, quien)
values ('865ED', '865E', date '2026-10-07', 'Unificado en 865E (12 u), v27.74', 'Luis')
on conflict (cod) do nothing;

create or replace function public.gv_codigo_baja_de(p_cod text)
returns text language sql stable security definer set search_path to 'public' as $f$
  -- v29.06-baja: el reemplazo de un código dado de baja (null = el código no está dado de baja)
  select coalesce(b.reemplazo, '')
    from public."GV_Codigo_Baja" b
   where upper(regexp_replace(b.cod,'^0+(?=.)','')) =
         upper(regexp_replace(regexp_replace(coalesce(p_cod,''),'\s+(LK|CH|LOKE)$','','i'),'^0+(?=.)',''))
$f$;
grant execute on function public.gv_codigo_baja_de(text) to anon, authenticated;

-- 3a) gv_stock_cod_conocido: un código dado de baja no es un artículo vivo
do $p$ declare d text; begin
  d := pg_get_functiondef('public.gv_stock_cod_conocido(text)'::regprocedure);
  if d ~ 'v29\.06-baja' then return; end if;
  if strpos(d, '  select exists(select 1 from public.vista_nombres_articulos v, k') = 0 then
    raise exception 'gv_stock_cod_conocido: no matchea el texto esperado'; end if;
  d := replace(d, '  select exists(select 1 from public.vista_nombres_articulos v, k',
    '  select not exists(select 1 from public."GV_Codigo_Baja" b, k   -- v29.06-baja
                     where upper(regexp_replace(b.cod,''^0+(?=.)'','''')) = k.c) and (
         exists(select 1 from public.vista_nombres_articulos v, k');
  d := regexp_replace(d, '(from public\."Insumos" v, k\s+where [^;]+= k\.c\));', '\1);');
  if d !~ '= k\.c\)\);' then raise exception 'gv_stock_cod_conocido: no cerró el paréntesis'; end if;
  execute d;
end $p$;

-- 3b) refresh_stocks_carga_rapida: v_conocidos sin los códigos dados de baja
do $p$ declare d text; v text := 'from public."Insumos") z where c is not null'; begin
  d := pg_get_functiondef('public.refresh_stocks_carga_rapida()'::regprocedure);
  if d ~ 'v29\.06-baja' then return; end if;
  if strpos(d, v) = 0 then raise exception 'refresh_stocks_carga_rapida: no matchea el texto esperado'; end if;
  d := replace(d, v, v || E'\n      and c <> all(array(select upper(regexp_replace(cod,''^0+(?=.)'','''')) from public."GV_Codigo_Baja")) /* v29.06-baja */');
  execute d;
end $p$;

-- 4) el trigger
create or replace function public.gv_codigo_baja_movimiento()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare v_rep text;
begin
  -- v29.06-baja
  if new.tipo in ('picking','separado','facturado') or coalesce(new.legajo,'') in ('pipeline','sistema') then
    return new; end if;
  v_rep := public.gv_codigo_baja_de(new.cod_art);
  if v_rep is null or v_rep = '' then return new; end if;
  new.descripcion := coalesce(nullif(new.descripcion,'') || ' · ', '') || 'cargado como ' || new.cod_art || ' (dado de baja) → ' || v_rep;
  new.cod_art := v_rep;
  return new;
end $f$;
create or replace trigger aa_gv_codigo_baja before insert on public."Movimientos_Stock"
  for each row execute function public.gv_codigo_baja_movimiento();

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_stock_cod_conocido','funcion','GV_Codigo_Baja','un código dado de baja (865ED) no es un artículo vivo: no sale en Stocks','Luis','v29.06'),
       ('refresh_stocks_carga_rapida','funcion','GV_Codigo_Baja','v_conocidos sin los códigos dados de baja (865ED -> visible_en_stock false)','Luis','v29.06');

select public.refresh_stocks_carga_rapida();

-- la lista entera para el front (importados: el buscador de «Modificar existente» no la ofrece)
create or replace function public.gv_codigos_baja()
returns table(cod text, reemplazo text) language sql stable security definer set search_path to 'public' as $f$
  -- v29.06-baja: la lista entera, para que el front no ofrezca un código dado de baja
  select b.cod, coalesce(b.reemplazo,'') from public."GV_Codigo_Baja" b order by 1
$f$;
grant execute on function public.gv_codigos_baja() to anon, authenticated;
