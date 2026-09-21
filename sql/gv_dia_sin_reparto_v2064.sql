-- v20.64 — DÍA SIN REPARTO: el armado sigue, el camión no sale
--
-- Luis, 2026-09-21: *"hace que la programacion automatica vea que el martes no se programa nada"*.
--
-- Qué se midió: la otra sesión vació el martes 22/09 a las 12:27 moviendo 12 tandas. A las 12:45
-- el armador automático creó la tanda **E12F para el 22/09** (Okabe, 0,094 m³). O sea que
-- redistribuir a mano no alcanza: el armador vuelve a llenar el día cada 5 minutos.
--
-- Por dónde entró, y es el dato que define el arreglo: `gv_ppp_web_dia_camion` devuelve el
-- primer día que YA tiene camión a esa zona, y **no mira el día mínimo a propósito** (v15.48,
-- dueño: "si ya hay programado algo para x día para esa zona, hay que agregarlo ahí"). El 22
-- tenía D47B y E12E, así que era un día con camión y el pedido se colgó ahí. Por eso no alcanza
-- con correr el piso: hay que decir que ese día NO HAY CAMIÓN.
--
-- ⚠ NO se usa `GV_Dias_No_Habiles`. Eso significa "no se trabaja", y acá el armado sigue normal:
-- si el 22 fuera no hábil se movería el conteo de días hábiles de toda la operación (la espera de
-- cada pedido, los 10 días hábiles del tope, la anticipación mínima de 4). Son dos cosas
-- distintas y por eso son dos tablas distintas:
--
--     gv_es_dia_habil(d)        -> ¿se trabaja en el depósito?      (GV_Dias_No_Habiles)
--     gv_es_dia_con_reparto(d)  -> ¿además sale el camión?          (+ GV_Dias_Sin_Reparto)
--
-- REGLA DE RETIRA (Luis, 21/09, textual): *"Solo los que ya estan programados, no se programan
-- retiros nuevos"*. Un Retira lo viene a buscar el cliente al depósito, no usa camión: el que ya
-- quedó programado para ese día SALE IGUAL y no se toca. Lo que se frena es programar un Retira
-- NUEVO en un día sin reparto — queda en A Programar para que lo acomode Marianela.

-- 1) LA TABLA. Un día por fila, con el motivo escrito: dentro de un mes nadie se acuerda.
create table if not exists public."GV_Dias_Sin_Reparto" (
  fecha       date primary key,
  motivo      text not null,
  creado_por  text,
  creado_at   timestamptz not null default now()
);
alter table public."GV_Dias_Sin_Reparto" enable row level security;
grant select on public."GV_Dias_Sin_Reparto" to anon, authenticated;

drop policy if exists "GV_Dias_Sin_Reparto lectura" on public."GV_Dias_Sin_Reparto";
create policy "GV_Dias_Sin_Reparto lectura" on public."GV_Dias_Sin_Reparto" for select using (true);

-- 2) LAS DOS PREGUNTAS, separadas
create or replace function public.gv_es_dia_sin_reparto(p_fecha date default current_date)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select exists (select 1 from public."GV_Dias_Sin_Reparto" d where d.fecha = p_fecha);
$$;

create or replace function public.gv_es_dia_con_reparto(p_fecha date default current_date)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select public.gv_es_dia_habil(p_fecha) and not public.gv_es_dia_sin_reparto(p_fecha);
$$;

grant execute on function public.gv_es_dia_sin_reparto(date) to anon, authenticated, service_role;
grant execute on function public.gv_es_dia_con_reparto(date) to anon, authenticated, service_role;

-- 3) LOS CUATRO QUE ELIGEN DÍA. Medido sobre `gv_ppp_web_armar_pendientes`: los 11 pases sólo
--    llaman a estos cuatro para decidir una fecha (`gv_ppp_web_dia_minimo`,
--    `gv_ppp_web_proximo_dia_con_cupo`, `gv_ppp_web_dia_camion` y `gv_web_retiro_pactado`);
--    `ppp_web_armar_tandas` sólo escribe la fecha que ya eligió el llamador
--    (`dias_hasta_entrega = 0`), así que no se toca — y si se tocara, pisaría el día que el
--    cliente pactó para su Retira.

-- 3a) la cascada de días con cupo
create or replace function public.gv_ppp_web_proximo_dia_con_cupo(p_desde date)
returns date language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_d     date := coalesce(p_desde, current_date);
  v_usado numeric;
  v_i     int := 0;
begin
  loop
    v_i := v_i + 1;
    -- v20.64: `con_reparto` en vez de `habil` — el día sin reparto se saltea aunque se trabaje.
    if public.gv_es_dia_con_reparto(v_d) then
      select coalesce(sum(m3), 0) into v_usado
        from public."PPP_Web_Programacion"
       where fecha_entrega = v_d and coalesce(nullif(trim(tanda), ''), '') <> '';
      v_usado := v_usado + public.gv_ppp_web_m3_isis(v_d);
      if v_usado < public.gv_ppp_web_cupo(v_d) then return v_d; end if;
    end if;
    v_d := v_d + 1;
    exit when v_i > 120;
  end loop;
  return v_d;
end $$;

-- 3b) el piso de anticipación. El CONTEO de días hábiles no cambia (el depósito trabaja igual):
--     lo que no puede es TERMINAR en un día sin reparto.
create or replace function public.gv_ppp_web_dia_minimo(p_ahora timestamp with time zone default now())
returns date language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_local timestamp := p_ahora at time zone 'America/Argentina/Buenos_Aires';
  v_corte time := coalesce((select valor_texto from public."PPP_Web_Config" where clave = 'intradia_corte_hora'), '12:00')::time;
  v_n     int  := coalesce((select valor from public."PPP_Web_Config" where clave = 'dias_anticipacion_min'), 0)::int;
  v_d     date := v_local::date;
  v_g     int  := 0;
begin
  if v_local::time >= v_corte then v_d := v_d + 1; end if;
  while v_n > 0 and v_g < 60 loop
    v_d := v_d + 1; v_g := v_g + 1;
    if public.gv_es_dia_habil(v_d) then v_n := v_n - 1; end if;   -- el conteo NO cambia
  end loop;
  -- v20.64: y el día al que se llega tampoco puede ser un día sin reparto
  v_g := 0;
  while public.gv_es_dia_sin_reparto(v_d) and v_g < 60 loop v_d := v_d + 1; v_g := v_g + 1; end loop;
  return v_d;
end $$;

-- 3c) EL QUE IMPORTA: "¿qué día ya tiene camión a esta zona?". Un día sin reparto no tiene
--     camión, por más tandas que le hayan quedado adentro. Sin esta línea el pedido nuevo se
--     cuelga del día cerrado (fue exactamente E12F, 21/09 12:45).
create or replace function public.gv_ppp_web_dia_camion(p_zona text, p_desde date)
returns date language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
    -- v15.48 (dueno, 2026-09-11: "si ya hay programado algo para x dia para esa zona, hay que
    -- agregarlo ahi"): el piso NUNCA es mas tarde que manana.
    -- v18.60 (Luis, 15/09): la tanda de un SUPER no cuenta como "camion a esa zona".
    -- v20.64 (Luis, 21/09): un DIA SIN REPARTO no cuenta como camion a ninguna zona.
    with zn as (select (regexp_match(btrim(coalesce(p_zona, '')), '^Zona\s*([0-9]+)'))[1] as n),
         piso as (select least(coalesce(p_desde, current_date + 1), current_date + 1) as d)
    select min(dia) from (
      select w.fecha_entrega as dia
        from public."PPP_Web_Programacion" w, zn, piso
       where zn.n is not null
         and w.fecha_entrega >= piso.d
         and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
         and (regexp_match(btrim(coalesce(w.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
         and not public.gv_es_super(w.empresa, w.cod_cliente)
         and not public.gv_es_dia_sin_reparto(w.fecha_entrega)          -- v20.64
      union all
      select left(btrim(i.fecha_entrega::text), 10)::date
        from public.gv_ppp_programacion_diaria i, zn, piso
       where zn.n is not null
         and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
         and left(btrim(i.fecha_entrega::text), 10)::date >= piso.d
         and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
         and coalesce(i.tipo, '') <> 'KRIKOS'
         and (regexp_match(btrim(coalesce(i.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
         and not public.gv_es_super_np(i.np, i.cod)
         and not public.gv_es_dia_sin_reparto(left(btrim(i.fecha_entrega::text), 10)::date)  -- v20.64
    ) d;
  $$;

-- 3d) RETIRA. El pase (a4) programa solo el Retira con día pactado. Si ese día quedó sin reparto,
--     NO se programa: queda en A Programar con el badge para que lo recoordine un supervisor.
--     ⚠ Esto NO mueve a nadie: el Retira que ya estaba programado ese día sale igual, porque el
--     pase (a4) sólo mira los pedidos SIN tanda.
create or replace function public.gv_web_retiro_pactado(p_empresa text, p_order_id bigint)
returns date language sql stable
set search_path to 'public'
as $$
  /* v19.52 (Luis, 2026-09-17) — EL DIA QUE EL CLIENTE ELIGIO PARA RETIRAR. La pagina se lo
     pide al marcar "Retira" (minimo +3 dias habiles, lun-vie) y lo guarda en
     orders.sheets_payload->>'retiro_fecha'. Viaja de LK por el FDW cada 15 min.

     v19.60 (Thomas, 2026-09-18) — TAMBIEN MIRA EL DIA CARGADO A MANO (GV_Pedido_Horario).
     EL MANUAL MANDA, mismo criterio que el front (aprHorBadge).

     v20.64 (Luis, 2026-09-21) — y si ese dia quedo SIN REPARTO, no se programa solo. Regla
     textual: "Solo los que ya estan programados, no se programan retiros nuevos". El pedido
     queda en A Programar; el Retira ya programado para ese dia no se toca (este pase sólo
     mira los que NO tienen tanda). */
  select d.f from (
    select coalesce(
      (select h.fecha from public."GV_Pedido_Horario" h
        where h.empresa = p_empresa and h.clave = p_order_id::text and h.fecha is not null
        limit 1),
      (select m.retiro_fecha from public.lk_pedidos_match m
        where m.empresa = p_empresa and m.order_id = p_order_id
        limit 1)) as f) d
   where d.f is null or not public.gv_es_dia_sin_reparto(d.f);
$$;

-- 4) EL CENTINELA: qué quedó de REPARTO programado en un día sin camión. Mira las dos mitades
--    —web e ISIS— porque el día cerrado se llena por los dos lados, y saca lo que YA SALIÓ
--    (carga de camión o remito controlado): esa fecha es historia, no un pendiente. Los Retira
--    tampoco se marcan: salen igual, los viene a buscar el cliente.
--    ⚠ No se arregla solo: mover una tanda es decisión de armado (Marianela). Se reporta.
drop view if exists public.gv_dia_sin_reparto_ocupado;
create view public.gv_dia_sin_reparto_ocupado as
with salidos as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
   group by 1)
select d.fecha, d.motivo, 'web'::text as origen,
       upper(btrim(w.tanda)) as tanda,
       public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
       w.razon_social, coalesce(w.zona,'') as zona, w.m3
  from public."GV_Dias_Sin_Reparto" d
  join public."PPP_Web_Programacion" w on w.fecha_entrega = d.fecha
 where coalesce(nullif(btrim(w.tanda), ''), '') <> ''
   and not (coalesce(w.zona,'') ~* '^\s*retira\s*$')
   and not exists (select 1 from salidos s
                    where s.np = upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))))
union all
select d.fecha, d.motivo, 'isis',
       upper(btrim(i.tanda)),
       regexp_replace(upper(btrim(i.np)), '\.0+$', ''),
       i.razon_social, coalesce(i.zona,''), i.m3::numeric
  from public."GV_Dias_Sin_Reparto" d
  join public.gv_ppp_programacion_diaria i
    on btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
   and left(btrim(i.fecha_entrega::text), 10)::date = d.fecha
 where coalesce(nullif(btrim(i.tanda), ''), '') <> '' and i.np is not null
   and not (coalesce(i.zona,'') ~* '^\s*retira\s*$')
   and not exists (select 1 from salidos s where s.np = regexp_replace(upper(btrim(i.np)), '\.0+$', ''));
alter view public.gv_dia_sin_reparto_ocupado set (security_invoker = true);
grant select on public.gv_dia_sin_reparto_ocupado to anon, authenticated;

-- 5) LOS CENTINELAS DE REGLA
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_ppp_web_dia_camion','funcion','gv_es_dia_sin_reparto',
  'Un dia sin reparto NO cuenta como "camion a esa zona", por mas tandas que le hayan quedado adentro. Sin esto el armador cuelga el pedido nuevo del dia cerrado (paso con E12F el 21/09 12:45).',
  'Luis','v20.64'),
 ('gv_ppp_web_proximo_dia_con_cupo','funcion','gv_es_dia_con_reparto',
  'La cascada de dias con cupo saltea el dia sin reparto. Va con gv_es_dia_con_reparto, NUNCA con gv_es_dia_habil: el deposito ese dia trabaja igual.',
  'Luis','v20.64'),
 ('gv_web_retiro_pactado','funcion','gv_es_dia_sin_reparto',
  'Un Retira NUEVO no se programa solo en un dia sin reparto (queda en A Programar). El que ya estaba programado sale igual: el cliente lo viene a buscar, no usa camion.',
  'Luis','v20.64'),
 ('gv_es_dia_con_reparto','funcion','gv_es_dia_habil',
  'Son dos preguntas distintas: gv_es_dia_habil = se trabaja en el deposito; gv_es_dia_con_reparto = ademas sale el camion. Meter el dia sin reparto en GV_Dias_No_Habiles moveria el conteo de dias habiles de toda la operacion.',
  'Luis','v20.64');

-- ── CHEQUEOS ────────────────────────────────────────────────────────────────────────────────
--   select * from public.gv_reglas_perdidas;              -- vacia = todo bien
--   select * from public.gv_dia_sin_reparto_ocupado;      -- lo que quedo en un dia cerrado
--   select public.gv_es_dia_habil('2026-09-22')       as trabaja,      -- true: el armado sigue
--          public.gv_es_dia_con_reparto('2026-09-22') as sale_camion;  -- false

-- 6) EL DIA: el martes 22/09/2026, pedido de Luis.
insert into public."GV_Dias_Sin_Reparto" (fecha, motivo, creado_por)
values (date '2026-09-22', 'Martes sin reparto: no sale ningun camion. El armado sigue normal. Pedido de Luis, 21/09.', 'Luis (claude-remote)')
on conflict (fecha) do nothing;
