-- v22.87 · Conciliación bancaria → Supabase (Thomas, 25/09, tarea para Viviana)
--
-- Cuatro tablas, una por banco/empresa, con el MISMO formato legible:
--   GV_Conc_Credicoop_LK · GV_Conc_Santander_LK · GV_Conc_Credicoop_CH · GV_Conc_Santander_CH
-- y una vista que las junta para Cobranzas: gv_conciliacion_bancaria.
--
-- Cómo llega el dato: el Excel vive en una PC. La carga la hace una macro al guardar
-- (o cualquier cliente) llamando a gv_conc_cargar(banco, año, filas, archivo, token):
--   * manda las filas CRUDAS de la hoja: [{"fila":3,"c":[celda0, celda1, …]}, …]
--   * el mapeo columna→campo vive acá (GV_Conc_Columnas), no en la macro: si la planilla
--     cambia de forma se corrige un UPDATE, no la macro de cada PC.
--   * reemplaza el AÑO ENTERO de ese banco (las filas del Excel no tienen id propio;
--     una fila insertada en el medio corre a todas las de abajo).
--
-- Seguridad: las tablas tienen RLS; sólo supervisores leen. Nadie escribe directo:
-- sólo la RPC (SECURITY DEFINER), con sesión de supervisor o con el token de GV_Conc_Token.
--
-- Rollback:
--   drop view if exists public.gv_conciliacion_bancaria;
--   drop function if exists public.gv_conc_cargar(text,int,jsonb,text,text);
--   drop function if exists public.gv_conc_parsear(text,jsonb);
--   drop function if exists public.gv_conc_num(text), public.gv_conc_fecha(text),
--        public.gv_conc_txt(text), public.gv_conc_cod(text);
--   drop table if exists public."GV_Conc_Credicoop_LK", public."GV_Conc_Santander_LK",
--        public."GV_Conc_Credicoop_CH", public."GV_Conc_Santander_CH",
--        public."GV_Conc_Columnas", public."GV_Conc_Cargas", public."GV_Conc_Token";

-- ─── helpers de limpieza de celdas ────────────────────────────────────────────
create or replace function public.gv_conc_txt(v text) returns text
language sql immutable as $$
  -- vacío → null; las leyendas del Excel ("D=DEPOSITOS", "3=DEPOSITO CHEQUE…") no son datos
  select case when v is null or btrim(v) = '' then null
              when v ~ '^\s*[0-9A-Za-z .]{1,10}\s*=' then null
              else btrim(v) end $$;

create or replace function public.gv_conc_num(v text) returns numeric
language sql immutable as $$
  select case
    when v is null or btrim(v) = '' then null
    when btrim(v) ~ '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$' then round(btrim(v)::numeric, 2)
    -- texto con formato argentino: 1.234.567,89
    when btrim(v) ~ '^-?[0-9.]+,[0-9]+$' then round(replace(replace(btrim(v),'.',''),',','.')::numeric, 2)
    else null end $$;

create or replace function public.gv_conc_fecha(v text) returns date
language sql immutable as $$
  select case
    when v is null or btrim(v) = '' then null
    -- número de serie de Excel (lo que manda Value2)
    when btrim(v) ~ '^[0-9]{5}(\.[0-9]+)?$' then date '1899-12-30' + floor(btrim(v)::numeric)::int
    when btrim(v) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' then left(btrim(v),10)::date
    when btrim(v) ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then to_date(btrim(v),'DD/MM/YYYY')
    else null end $$;

create or replace function public.gv_conc_cod(v text) returns text
language sql immutable as $$
  -- códigos numéricos llegan como 1409.0 → '1409'
  select case when v is null or btrim(v) = '' then null
              when btrim(v) ~ '^[0-9]+\.0+$' then split_part(btrim(v),'.',1)
              else btrim(v) end $$;

-- ─── las cuatro tablas ────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['GV_Conc_Credicoop_LK','GV_Conc_Santander_LK',
                           'GV_Conc_Credicoop_CH','GV_Conc_Santander_CH'] loop
    execute format($f$
      create table if not exists public.%I (
        id            bigint generated always as identity primary key,
        anio          int  not null,                 -- hoja "CONCILIACION <año>"
        fila          int  not null,                 -- nº de fila en la hoja (1 = primera)
        fecha         date,
        operacion     text,                          -- "Operación / Cheque Nº": Deposito, Transf, A Depositar…
        entrada       numeric(18,2),
        salida        numeric(18,2),
        saldo         numeric(18,2),
        detalle       text,                          -- cliente / proveedor / concepto
        det           text,                          -- código DET: D, 3, T, G, S, TB, SI…
        nro_op        text,                          -- orden de pago (egresos)
        nro_recibo    text,                          -- recibo (ingresos)
        cod_cliente   text,                          -- código de cliente/proveedor en ISIS de ESA empresa
        observacion   text,                          -- "Electronico" (e-cheq) o nota libre
        estado_echeq  text,                          -- "Aceptado 20/07"
        estado_isis   text,                          -- "Pasado a Isis"
        nota          text,
        tipo          text generated always as (
          case when operacion ~* '^\s*saldo\s+ini' or upper(coalesce(det,'')) = 'SI' then 'saldo_inicial'
               when operacion ~* '^\s*a\s+depositar' then 'a_depositar'
               when operacion ~* '^\s*proyecc'       then 'proyeccion'
               when entrada is not null              then 'ingreso'
               else 'egreso' end) stored,
        carga_id      bigint,
        cargado_en    timestamptz not null default now(),
        unique (anio, fila)
      )$f$, t);
    execute format('create index if not exists %I on public.%I (cod_cliente, fecha)', t||'_cli_idx', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
    execute format('drop policy if exists sup_lee on public.%I', t);
    execute format('create policy sup_lee on public.%I for select to authenticated using (public.es_supervisor_virgilio())', t);
  end loop;
end $$;

-- ─── mapeo columna → campo (0 = columna A) ────────────────────────────────────
create table if not exists public."GV_Conc_Columnas" (
  banco text not null, campo text not null, col int not null,
  primary key (banco, campo));
alter table public."GV_Conc_Columnas" enable row level security;
revoke insert, update, delete, truncate on public."GV_Conc_Columnas" from anon, authenticated;
drop policy if exists sup_lee on public."GV_Conc_Columnas";
create policy sup_lee on public."GV_Conc_Columnas" for select to authenticated using (public.es_supervisor_virgilio());

-- medido sobre los Excel del 25/09/2026, hoja 2026.
-- En Santander LK y Credicoop Chef la MISMA columna es OP (egresos) y recibo (ingresos).
insert into public."GV_Conc_Columnas" (banco, campo, col) values
 ('credicoop_lk','fecha',0),('credicoop_lk','operacion',1),('credicoop_lk','entrada',2),('credicoop_lk','salida',3),
 ('credicoop_lk','saldo',4),('credicoop_lk','detalle',5),('credicoop_lk','det',6),('credicoop_lk','nro_op',7),
 ('credicoop_lk','nro_recibo',8),('credicoop_lk','cod_cliente',9),('credicoop_lk','observacion',11),
 ('credicoop_lk','estado_echeq',12),('credicoop_lk','estado_isis',13),('credicoop_lk','nota',14),
 ('santander_lk','fecha',0),('santander_lk','operacion',1),('santander_lk','entrada',2),('santander_lk','salida',3),
 ('santander_lk','saldo',4),('santander_lk','detalle',5),('santander_lk','det',6),('santander_lk','nro_op',7),
 ('santander_lk','nro_recibo',7),('santander_lk','cod_cliente',8),('santander_lk','observacion',10),
 ('santander_lk','estado_echeq',11),('santander_lk','estado_isis',12),
 ('credicoop_ch','fecha',0),('credicoop_ch','operacion',1),('credicoop_ch','entrada',2),('credicoop_ch','salida',3),
 ('credicoop_ch','saldo',4),('credicoop_ch','detalle',5),('credicoop_ch','det',6),('credicoop_ch','nro_op',7),
 ('credicoop_ch','nro_recibo',7),('credicoop_ch','cod_cliente',8),('credicoop_ch','observacion',10),
 ('santander_ch','fecha',0),('santander_ch','operacion',1),('santander_ch','entrada',2),('santander_ch','salida',3),
 ('santander_ch','saldo',4),('santander_ch','detalle',5),('santander_ch','det',6),('santander_ch','nro_op',7),
 ('santander_ch','nro_recibo',8),('santander_ch','cod_cliente',9),('santander_ch','observacion',10),
 ('santander_ch','estado_echeq',11),('santander_ch','estado_isis',12),('santander_ch','nota',13)
on conflict (banco, campo) do nothing;

-- ─── log de cargas y token de la macro ────────────────────────────────────────
create table if not exists public."GV_Conc_Cargas" (
  id bigint generated always as identity primary key,
  banco text not null, anio int not null, archivo text,
  filas int, ingresos numeric(18,2), egresos numeric(18,2),
  por text, cargado_en timestamptz not null default now());
alter table public."GV_Conc_Cargas" enable row level security;
revoke insert, update, delete, truncate on public."GV_Conc_Cargas" from anon, authenticated;
drop policy if exists sup_lee on public."GV_Conc_Cargas";
create policy sup_lee on public."GV_Conc_Cargas" for select to authenticated using (public.es_supervisor_virgilio());

create table if not exists public."GV_Conc_Token" (
  id int primary key default 1 check (id = 1),
  token text not null default gen_random_uuid()::text,
  creado_en timestamptz not null default now());
alter table public."GV_Conc_Token" enable row level security;   -- sin policies: nadie lo lee por la API
revoke all on public."GV_Conc_Token" from anon, authenticated;
insert into public."GV_Conc_Token" (id) values (1) on conflict do nothing;

-- ─── parseo (no escribe: sirve para probar el mapeo) ──────────────────────────
create or replace function public.gv_conc_parsear(p_banco text, p_filas jsonb)
returns table (fila int, fecha date, operacion text, entrada numeric, salida numeric, saldo numeric,
               detalle text, det text, nro_op text, nro_recibo text, cod_cliente text,
               observacion text, estado_echeq text, estado_isis text, nota text)
language plpgsql stable set search_path = public as $$
declare m jsonb;
begin
  select jsonb_object_agg(campo, col) into m from "GV_Conc_Columnas" where banco = p_banco;
  if m is null then raise exception 'banco desconocido: %', p_banco; end if;
  return query
  with raw as (
    select (e->>'fila')::int as f, e->'c' as c from jsonb_array_elements(p_filas) e
  ), v as (
    select r.f,
      gv_conc_fecha(r.c->>(m->>'fecha')::int)                         as fecha,
      gv_conc_txt(r.c->>(m->>'operacion')::int)                       as operacion,
      gv_conc_num(r.c->>(m->>'entrada')::int)                         as entrada,
      gv_conc_num(r.c->>(m->>'salida')::int)                          as salida,
      gv_conc_num(r.c->>(m->>'saldo')::int)                           as saldo,
      gv_conc_txt(r.c->>(m->>'detalle')::int)                         as detalle,
      gv_conc_cod(gv_conc_txt(r.c->>(m->>'det')::int))                as det,
      gv_conc_cod(gv_conc_txt(r.c->>(m->>'nro_op')::int))             as nro_op,
      gv_conc_cod(gv_conc_txt(r.c->>(m->>'nro_recibo')::int))         as nro_recibo,
      gv_conc_cod(gv_conc_txt(r.c->>(m->>'cod_cliente')::int))        as cod_cliente,
      gv_conc_txt(r.c->>(m->>'observacion')::int)                     as observacion,
      gv_conc_txt(r.c->>((m->>'estado_echeq')::int))                  as estado_echeq,
      gv_conc_txt(r.c->>((m->>'estado_isis')::int))                   as estado_isis,
      gv_conc_txt(r.c->>((m->>'nota')::int))                          as nota
    from raw r)
  select v.f, v.fecha, v.operacion, v.entrada, v.salida, v.saldo, v.detalle, v.det,
         -- misma columna para OP y recibo: se reparte según sea ingreso o egreso
         case when m->>'nro_op' = m->>'nro_recibo' and v.entrada is not null then null else v.nro_op end,
         case when m->>'nro_op' = m->>'nro_recibo' and v.entrada is null     then null else v.nro_recibo end,
         v.cod_cliente, v.observacion, v.estado_echeq, v.estado_isis, v.nota
    from v
   -- sólo movimientos y el saldo inicial; los renglones de título, totales y vacíos no
   where v.entrada is not null or v.salida is not null
      or v.operacion ~* '^\s*saldo\s+ini';
end $$;

-- ─── carga: reemplaza el año entero de ese banco ──────────────────────────────
create or replace function public.gv_conc_cargar(p_banco text, p_anio int, p_filas jsonb,
                                                 p_archivo text default null, p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tabla text := case p_banco when 'credicoop_lk' then 'GV_Conc_Credicoop_LK'
                               when 'santander_lk' then 'GV_Conc_Santander_LK'
                               when 'credicoop_ch' then 'GV_Conc_Credicoop_CH'
                               when 'santander_ch' then 'GV_Conc_Santander_CH' end;
  v_por text; v_carga bigint; v_n int; v_ing numeric; v_egr numeric;
begin
  if v_tabla is null then raise exception 'banco desconocido: %', p_banco; end if;
  if p_anio is null or p_anio < 2012 or p_anio > 2100 then raise exception 'año inválido: %', p_anio; end if;
  if jsonb_typeof(p_filas) <> 'array' then raise exception 'p_filas tiene que ser un array'; end if;

  if public.es_supervisor_virgilio() then
    v_por := coalesce(auth.jwt()->>'email', 'supervisor');
  elsif p_token is not null and exists (select 1 from "GV_Conc_Token" where token = p_token) then
    v_por := 'macro';
  else
    raise exception 'sin permiso para cargar la conciliación';
  end if;

  -- un Excel vacío o mal leído no puede borrar el año: tiene que traer movimientos
  select count(*), sum(entrada), sum(salida) into v_n, v_ing, v_egr
    from gv_conc_parsear(p_banco, p_filas);
  if v_n = 0 then raise exception 'el archivo no trae movimientos: no se cargó nada'; end if;

  perform pg_advisory_xact_lock(hashtext('gv_conc_' || p_banco || p_anio));

  insert into "GV_Conc_Cargas" (banco, anio, archivo, filas, ingresos, egresos, por)
  values (p_banco, p_anio, p_archivo, v_n, v_ing, v_egr, v_por) returning id into v_carga;

  execute format('delete from public.%I where anio = $1', v_tabla) using p_anio;
  execute format($i$
    insert into public.%I (anio, fila, fecha, operacion, entrada, salida, saldo, detalle, det,
                           nro_op, nro_recibo, cod_cliente, observacion, estado_echeq, estado_isis, nota, carga_id)
    select $1, fila, fecha, operacion, entrada, salida, saldo, detalle, det,
           nro_op, nro_recibo, cod_cliente, observacion, estado_echeq, estado_isis, nota, $3
      from public.gv_conc_parsear($2, $4)$i$, v_tabla)
  using p_anio, p_banco, v_carga, p_filas;

  return jsonb_build_object('ok', true, 'banco', p_banco, 'anio', p_anio, 'filas', v_n,
                            'ingresos', v_ing, 'egresos', v_egr, 'carga_id', v_carga);
end $$;
revoke all on function public.gv_conc_cargar(text,int,jsonb,text,text) from public;
grant execute on function public.gv_conc_cargar(text,int,jsonb,text,text) to anon, authenticated;

-- ─── vista para Cobranzas ─────────────────────────────────────────────────────
create or replace view public.gv_conciliacion_bancaria with (security_invoker = true) as
  select 'credicoop'::text banco, 'lk'::text empresa, t.* from public."GV_Conc_Credicoop_LK" t
  union all select 'santander', 'lk',   t.* from public."GV_Conc_Santander_LK" t
  union all select 'credicoop', 'chef', t.* from public."GV_Conc_Credicoop_CH" t
  union all select 'santander', 'chef', t.* from public."GV_Conc_Santander_CH" t;
revoke all on public.gv_conciliacion_bancaria from anon;
grant select on public.gv_conciliacion_bancaria to authenticated;

-- ─── cierre de permisos (aplicado después, mismo día) ─────────────────────────
revoke all on public."GV_Conc_Credicoop_LK", public."GV_Conc_Santander_LK", public."GV_Conc_Credicoop_CH",
              public."GV_Conc_Santander_CH", public."GV_Conc_Columnas", public."GV_Conc_Cargas" from anon;
revoke insert, update, delete, truncate on public.gv_conciliacion_bancaria from authenticated;

-- Verificado 25/09: gv_conc_parsear con filas reales de los 4 Excel mapea bien cada campo;
-- anon sin token → 'sin permiso para cargar la conciliación'. Las tablas quedan VACÍAS
-- hasta la primera carga.
