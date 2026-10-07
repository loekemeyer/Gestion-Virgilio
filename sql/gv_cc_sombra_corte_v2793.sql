-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 07/10/2026: "corregí y pasame el sql")
-- =====================================================================================
-- v27.93 (Luis, 07/10/2026): MODO SOMBRA de la cuenta corriente — dos correcciones
-- =====================================================================================
-- 1) El Excel de deuda NO es "la deuda a la hora en que se subió": es la deuda al CIERRE
--    de un día (el reporte de ISIS). Medido con el de LK del 07/10 11:11: trae TODAS las
--    facturas del 06/10 y NINGÚN comprobante del 07/10 (la FC 0004-36161 de Matiz,
--    $8.179.600, emitida 07/10 08:09, no está). Y las NC del corte NO aparecen como
--    renglón: se imputan contra su factura (o la anulan entera: Cencosud FC 36160 + NC
--    11247 de $21.189,62 y Garbarino FC 36159 + NC 11248 de $20.778,12, las cuatro del
--    06/10, ninguna en el Excel porque se cancelan entre sí).
--
--    El estimador anterior cortaba por la HORA de subida y, en el día del ancla, sumaba
--    las FC que no estaban en el Excel y salteaba las NC (regla heredada de deuda_viva).
--    Resultado: FC anulada el mismo día = +importe de la FC; FC del día de la subida = de más.
--
--    Ahora cada ancla tiene su CORTE = la fecha más nueva de los comprobantes de ISIS que
--    trae el Excel. Todo lo de fecha <= corte YA está adentro del Excel (como renglón, o
--    imputado, o cancelado); lo de fecha > corte se suma, FC, ND y NC por igual.
--
-- 2) Días sin Excel. La racha ya no exige un Excel por día hábil: cada cruce OK valida
--    TODOS los días hábiles entre el corte anterior (exclusive) y el nuevo (inclusive),
--    porque estima esos días juntos contra la verdad del ERP (es una prueba más difícil,
--    no más fácil). Un día sin Excel queda pendiente y lo valida el Excel siguiente.
--    La racha se corta sólo con un cruce que dé diferencia.
-- =====================================================================================

alter table public."GV_CC_Ancla" add column if not exists corte date;
alter table public."GV_CC_Cruce" add column if not exists corte_prev date;
alter table public."GV_CC_Cruce" add column if not exists corte_nuevo date;

-- Corte de un lote: fecha máxima de los comprobantes ISIS (FC/ND/NC) que el Excel trae.
-- Se mira sólo 120 días para atrás (el doc_key se calcula sobre ISIS, no por renglón).
-- Sin ninguno reconocido: el día anterior al de la subida.
create or replace function public.gv_cc_sombra_corte(p_emp text, p_lote text)
returns date language plpgsql stable security definer set search_path = public
as $f$
declare v_ancla timestamptz; v_c date;
begin
  select max(ancla) into v_ancla from "GV_CC_Ancla" where empresa = p_emp and lote = p_lote;
  if v_ancla is null then return null; end if;
  with k as materialized (select distinct doc_key from "GV_CC_Ancla"
                           where empresa = p_emp and lote = p_lote and doc_key is not null),
       i as materialized (
         select d.fecha, gv_cobranza_doc_key(d.familia, d.punto_venta||d.numero) dk
           from isis_lk.documentos d
          where p_emp = 'lk' and d.familia in ('factura_venta','nd_venta','nc_venta')
            and d.fecha between (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date - 120
                            and (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date
         union all
         select d.fecha, gv_cobranza_doc_key(d.familia, d.punto_venta||d.numero)
           from isis_ch.documentos d
          where p_emp = 'chef' and d.familia in ('factura_venta','nd_venta','nc_venta')
            and d.fecha between (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date - 120
                            and (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date)
  select max(i.fecha) into v_c from i join k on k.doc_key = i.dk;
  return coalesce(v_c, (v_ancla at time zone 'America/Argentina/Buenos_Aires')::date - 1);
end $f$;

-- Estimado por cliente: ancla anterior + comprobantes con fecha en (corte_prev, corte_nuevo]
-- − recibos posteriores (misma numeración que gv_cobranza_deuda_viva_refrescar).
-- La versión vieja gv_cc_sombra_estimar(text,text,timestamptz) NO se dropea (el DROP se cuelga en el MCP):
-- queda sin llamador, de rollback.
create or replace function public.gv_cc_sombra_estimar(p_emp text, p_lote_prev text, p_corte_nuevo date)
returns table (cod text, base numeric, nuevos numeric, cobros numeric)
language plpgsql stable security definer set search_path = public
as $f$
declare v_corte date; v_med numeric; v_nrec bigint;
begin
  -- v27.93-cc-corte
  select max(a.corte) into v_corte from "GV_CC_Ancla" a where a.empresa = p_emp and a.lote = p_lote_prev;
  if v_corte is null then v_corte := gv_cc_sombra_corte(p_emp, p_lote_prev); end if;
  if v_corte is null then return; end if;

  select percentile_cont(0.5) within group (order by r.recibo::bigint) into v_med
    from gv_cobranza_recibos r where r.empresa = p_emp and r.fecha_primer_cobro between v_corte - 30 and v_corte;
  select max(r.recibo::bigint) into v_nrec
    from gv_cobranza_recibos r
   where r.empresa = p_emp and r.fecha_primer_cobro between v_corte - 30 and v_corte and r.recibo::bigint <= 1.05 * v_med;

  return query
  with b as materialized (
         select a.cod, a.doc_key, a.pendiente from "GV_CC_Ancla" a where a.empresa = p_emp and a.lote = p_lote_prev),
       docs as materialized (
         select regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') c,
                gv_cobranza_doc_key(d.familia, d.punto_venta||d.numero) k,
                case when d.familia = 'nc_venta' then -abs(d.total) else abs(d.total) end m
           from isis_lk.documentos d
          where p_emp = 'lk' and d.familia in ('factura_venta','nc_venta','nd_venta')
            and d.fecha > v_corte and d.fecha <= p_corte_nuevo
         union all
         select regexp_replace(coalesce(d.contraparte_codigo,''),'^0+',''),
                gv_cobranza_doc_key(d.familia, d.punto_venta||d.numero),
                case when d.familia = 'nc_venta' then -abs(d.total) else abs(d.total) end
           from isis_ch.documentos d
          where p_emp = 'chef' and d.familia in ('factura_venta','nc_venta','nd_venta')
            and d.fecha > v_corte and d.fecha <= p_corte_nuevo),
       n as (select dd.c, sum(dd.m) m from docs dd
              where dd.m <> 0 and not exists (select 1 from b where b.doc_key = dd.k) group by 1),
       r as (select rr.cod_cliente c,
                    sum(rr.pagado / (1 - coalesce((select sd.pct from "GV_Cobranza_Super_Deduccion" sd
                                                    where sd.empresa = p_emp and sd.cod_cliente = rr.cod_cliente), 0))) m
               from gv_cobranza_recibos rr
              where rr.empresa = p_emp and v_nrec is not null
                and rr.recibo::bigint > v_nrec and rr.recibo::bigint <= 1.05 * v_nrec
                and rr.fecha_primer_cobro <= p_corte_nuevo
              group by 1),
       bb as (select b.cod c, sum(b.pendiente) m from b group by 1),
       u as (select bb.c from bb union select n.c from n union select r.c from r)
  select u.c, coalesce(bb.m,0), coalesce(n.m,0), coalesce(r.m,0)
    from u left join bb on bb.c = u.c left join n on n.c = u.c left join r on r.c = u.c
   where u.c <> '' and not (p_emp = 'lk' and u.c = '411') and not (p_emp = 'chef' and u.c = '1434');
end $f$;

-- Racha: días hábiles cubiertos por los cruces OK seguidos, del más nuevo hacia atrás.
-- Cada cruce cubre (corte_prev, corte_nuevo]. Se corta sólo con un cruce con diferencia.
create or replace function public.gv_cc_sombra_racha(p_emp text, p_var text)
returns int language plpgsql stable security definer set search_path = public
as $f$
declare c record; v_n int := 0;
begin
  -- v27.93-cc-racha-cubre
  for c in select ok, corte_prev, corte_nuevo from "GV_CC_Cruce"
            where empresa = p_emp and variante = p_var and corte_nuevo is not null
            order by ancla_nueva desc loop
    exit when not c.ok;
    v_n := v_n + (select count(*) from generate_series(c.corte_prev + 1, c.corte_nuevo, interval '1 day') g
                   where gv_es_dia_habil(g::date))::int;
  end loop;
  return v_n;
end $f$;

-- Tick: igual que v27.89, con el corte guardado en el ancla y pasado al estimador.
create or replace function public.gv_cc_sombra_tick()
returns text language plpgsql security definer set search_path = public
as $f$
declare e text; v_lote text; v_ancla timestamptz; v_prev text; v_tol numeric; v_obj int; v_emp_id int;
        v_var text; v_id bigint; v_racha int; v_task bigint; v_out text := '';
        v_corte date; v_corte_prev date;
begin
  -- v27.88-cc-sombra · v27.93-cc-corte
  select valor into v_tol from "GV_CC_Sombra_Config" where clave = 'tolerancia';
  select valor::int into v_obj from "GV_CC_Sombra_Config" where clave = 'racha_objetivo';
  select valor::int into v_emp_id from "GV_CC_Sombra_Config" where clave = 'planify_employee';

  foreach e in array array['lk','chef'] loop
    select x.lote, max(x.cargado_at) into v_lote, v_ancla from "GV_Cuarentena_Deuda_Detalle" x
     where x.empresa = e group by x.lote order by max(x.cargado_at) desc limit 1;
    continue when v_lote is null;
    continue when exists (select 1 from "GV_CC_Ancla" a where a.empresa = e and a.lote = v_lote);

    select a.lote into v_prev from "GV_CC_Ancla" a where a.empresa = e and a.ancla < v_ancla
     order by a.ancla desc limit 1;

    insert into "GV_CC_Ancla" (empresa, lote, ancla, cod, doc_key, comprobante, pendiente)
    select e, v_lote, v_ancla, regexp_replace(coalesce(x.cod,''),'^0+',''),
           gv_cobranza_doc_key(split_part(x.comp_key,'-',1), split_part(x.comp_key,'-',2)),
           x.comprobante, x.pendiente
      from "GV_Cuarentena_Deuda_Detalle" x
     where x.empresa = e and x.lote = v_lote and x.pendiente <> 0 and x.comp_key ~ '^[A-Z]';
    v_corte := gv_cc_sombra_corte(e, v_lote);
    update "GV_CC_Ancla" set corte = v_corte where empresa = e and lote = v_lote;
    v_out := v_out || format('%s: ancla %s (corte %s) copiada. ', e, v_lote, v_corte);

    continue when v_prev is null;
    select max(corte) into v_corte_prev from "GV_CC_Ancla" where empresa = e and lote = v_prev;
    if v_corte_prev is null then
      v_corte_prev := gv_cc_sombra_corte(e, v_prev);
      update "GV_CC_Ancla" set corte = v_corte_prev where empresa = e and lote = v_prev;
    end if;

    foreach v_var in array array['excel+isis','excel+isis-banco'] loop
      v_id := null;
      insert into "GV_CC_Cruce" (empresa, variante, lote_prev, ancla_prev, lote_nuevo, ancla_nueva, dia,
                                 clientes, clientes_dif, suma_abs_dif, max_abs_dif, ok, corte_prev, corte_nuevo)
      values (e, v_var, v_prev, (select max(ancla) from "GV_CC_Ancla" where empresa = e and lote = v_prev),
              v_lote, v_ancla, v_corte, 0, 0, 0, 0, false, v_corte_prev, v_corte)
      on conflict do nothing returning id into v_id;
      continue when v_id is null;

      insert into "GV_CC_Cruce_Detalle" (cruce_id, cod, estimado, excel, dif)
      select v_id, coalesce(s.cod, n.cod),
             round(coalesce(s.base + s.nuevos - case when v_var = 'excel+isis-banco' then s.cobros else 0 end, 0), 2),
             round(coalesce(n.m, 0), 2),
             round(coalesce(s.base + s.nuevos - case when v_var = 'excel+isis-banco' then s.cobros else 0 end, 0)
                   - coalesce(n.m, 0), 2)
        from gv_cc_sombra_estimar(e, v_prev, v_corte) s
        full join (select a.cod, sum(a.pendiente) m from "GV_CC_Ancla" a
                    where a.empresa = e and a.lote = v_lote
                      and not (e = 'lk' and a.cod = '411') and not (e = 'chef' and a.cod = '1434')
                    group by 1) n on n.cod = s.cod;

      update "GV_CC_Cruce" c set
        clientes     = d.n,
        clientes_dif = d.nd,
        suma_abs_dif = d.sa,
        max_abs_dif  = d.mx,
        ok           = (d.nd = 0)
        from (select count(*) n, count(*) filter (where abs(dif) >= v_tol) nd,
                     coalesce(sum(abs(dif)),0) sa, coalesce(max(abs(dif)),0) mx
                from "GV_CC_Cruce_Detalle" where cruce_id = v_id) d
       where c.id = v_id;

      v_racha := gv_cc_sombra_racha(e, v_var);
      v_out := v_out || format('%s/%s racha %s. ', e, v_var, v_racha);

      -- una sola tarea por empresa (la primera variante que llegue; planify.tasks tiene unico (name, date))
      if v_racha >= v_obj and not exists (select 1 from "GV_CC_Sombra_Aviso" where empresa = e) then
        insert into planify.tasks (name, type, prio, time, date, note, rec, done, assignment_type,
          employee_id, department_id, system_generated, broadcast, created_at, updated_at)
        values (left('Implementar cuenta corriente en página ' || upper(e), 60), 'tarea', 'normal', '09:00',
          to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD'),
          format('Falta: decidir e implementar la cuenta corriente del cliente en la página %s. El modo sombra (variante %s) dio %s días hábiles seguidos con 0 diferencia contra el Excel de deuda. NO se muestra nada al cliente hasta pedido explícito de Thomas o Luis. Pedido de Luis · cargada por Claude (gv_cc_sombra_tick), sesión https://claude.ai/code/session_016HWyanXdXj3agMmtenRK2U',
                 upper(e), v_var, v_racha),
          'none', false, 'employee', v_emp_id, null, true, false, now(), now())
        returning id into v_task;
        insert into "GV_CC_Sombra_Aviso" (empresa, variante, task_id, racha) values (e, v_var, v_task, v_racha);
        v_out := v_out || format('TAREA %s abierta. ', v_task);
      end if;
    end loop;
  end loop;
  return coalesce(nullif(v_out, ''), 'sin lotes nuevos');
end $f$;

revoke execute on function public.gv_cc_sombra_corte(text, text) from public, anon, authenticated;
revoke execute on function public.gv_cc_sombra_estimar(text, text, date) from public, anon, authenticated;
revoke execute on function public.gv_cc_sombra_racha(text, text) from public, anon, authenticated;
revoke execute on function public.gv_cc_sombra_tick() from public, anon, authenticated;

-- Las anclas que ya estaban: se les calcula el corte UNA vez por lote (no por fila)
do $bf$ declare l record; begin
  for l in select distinct empresa, lote from public."GV_CC_Ancla" where corte is null loop
    update public."GV_CC_Ancla" set corte = public.gv_cc_sombra_corte(l.empresa, l.lote)
     where empresa = l.empresa and lote = l.lote;
  end loop;
end $bf$;

-- La vista suma los cortes
-- (create or replace: las columnas nuevas van AL FINAL; el DROP se cuelga en el MCP)
create or replace view public.gv_cc_sombra_estado with (security_invoker = true) as
select c.empresa, c.variante, c.dia, c.lote_prev, c.lote_nuevo,
       c.clientes, c.clientes_dif, round(c.suma_abs_dif) suma_abs_dif, round(c.max_abs_dif) max_abs_dif, c.ok,
       public.gv_cc_sombra_racha(c.empresa, c.variante) racha_actual,
       c.corte_prev, c.corte_nuevo
  from public."GV_CC_Cruce" c order by c.ancla_nueva desc, c.empresa, c.variante;

-- Centinelas: el de la racha (349) pasa a 'exit when not c\.ok'; nuevos para estimar y corte.

-- -------------------------------------------------------------------------------------
-- Chequeo
--   select empresa, lote, corte from public."GV_CC_Ancla" group by 1,2,3;   -- lk 07/10 → corte 06/10
--   select * from public.gv_cc_sombra_estado;
-- Rollback: volver a correr sql/gv_cc_sombra_v2789.sql (las columnas nuevas quedan, no molestan)
--   y drop function public.gv_cc_sombra_corte(text,text), public.gv_cc_sombra_estimar(text,text,date);
-- =====================================================================================
