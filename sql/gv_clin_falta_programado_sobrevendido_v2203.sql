-- v22.03 — Vivi, 2026-09-23: "si ya no hay stock del 323E, no debo cobrarselo".
--
-- QUE ESTABA MAL
-- gv_clientes_nuevos_valor_lote y gv_clin_composicion reparten los importados escasos con un
-- greedy por (fecha_pedido, hora, order_id), y le hacen un ATAJO al pedido que ya esta en
-- gv_demanda_programada_pendiente: "sus cajas ya se contaron en _prog, no compite" -> falta = 0.
--
-- Ese atajo supone que lo PROGRAMADO entra en lo DISPONIBLE. Cuando no entra, la reserva es
-- ficticia y el atajo dice "tiene stock" con la gondola vacia.
--
-- Medido el 23/09 sobre web LK 1448 (Silvano, LK 4282, cliente nuevo en cuarentena):
--   * sus 3 NP (LK 0094/0095/0096) estan en la vista con tanda '' y fecha_entrega NULL,
--     o sea DESPROGRAMADAS, y aun asi disparaban el atajo;
--   * los 17 importados del pedido salian con cajas_falta = 0 y valor_importados = 0,00;
--   * 7 de esos 17 estan SOBREVENDIDOS, y 4 tienen CERO cajas:
--       035E  disp 0   programado 8      323E  disp 0   programado 10
--       970E  disp 0   programado 3      971E  disp 0   programado 4
--       590E  disp 3   programado 64     583E  disp 5   programado 17
--       584E  disp 15  programado 28
--
-- COMO QUEDA
-- Si de un codigo hay menos disponible que programado, se reparte lo que hay entre TODA la
-- demanda programada por su `prioridad` -- que ordena por fecha de entrega, y la NP sin fecha
-- (justo el caso del cliente nuevo retenido) va ULTIMA -- y cada pedido se queda con su parte.
-- Lo que no cubre es cajas_falta y NO se cobra (regla v20.41).
--
-- Cuando lo programado SI entra en lo disponible, cubiertas = cajas y el resultado es
-- identico al de hoy: el cambio muerde solo en el sobreventa.
--
-- ⚠ cubiertas queda NULL (no 0) cuando ese codigo del pedido no tiene fila en la vista
--   -- por ejemplo una NP ya facturada mientras otra sigue viva --. En ese caso NO se asume
--   faltante: cae al greedy normal contra `libre`, que es lo que corresponde.
--
-- ⚠ Al valor_lote se le agrega ademas _vl_itg (la agregacion por codigo que la v21.96 ya le
--   puso a la composicion). Sin eso, un codigo repetido en el carrito -- y 323E y 590E vienen
--   DOS veces en order_items de LK -- se cuenta como dos pedidos distintos peleando por la
--   misma caja, y las dos mitades se miden con el hermano como `tomado_antes`.
--
-- Se aplica sobre pg_get_functiondef (varias sesiones tocan estos objetos), es idempotente y
-- falla con un raise si el texto no matchea.

do $patch$
declare
  d text; nuevo text; pref text; f text;
begin
  foreach f in array array['public.gv_clientes_nuevos_valor_lote(jsonb)',
                           'public.gv_clin_composicion(jsonb,text,text)']
  loop
    pref := case when f like '%valor_lote%' then '_vl_' else '_cp_' end;
    d := pg_get_functiondef(f::regprocedure);

    if position(pref || 'progalloc' in d) > 0 then
      raise notice '% ya tiene la regla, no se toca', f;
      continue;
    end if;

    nuevo := d;

    -- (0) solo el valor_lote: la agregacion por codigo que la composicion ya tiene
    if pref = '_vl_' then
      if position('_vl_itg' in nuevo) = 0 then
        nuevo := replace(nuevo,
          '  _vl_prog as materialized (',
          '  _vl_itg as (' || chr(10) ||
          '    select order_id, empresa, cod_cli, cond, art, sum(cajas) as cajas,' || chr(10) ||
          '           codn, emp, imp, f_ped, h_ped' || chr(10) ||
          '      from _vl_it' || chr(10) ||
          '     group by order_id, empresa, cod_cli, cond, art, codn, emp, imp, f_ped, h_ped' || chr(10) ||
          '  ),' || chr(10) ||
          '  _vl_prog as materialized (');
        nuevo := replace(nuevo, '      from _vl_it it', '      from _vl_itg it');
        if position('_vl_itg' in nuevo) = 0 then
          raise exception 'no se pudo insertar _vl_itg en %', f;
        end if;
      end if;
    end if;

    -- (1) el reparto de lo disponible entre la demanda programada, por prioridad
    nuevo := replace(nuevo,
      '  ' || pref || 'libre as (',
      '  ' || pref || 'disp as materialized (' || chr(10) ||
      '    select it.codn, it.emp, max(public.gv_art_disponible(it.art, it.empresa)) as disp' || chr(10) ||
      '      from ' || pref || 'itg it' || chr(10) ||
      '     where it.imp and it.art is not null' || chr(10) ||
      '     group by it.codn, it.emp' || chr(10) ||
      '  ),' || chr(10) ||
      '  -- v22.03 (Vivi): estar programado NO garantiza la caja si lo programado pasa lo' || chr(10) ||
      '  -- disponible. Se reparte lo que hay por prioridad (la NP sin fecha va ultima).' || chr(10) ||
      '  ' || pref || 'progalloc as materialized (' || chr(10) ||
      '    select d.np, d.codn, d.emp,' || chr(10) ||
      '           greatest(0, least(d.cajas, dp.disp' || chr(10) ||
      '             - coalesce(sum(d.cajas) over (partition by d.codn, d.emp' || chr(10) ||
      '                                           order by d.prioridad' || chr(10) ||
      '                                           rows between unbounded preceding and 1 preceding), 0)' || chr(10) ||
      '           )) as cubiertas' || chr(10) ||
      '      from public.gv_demanda_programada_pendiente d' || chr(10) ||
      '      join ' || pref || 'disp dp on dp.codn = d.codn and dp.emp = d.emp' || chr(10) ||
      '  ),' || chr(10) ||
      '  ' || pref || 'npped as materialized (' || chr(10) ||
      '    select distinct s.order_id, s.empresa,' || chr(10) ||
      '           public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np' || chr(10) ||
      '      from ' || pref || 'src s' || chr(10) ||
      '      join public."PPP_Web_Programacion" w' || chr(10) ||
      '        on w.empresa = s.empresa and w.order_id::text = s.order_id' || chr(10) ||
      '  ),' || chr(10) ||
      '  ' || pref || 'progped as materialized (' || chr(10) ||
      '    select y.order_id, y.empresa, a.codn, a.emp, sum(a.cubiertas) as cubiertas' || chr(10) ||
      '      from ' || pref || 'npped y' || chr(10) ||
      '      join ' || pref || 'progalloc a on a.np = y.np' || chr(10) ||
      '     group by 1, 2, 3, 4' || chr(10) ||
      '  ),' || chr(10) ||
      '  ' || pref || 'libre as (');

    -- (2) que cubiertas viaje hasta _falta. NULL = ese codigo no tiene reserva que medir.
    nuevo := replace(nuevo,
      '                    where y.order_id = it.order_id and y.empresa = it.empresa) as ya_prog' || chr(10) ||
      '      from ' || pref || 'itg it',
      '                    where y.order_id = it.order_id and y.empresa = it.empresa) as ya_prog,' || chr(10) ||
      '           (select pp.cubiertas from ' || pref || 'progped pp' || chr(10) ||
      '             where pp.order_id = it.order_id and pp.empresa = it.empresa' || chr(10) ||
      '               and pp.codn = it.codn and pp.emp = it.emp) as cubiertas' || chr(10) ||
      '      from ' || pref || 'itg it');

    -- (3) el atajo de ya_prog deja de ser un cero a secas
    nuevo := replace(nuevo,
      '           case when not g.imp or g.ya_prog or g.art is null then 0' || chr(10) ||
      '                else greatest(0, g.cajas - greatest(0, g.libre - coalesce(g.tomado_antes, 0)))',
      '           case when not g.imp or g.art is null then 0' || chr(10) ||
      '                when g.ya_prog and g.cubiertas is not null' || chr(10) ||
      '                     then greatest(0, g.cajas - g.cubiertas)' || chr(10) ||
      '                else greatest(0, g.cajas - greatest(0, g.libre - coalesce(g.tomado_antes, 0)))');

    if position(pref || 'progalloc' in nuevo) = 0
       or position(pref || 'progped pp' in nuevo) = 0
       or position('when g.ya_prog and g.cubiertas is not null' in nuevo) = 0
       or position('or g.ya_prog or g.art is null' in nuevo) > 0 then
      raise exception 'el texto vivo de % no matcheo los anclajes: el parche NO se aplico', f;
    end if;

    execute nuevo;
    raise notice 'parcheada %', f;
  end loop;
end $patch$;

-- centinelas: que ninguna sesion vuelva a dejar el atajo como un cero a secas
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_clientes_nuevos_valor_lote', 'funcion', '_vl_progalloc',
  'Si lo programado de un importado pasa lo disponible, se reparte por prioridad: el cliente nuevo no paga la caja que no existe (Vivi 23/09)',
  'Vivi', 'v22.03'),
 ('gv_clin_composicion', 'funcion', '_cp_progalloc',
  'Si lo programado de un importado pasa lo disponible, se reparte por prioridad: el cliente nuevo no paga la caja que no existe (Vivi 23/09)',
  'Vivi', 'v22.03'),
 ('gv_clientes_nuevos_valor_lote', 'funcion', '_vl_itg',
  'Los items se agregan por codigo antes del greedy: un codigo repetido en el carrito no pelea contra si mismo (v21.96 / v22.03)',
  'Vivi', 'v22.03')
on conflict do nothing;

-- ============================================================================
-- MEDIDO AL APLICAR (23/09, como rol authenticated)
--
-- web LK 1448 (Silvano, LK 4282) — los 7 importados sobrevendidos pasan a cajas_ok 0:
--   035E 0/1 · 323E 0/3 · 583E 0/2 · 584E 0/2 · 590E 0/6 · 970E 0/2 · 971E 0/2
--   valor 1.730.662 -> 1.386.932 · no se cobra 343.730 (7 items)
--   importe de cada linea faltante = 0,00, asi que el total del pop-up ya los deja afuera.
--
-- control: los importados CON stock del mismo pedido no se movieron (529E y 812E, falta 0).
-- costo: composicion 297 ms · valor_lote 279 ms (timeout de authenticated: 8 s).
--
-- IMPACTO sobre los 7 pedidos web desprogramados de hoy: $2.218.883 que dejan de cobrarse
-- por adelantado (1451 455.881 · 1343 445.041 · 1347 440.940 · 1474 397.637 · 1448 343.730 ·
-- 1482 71.705 · 1349 63.949).
--
-- PRUEBA DEL CENTINELA (romper la regla y ver si avisa, en transaccion abortada):
--   antes: 0 perdidas · con _cp_progalloc renombrado: 1 · la nombra: si
-- ============================================================================
