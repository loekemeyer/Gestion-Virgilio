-- v22.88 · Conciliación bancaria: mapeo de columnas POR AÑO (Thomas: "cargá todo lo que tengas")
-- Las hojas viejas no tienen las columnas donde las tiene 2026 (medido 25/09 sobre cada hoja).
-- GV_Conc_Columnas gana `anio`: 0 = el mapeo por defecto (el de 2026); una fila con el año pisa
-- ese campo para esa hoja; col NULL = ese campo no existe en esa hoja.
-- Rollback: delete from public."GV_Conc_Columnas" where anio <> 0; (y volver a la v22.87)

alter table public."GV_Conc_Columnas" add column if not exists anio int not null default 0;
alter table public."GV_Conc_Columnas" alter column col drop not null;
alter table public."GV_Conc_Columnas" drop constraint if exists "GV_Conc_Columnas_pkey";
alter table public."GV_Conc_Columnas" add primary key (banco, anio, campo);

insert into public."GV_Conc_Columnas" (banco, anio, campo, col)
select b, a, c, v from (values
 -- Credicoop LK 2022: no hay OP; el recibo viene como texto "Rc 5133"
 ('credicoop_lk',2022,'cod_cliente',7),('credicoop_lk',2022,'nro_recibo',8),('credicoop_lk',2022,'nro_op',null),
 ('credicoop_lk',2022,'observacion',9),('credicoop_lk',2022,'estado_echeq',10),('credicoop_lk',2022,'estado_isis',11),
 ('credicoop_lk',2022,'nota',12),
 -- Credicoop LK 2023: RC antes que OP
 ('credicoop_lk',2023,'nro_recibo',7),('credicoop_lk',2023,'nro_op',8),('credicoop_lk',2023,'cod_cliente',9),
 ('credicoop_lk',2023,'observacion',11),('credicoop_lk',2023,'estado_echeq',12),('credicoop_lk',2023,'estado_isis',13),
 ('credicoop_lk',2023,'nota',14),
 -- Santander LK 2022: sólo PROV/CTE
 ('santander_lk',2022,'cod_cliente',7),('santander_lk',2022,'nro_op',null),('santander_lk',2022,'nro_recibo',null),
 ('santander_lk',2022,'observacion',null),('santander_lk',2022,'estado_echeq',null),('santander_lk',2022,'estado_isis',null),
 -- Santander LK 2025: OP, recibo y cliente en columnas separadas
 ('santander_lk',2025,'nro_op',7),('santander_lk',2025,'nro_recibo',8),('santander_lk',2025,'cod_cliente',9),
 ('santander_lk',2025,'estado_echeq',null),('santander_lk',2025,'estado_isis',null),
 -- Credicoop Chef 2023: OP propia; col 8 notas
 ('credicoop_ch',2023,'nro_op',7),('credicoop_ch',2023,'nro_recibo',null),('credicoop_ch',2023,'cod_cliente',null),
 ('credicoop_ch',2023,'nota',8),('credicoop_ch',2023,'observacion',null),
 -- Credicoop Chef 2024
 ('credicoop_ch',2024,'nro_op',7),('credicoop_ch',2024,'nro_recibo',null),('credicoop_ch',2024,'cod_cliente',9),
 -- Credicoop Chef 2025: col 8 = planta (cervantes/virgilio…), col 9 = recibo
 ('credicoop_ch',2025,'nro_op',7),('credicoop_ch',2025,'nota',8),('credicoop_ch',2025,'nro_recibo',9),
 ('credicoop_ch',2025,'cod_cliente',null)
) v(b,a,c,v)
on conflict (banco, anio, campo) do nothing;

-- Credicoop Chef 2012-2022: sólo fecha/operación/importes/detalle/DET; col 7 = notas sueltas
insert into public."GV_Conc_Columnas" (banco, anio, campo, col)
select 'credicoop_ch', a, c, v from generate_series(2012,2022) a,
  (values ('nro_op',null::int),('nro_recibo',null),('cod_cliente',null),('observacion',null),('nota',7)) x(c,v)
on conflict (banco, anio, campo) do nothing;

drop function if exists public.gv_conc_parsear(text, jsonb);
create or replace function public.gv_conc_parsear(p_banco text, p_filas jsonb, p_anio int default null)
returns table (fila int, fecha date, operacion text, entrada numeric, salida numeric, saldo numeric,
               detalle text, det text, nro_op text, nro_recibo text, cod_cliente text,
               observacion text, estado_echeq text, estado_isis text, nota text)
language plpgsql stable set search_path = public as $$
declare m jsonb; mo jsonb;
begin
  select jsonb_object_agg(campo, col) into m from "GV_Conc_Columnas" where banco = p_banco and anio = 0;
  if m is null then raise exception 'banco desconocido: %', p_banco; end if;
  select jsonb_object_agg(campo, col) into mo from "GV_Conc_Columnas" where banco = p_banco and anio = p_anio;
  m := m || coalesce(mo, '{}'::jsonb);
  return query
  with raw as (
    select (e->>'fila')::int as f, e->'c' as c from jsonb_array_elements(p_filas) e
  ), v as (
    select r.f,
      gv_conc_fecha(r.c->>((m->>'fecha')::int))                        as fecha,
      gv_conc_txt(r.c->>((m->>'operacion')::int))                      as operacion,
      gv_conc_num(r.c->>((m->>'entrada')::int))                        as entrada,
      gv_conc_num(r.c->>((m->>'salida')::int))                         as salida,
      gv_conc_num(r.c->>((m->>'saldo')::int))                          as saldo,
      gv_conc_txt(r.c->>((m->>'detalle')::int))                        as detalle,
      gv_conc_cod(gv_conc_txt(r.c->>((m->>'det')::int)))               as det,
      gv_conc_cod(gv_conc_txt(r.c->>((m->>'nro_op')::int)))            as nro_op,
      gv_conc_cod(gv_conc_txt(r.c->>((m->>'nro_recibo')::int)))        as nro_recibo,
      gv_conc_cod(gv_conc_txt(r.c->>((m->>'cod_cliente')::int)))       as cod_cliente,
      gv_conc_txt(r.c->>((m->>'observacion')::int))                    as observacion,
      gv_conc_txt(r.c->>((m->>'estado_echeq')::int))                   as estado_echeq,
      gv_conc_txt(r.c->>((m->>'estado_isis')::int))                    as estado_isis,
      gv_conc_txt(r.c->>((m->>'nota')::int))                           as nota
    from raw r)
  select v.f, v.fecha, v.operacion, v.entrada, v.salida, v.saldo, v.detalle, v.det,
         case when m->>'nro_op' = m->>'nro_recibo' and v.entrada is not null then null else v.nro_op end,
         case when m->>'nro_op' = m->>'nro_recibo' and v.entrada is null     then null else v.nro_recibo end,
         v.cod_cliente, v.observacion, v.estado_echeq, v.estado_isis, v.nota
    from v
   where v.entrada is not null or v.salida is not null
      or v.operacion ~* '^\s*saldo\s+ini';
end $$;

-- gv_conc_cargar: misma función, ahora le pasa el año al parseo
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

  select count(*), sum(entrada), sum(salida) into v_n, v_ing, v_egr
    from gv_conc_parsear(p_banco, p_filas, p_anio);
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
      from public.gv_conc_parsear($2, $4, $1)$i$, v_tabla)
  using p_anio, p_banco, v_carga, p_filas;

  return jsonb_build_object('ok', true, 'banco', p_banco, 'anio', p_anio, 'filas', v_n,
                            'ingresos', v_ing, 'egresos', v_egr, 'carga_id', v_carga);
end $$;
