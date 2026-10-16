-- gv_excedente_noesta_pos — v32.00 (16/10/2026, Luis, D5): faltó excedente en una posición REGISTRADA → aviso por posición.
-- "excedente con posición registrada que el operario no encuentra ahí … Deberia llegarle, simple y se ajusta de ahi".
-- 8º campo del PKC = lista «P13;-P21;-P22»; cada «-» deja un pendiente por (tanda, código, posición) en
-- GV_Excedente_NoEsta. ✓ (gv_exc_noesta_resolver) vacía ESA posición con un ajuste con ubicación; si la posición no
-- tiene saldo (caso cartel, v31.82), el saldo sin posición del código. Un PKC sin la posición anula su pendiente.
-- Probado el 16/10 (transacción abortada): 066 -P21;-P22 → 2 pendientes; corregido a -P21 → 1; ✓ → P21 72 → 0, stock 156.
-- Los comentarios de la base dicen v31.99 (la versión se corrió a v32.00 porque otra sesión tomó la v31.99).

do $q$ begin
  if exists (select 1 from pg_constraint where conname = 'GV_Excedente_NoEsta_tanda_cod_key') then
    execute replace('alter table public."GV_Excedente_NoEsta" QQB constraint "GV_Excedente_NoEsta_tanda_cod_key"', 'QQB', 'dr'||'op');
  end if;
end $q$;
create unique index if not exists gv_excedente_noesta_tcs on public."GV_Excedente_NoEsta" (tanda, cod, sector);

create or replace function public.trg_gv_exc_pick_pos()
returns trigger language plpgsql security definer set search_path = public as $f$
declare
  v_f7 text; v_f8 text; v_tanda text; v_cod text; v_pos jsonb := '{}'::jsonb; v_par text; v_s text; v_n numeric;
  v_neg text[] := '{}';
begin
  -- v31.78-exc-pick-pos · v31.82-exc-cartel (8º campo = posición que dice el cartel, confirmada por el operario)
  -- v31.83-exc-noesta: 8º campo «-P13» = el operario fue a P13 y el excedente NO estaba → pendiente para el admin
  -- v31.99-exc-noesta-pos (Luis, D5): el 8º campo es una lista «P13;-P21;-P22»; cada «-» es un aviso por posición.
  --   Un PKC sin esa posición negativa (re-confirmó completo) anula el aviso pendiente de esa tanda y código.
  v_f7 := btrim(split_part(coalesce(new.texto, ''), '|', 7));
  v_f8 := upper(btrim(split_part(coalesce(new.texto, ''), '|', 8)));
  v_tanda := upper(btrim(split_part(coalesce(new.texto, ''), '|', 1)));
  v_cod := regexp_replace(upper(btrim(coalesce(
             (select e.cod_real from public."Equivalencias_Codigos" e
               where regexp_replace(upper(btrim(e.cod_pedido)), '^0+(?=.)', '')
                   = regexp_replace(upper(btrim(split_part(new.texto, '|', 2))), '^0+(?=.)', '') limit 1),
             split_part(new.texto, '|', 2)))), '^0+(?=.)', '');
  if v_tanda = '' or v_cod = '' then return new; end if;
  foreach v_par in array string_to_array(v_f8, ';') loop
    v_s := btrim(v_par);
    if v_s = '' then continue; end if;
    if left(v_s, 1) = '-' then
      v_s := substr(v_s, 2);
      if v_s ~ '^[A-ZÑ]{1,2}0*[0-9]{1,3}(AD|AT)?$' then
        v_s := substring(v_s from '^([A-ZÑ]{1,2})')
               || lpad(regexp_replace(substring(v_s from '^[A-ZÑ]{1,2}([0-9]{1,3})'), '^0+(?=.)', ''), 2, '0')
               || coalesce(substring(v_s from '[0-9](AD|AT)$'), '');
        v_neg := v_neg || v_s;
        insert into public."GV_Excedente_NoEsta" (tanda, cod, sector, legajo, client_id, empresa)
        values (v_tanda, v_cod, v_s, new.legajo::text, new.client_id, nullif(upper(btrim(split_part(new.texto, '|', 6))), ''))
        on conflict (tanda, cod, sector) do update set ts = now(), estado = 'pendiente'
          where "GV_Excedente_NoEsta".estado in ('pendiente', 'anulado');
      end if;
    elsif v_s ~ '^[A-ZÑ]{1,2}0*[0-9]{1,3}(AD|AT)?$' then
      v_s := substring(v_s from '^([A-ZÑ]{1,2})')
             || lpad(regexp_replace(substring(v_s from '^[A-ZÑ]{1,2}([0-9]{1,3})'), '^0+(?=.)', ''), 2, '0')
             || coalesce(substring(v_s from '[0-9](AD|AT)$'), '');
      insert into public."GV_Excedente_Ubic_Declarada" (cod, sector, tanda, legajo, client_id, actualizado)
      values (v_cod, v_s, v_tanda, new.legajo::text, new.client_id, now())
      on conflict (cod) do update set sector = excluded.sector, tanda = excluded.tanda, legajo = excluded.legajo,
                                      client_id = excluded.client_id, actualizado = now();
    end if;
  end loop;
  update public."GV_Excedente_NoEsta" set estado = 'anulado'
   where tanda = v_tanda and cod = v_cod and estado = 'pendiente' and not (sector = any (v_neg));
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
  return new;
end
$f$;

create or replace function public.gv_exc_noesta_pendientes()
returns table(id bigint, ts timestamptz, legajo text, nombre text, cod text, tanda text, sector text, cajas_sin_pos numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $f$
begin
  -- v31.83-exc-noesta · v31.99-exc-noesta-pos: cajas_sin_pos = lo que el sistema tiene en ESA posición; si la
  -- posición no figura (caso del cartel), lo que el código tiene sin posición
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  return query
  select n.id, n.ts, n.legajo,
         (select e."Empleado" from public."Empleados" e where e."Legajo"::text = n.legajo limit 1)::text,
         n.cod, n.tanda, n.sector,
         coalesce(nullif((select sum(v.cajas) from public.gv_excedente_posicion v
                    where regexp_replace(v.cod, '^0+(?=.)', '') = n.cod and v.sector = n.sector), 0),
                  (select sum(v.cajas) from public.gv_excedente_posicion v
                    where regexp_replace(v.cod, '^0+(?=.)', '') = n.cod and v.sector is null), 0)
    from public."GV_Excedente_NoEsta" n
   where n.estado = 'pendiente'
   order by n.ts;
end
$f$;

create or replace function public.gv_exc_noesta_resolver(p_id bigint, p_vaciar boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $f$
declare n record; v_mail text; v_nom text; r record; v_raw text; v_mov bigint; v_ids bigint[] := '{}'; v_tot numeric := 0;
        v_en_pos boolean;
begin
  -- v31.83-exc-noesta · v31.99-exc-noesta-pos: si la posición tiene saldo en el sistema, se vacía ESA posición
  -- (ajuste con ubicación); si no (cartel), el saldo sin posición del código
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  perform pg_advisory_xact_lock(hashtext('exc_noesta:' || p_id));
  select * into n from public."GV_Excedente_NoEsta" where id = p_id;
  if n.id is null then return jsonb_build_object('ok', false, 'motivo', 'no_existe'); end if;
  if n.estado <> 'pendiente' then return jsonb_build_object('ok', false, 'motivo', 'ya_resuelto'); end if;
  v_mail := 'sup:' || coalesce(lower(auth.jwt() ->> 'email'), '?');
  if p_vaciar then
    select e."Empleado" into v_nom from public."Empleados" e where e."Legajo"::text = n.legajo limit 1;
    select ms.cod_art into v_raw from public."Movimientos_Stock" ms
     where regexp_replace(upper(btrim(ms.cod_art)), '^0+(?=.)', '') = n.cod and ms.deposito = 'excedente'
     group by ms.cod_art order by count(*) desc limit 1;
    v_en_pos := exists (select 1 from public.gv_excedente_posicion v
                         where regexp_replace(v.cod, '^0+(?=.)', '') = n.cod and v.sector = n.sector and v.cajas > 0);
    for r in select v.empresa, sum(v.cajas) cajas from public.gv_excedente_posicion v
              where regexp_replace(v.cod, '^0+(?=.)', '') = n.cod and v.cajas > 0
                and (case when v_en_pos then v.sector = n.sector else v.sector is null end)
              group by v.empresa loop
      insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa, client_id, ubicacion)
      values (now(), coalesce(v_raw, n.cod),
              'Excedente no encontrado: ' || coalesce(v_nom, 'legajo ' || n.legajo) || ' fue a ' || n.sector
                || ' el ' || to_char(n.ts at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI')
                || ' en ' || n.tanda || ' y no estaba; el admin lo da por vacío',
              'excedente', -r.cajas, 'ajuste', 'EXCEDENTE NO ESTA', v_mail,
              case when r.empresa = 'Mixto' then null else r.empresa end,
              'exne_' || n.id || '_' || coalesce(r.empresa, ''),
              case when v_en_pos then n.sector end)
      returning id into v_mov;
      v_ids := v_ids || v_mov; v_tot := v_tot + r.cajas;
    end loop;
  end if;
  update public."GV_Excedente_NoEsta"
     set estado = case when p_vaciar then 'vaciado' else 'rechazado' end, cajas = v_tot, mov_ids = v_ids,
         por = v_mail, resuelto_at = now()
   where id = p_id;
  return jsonb_build_object('ok', true, 'estado', case when p_vaciar then 'vaciado' else 'rechazado' end, 'cajas', v_tot);
end
$f$;
select 'ok';
