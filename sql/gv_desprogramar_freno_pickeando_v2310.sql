-- v23.10 (Luis, 2026-09-28): "si se estaba pickeando por qué fue para cuarentena y salió de
-- programación?" → "que salte mensaje de que se están pickeando/armando y que requiere
-- coordinación entre cobranzas y virgilio y que lo bloquee".
--
-- Caso: LK 1506 (Multi Bazar, NP LK 0178/0179) estaba en E37E, PICKEADA el 25/09 (TP, 32 cajas en
-- separar_pedidos). El 28/09 09:09 alguien tocó «↩ Volver a Cuarentena» (gv_cuarentena_devolver →
-- gv_ppp_web_desprogramar) y la NP salió de la programación con el pallet armado. La única guarda
-- era "ya salió" (CCN/CRN): el freno por tanda empezada lo había sacado la v17.85 (web) y la v16.03
-- (ISIS), confiando en tanda_previa. Se restauró a mano (backup zz_backups."GV_Backup_Web1506_20260928").
--
-- REGLA: si la tanda de la NP tiene EP/TP/PKC/AP/TAP de un legajo real → BLOQUEADO con mensaje.
-- Excepción: gv_ppp_np_desarmar (devuelve el stock y DESPUÉS desprograma) marca gv.desarmando.
-- Se aplica sobre la definición viva, idempotente, con raise si no matchea.

do $p$
declare d text; a text;
  g_web text := $g$
  -- v23.10-freno (Luis, 28/09): tanda pickeándose/armándose → BLOQUEADO (salvo desarme).
  if coalesce(current_setting('gv.desarmando', true), '') <> '1' then
    select string_agg(distinct upper(btrim(w.tanda)), ', ') into v_sal
      from public."PPP_Web_Programacion" w
     where w.empresa = v_emp and w.order_id = v_oid and nullif(btrim(w.tanda), '') is not null
       and exists (select 1 from public."Registros_Produccion_Virgilio" r
                    where r.opcion in ('EP','TP','PKC','AP','TAP')
                      and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                      and not public.es_legajo_test(r.legajo));
    if v_sal is not null then
      raise exception 'BLOQUEADO: la tanda % ya se está pickeando o armando en Virgilio. Sacar este pedido de la programación (o volverlo a Cuarentena) requiere coordinación entre Cobranzas y Virgilio: hablen con el depósito antes. No se tocó nada.', v_sal;
    end if;
  end if;

$g$;
  g_isis text := $g$
  -- v23.10-freno (Luis, 28/09): tanda pickeándose/armándose → BLOQUEADO (salvo desarme).
  if coalesce(current_setting('gv.desarmando', true), '') <> '1' then
    select string_agg(distinct x.n || ' (' || x.t || ')', ', ') into v_det
      from (select n, coalesce(
                     (select nullif(btrim(o2.tanda), '') from public."GV_PPP_Prog_Override" o2 where o2.np = n),
                     (select nullif(btrim(p.tanda), '') from public."GV_PPP_Programacion_Diaria" p
                       where regexp_replace(btrim(p.np), '\.0+$', '') = n limit 1)) t
              from unnest(v_nps) n) x
     where x.t is not null
       and exists (select 1 from public."Registros_Produccion_Virgilio" r
                    where r.opcion in ('EP','TP','PKC','AP','TAP')
                      and upper(btrim(split_part(r.texto,'|',1))) = upper(x.t)
                      and not public.es_legajo_test(r.legajo));
    if v_det is not null then
      raise exception 'BLOQUEADO: % ya se está pickeando o armando en Virgilio. Sacar este pedido de la programación (o volverlo a Cuarentena) requiere coordinación entre Cobranzas y Virgilio: hablen con el depósito antes. No se tocó nada.', v_det;
    end if;
  end if;

$g$;
begin
  -- web
  d := pg_get_functiondef('public.gv_ppp_web_desprogramar(text,text)'::regprocedure);
  if position('v23.10-freno' in d) = 0 then
    a := E'  insert into public."GV_PPP_Web_Retenido" as t';
    if position(a in d) = 0 then raise exception 'web_desprogramar no matchea'; end if;
    execute replace(d, a, g_web || a);
  end if;
  -- isis
  d := pg_get_functiondef('public.gv_ppp_isis_desprogramar(text[],text,text)'::regprocedure);
  if position('v23.10-freno' in d) = 0 then
    a := E'  v_nota := ''v16.03 ''';
    if position(a in d) = 0 then raise exception 'isis_desprogramar no matchea'; end if;
    execute replace(d, a, g_isis || a);
  end if;
  -- desarmar: avisa que es un desarme (ahí sí se desprograma una tanda trabajada)
  d := pg_get_functiondef(to_regprocedure((select oid::regprocedure::text from pg_proc where proname='gv_ppp_np_desarmar' limit 1)));
  if position('gv.desarmando' in d) = 0 then
    a := E'  if v_isis then\n    if v_vuelve then';
    if position(a in d) = 0 then raise exception 'np_desarmar no matchea'; end if;
    execute replace(d, a, E'  perform set_config(''gv.desarmando'', ''1'', true);  -- v23.10-freno\n' || a);
  end if;
end $p$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_ppp_web_desprogramar','funcion','gv\.desarmando','no se desprograma una NP web cuya tanda se está pickeando/armando: requiere coordinación Cobranzas-Virgilio','Luis','v23.10'),
  ('gv_ppp_isis_desprogramar','funcion','gv\.desarmando','no se desprograma una NP de ISIS cuya tanda se está pickeando/armando','Luis','v23.10'),
  ('gv_ppp_np_desarmar','funcion','gv\.desarmando','el desarme marca gv.desarmando para poder desprogramar después de devolver el stock','Luis','v23.10')
) v(o,c,p,r,q,ve)
where not exists (select 1 from public."GV_Reglas_Centinela" x where x.objeto = v.o and x.patron = v.p);
