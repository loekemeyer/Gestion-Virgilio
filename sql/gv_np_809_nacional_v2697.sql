-- ============================================================================
-- v26.97 (Luis, 05/10/2026) — 809E de CH: facturado «Mixto» (D1/D2) y las 9 cajas del 809 primero (D3)
-- ⚠ Los marcadores internos del SQL dicen `v26.93-…` (es la versión con la que se aplicó antes de que
--   otras sesiones se llevaran la 26.93 a la 26.96): son la llave de idempotencia. No cambiarlos.
--
-- ── Lo que pasó ──────────────────────────────────────────────────────────────────────
-- «¿por qué se facturó un 809E que no existe?» Stocks mostraba una fila `809E` PELADA (sin LK ni CH)
-- con A facturar −4 / Stock −4. No era una factura de más: era la NP CH 0033 (F22F, 4 cajas de
-- 809E CH) facturada hoy 15:04 por el barrido, y su descuento quedó con empresa **'Mixto'**.
--   · las 4 cajas se pickearon el 30/09 en F21C (CH, góndola M14);
--   · el 02/10 12:54 la NP pasó a F22F. Ese traslado (v21.10) deja la porción como `ajuste`
--     (ref `F22F|MOV-F21C`), NO como `separado`/`picking`;
--   · para un código DUAL sin empresa, `trg_normalizar_empresa_stock` busca la empresa en (a) el
--     picking de la tanda, (b) la NP dentro del ref, (c) un `separado` de esa tanda en a_facturar.
--     F22F no tenía ninguno de los tres → 'Mixto'. La pila CH quedó con 4 cajas ya facturadas
--     (16 en vez de 12) y apareció la fila pelada con −4.
-- Era el único 'Mixto' de los 4 duales en todo el libro, pero la misma ruta se repite cada vez
-- que un dual ya armado cambia de tanda y después se factura.
--
-- ── D1 · el movimiento (APLICADO, con backup) ─────────────────────────────────────────
--   create table zz_backups."GV_Backup_Mov119150819_20261005" as
--     select * from public."Movimientos_Stock" where id = 119150819;
--   alter table zz_backups."GV_Backup_Mov119150819_20261005" enable row level security;
--   revoke insert, update, delete, truncate on zz_backups."GV_Backup_Mov119150819_20261005" from anon, authenticated;
--   update public."Movimientos_Stock" set empresa = 'CH'
--    where id = 119150819 and cod_art = '809E' and ref = 'F22F' and tipo = 'facturado' and empresa = 'Mixto';
--   select * from public.gv_refresh_stock_si_cambio(0, false);
-- Verificado: A facturar 809E CH 16 → 12 y la fila pelada desaparece (a_facturar CH 12, LK 1).
-- Rollback: update public."Movimientos_Stock" set empresa = 'Mixto' where id = 119150819;
--
-- ── D2 · la causa, en el trigger (APLICADO sobre la definición viva) ───────────────────
-- En el último fallback (facturado sobre a_facturar) el antecedente de empresa también puede ser un
-- `ajuste` de esa tanda: `X|MOV-Y` tiene explícita la empresa del pedido que viajó. Si hay
-- antecedentes de las dos empresas, count(DISTINCT) <> 1 y sigue cayendo en 'Mixto' como antes.
-- Probado con inserts reales en transacción abortada: antes del parche → Mixto; después → CH (tanda
-- CH) y LK (tanda LK).
-- ⚠ trg_normalizar_empresa_stock la tocan varias sesiones: el bloque se aplica sobre
--   pg_get_functiondef, es idempotente y falla con un raise si el texto no matchea.
-- ============================================================================
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10/2026: "d2 dale")
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure);
  if d ~ 'v26\.93-mov-ajuste' then return; end if;
  n := replace(d,
    $o$WHERE m.deposito='a_facturar' AND m.tipo='separado'$o$,
    $r$WHERE m.deposito='a_facturar' AND m.tipo IN ('separado','ajuste')  -- v26.93-mov-ajuste: el traslado de tanda (X|MOV-Y) tambien dice la empresa$r$);
  if n = d then raise exception 'trg_normalizar_empresa_stock: el texto no matcheo, no se toco nada'; end if;
  execute n;
end $p$;

-- ============================================================================
-- D3 · las 9 cajas del 809 (nacional, Chef) se usan PRIMERO
--
-- Luis: «las próximas 9 unidades que entren pedidas de 809E (o si ya hay alguna pedida) de pedidos
-- de CH se ponen como 809 (sin E, nacional). Literalmente a esa/esas NP/s −9 809E +9 809» y «que
-- no joda pedidos ya pickeados, armados, en proceso, facturados».
--
-- QUÉ HAY: el 809 (Corta Queso nacional, Chef) tiene 9 cajas en M16 sin moverse desde el 01/08;
-- los 6 picking de 809E CH desde el 15/09 (69 cajas) salieron todos del 809E. Ninguna regla lo
-- forzaba: el 809 aparece sólo en la agrupación de Stocks y en `Equivalencias_Familia` (que se usa al
-- revés: secundario sin stock → principal, v25.40). Los dos son de 12 cajas por master: 1 a 1.
--
-- CÓMO: se reusa EL MISMO mecanismo de v25.40 (`GV_NP_Cambio_Codigo`), en sentido contrario
-- (origen 809E → destino 809, factor 1). La Edge Function `gv-ppp-web-tandas-diarias` ya aplica ese
-- registro al armar la foto, el trigger `gv_ppp_web_base_np_cambio` impide que el 809E vuelva y el
-- podado reconoce el destino. Cero cambios en esas tres piezas. La línea de `PPP_Web_Base` se
-- RENOMBRA en el lugar (update 809E → 809): no hace falta borrar nada.
--
-- QUÉ NO SE TOCA (los frenos son los de v25.40 + el picking de stock):
--   · una tanda EMPEZADA (evento de un operario real: EP, PKC, AP…) → ni la NP ni las otras;
--   · una tanda con PICKING en el libro de stock;
--   · una NP con armado (`Entregas_Virgilio`) o ya facturada (`Facturacion_NP`);
--   · una NP ya cambiada por esta regla, o que ya trae 809 (el renombre chocaría con su línea);
--   · una línea que no entra ENTERA en lo que queda del cupo, o que supera el stock del 809 (menos
--     lo ya comprometido en NP sin pickear): se queda en 809E. NO PARTE una línea (el registro
--     cambia la línea entera, y partirla obligaba a tocar la Edge Function y dos objetos más).
--     Primero entra el pedido más viejo (order_id).
--   · sólo el 809E SIN L (el de Chef): con L sería un artículo de Loekemeyer.
--
-- ⚠ La función es SECURITY INVOKER a propósito (la corren el cron y los supervisores con su rol) y
--   NO lleva `delete`: el conector de Supabase de las sesiones cloud se cuelga a los 60 s con
--   cualquier `delete from` / `drop` (pide una confirmación que nadie puede dar). Medido el 05/10:
--   la misma función con un `delete` cortó tres veces; sin él entró al instante.
--
-- INTERRUPTORES (un `update`, no un deploy):
--   np_809_nacional_activo (1 = cambia; 0 o sin fila = sólo simula)
--   np_809_nacional_cupo   (9 = cajas de 809E que se cambian por 809; sale de las 9 de M16)
-- CHEQUEO:  select * from public.gv_web_np_809_nacional(true);   -- qué cambiaría, sin tocar
--           select * from public."GV_NP_Cambio_Codigo" where cod_destino = '809';
-- ROLLBACK de UNA NP: borrar su fila de GV_NP_Cambio_Codigo (cod_destino = '809'): la corrida siguiente de
--           la Edge Function vuelve a escribir el 809E del pedido y el podado saca el 809 (sólo si la tanda no
--           empezó). Ojo: el borrado hay que correrlo desde el SQL Editor, no desde una sesión cloud
--           (el conector se cuelga con `delete`).
--           Apagar la regla: select cron.unschedule('gv-np-809-nacional');
--                            update public."PPP_Web_Config" set valor = 0 where clave = 'np_809_nacional_activo';
-- ============================================================================
create or replace function public.gv_web_np_809_nacional(p_simular boolean default true, p_por text default 'sistema')
returns table(empresa text, order_id bigint, np_idx int, np_label text, tanda text,
              cod_origen text, cod_destino text, cajas_origen numeric, cajas_destino numeric,
              cupo_restante numeric, stock_809 numeric, accion text)
language plpgsql
set search_path to 'public'
as $fn$
#variable_conflict use_column
-- v26.93-809-nacional: en NP de CH, el 809E se cambia por el 809 nacional hasta agotar el cupo.
declare
  _n9_r      record;
  _n9_activo numeric;
  _n9_cupo   numeric;
  _n9_rest   numeric;
  _n9_disp   numeric;
  _n9_sim    boolean := coalesce(p_simular, true);
  _n9_verd   text;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Solo supervisores o el sistema pueden cambiar codigos de NP.';
  end if;
  select c.valor into _n9_activo from public."PPP_Web_Config" c where c.clave = 'np_809_nacional_activo';
  if coalesce(_n9_activo, 0) = 0 then _n9_sim := true; end if;
  select coalesce(c.valor, 0) into _n9_cupo from public."PPP_Web_Config" c where c.clave = 'np_809_nacional_cupo';
  _n9_cupo := coalesce(_n9_cupo, 0);

  select _n9_cupo - coalesce(sum(k.cajas_origen), 0) into _n9_rest
    from public."GV_NP_Cambio_Codigo" k
   where k.empresa = 'chef' and k.cod_origen = '809E' and k.cod_destino = '809';
  if _n9_rest <= 0 then return; end if;

  select coalesce((select sum(m.delta) from public."Movimientos_Stock" m
                    where m.deposito = 'terminado'
                      and regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') = '809'), 0)
       - coalesce((select sum(k.cajas_destino)
                     from public."GV_NP_Cambio_Codigo" k
                     join public."PPP_Web_Programacion" g
                       on g.empresa = k.empresa and g.order_id = k.order_id and g.np_idx = k.np_idx
                    where k.empresa = 'chef' and k.cod_origen = '809E' and k.cod_destino = '809'
                      and not exists (select 1 from public."Movimientos_Stock" p
                                       where p.tipo = 'picking' and p.deposito = 'separar_pedidos'
                                         and regexp_replace(upper(btrim(p.cod_art)), '^0+(?=.)', '') = '809'
                                         and upper(btrim(split_part(p.ref, '|', 1))) = upper(btrim(g.tanda)))), 0)
    into _n9_disp;

  for _n9_r in
    select b.empresa, b.order_id, b.np_idx, b.np_label, b.articulo, b.cajas, g.tanda as g_tanda
      from public."PPP_Web_Base" b
      join public."PPP_Web_Programacion" g
        on g.empresa = b.empresa and g.order_id = b.order_id and g.np_idx = b.np_idx
     where b.empresa = 'chef'
       and upper(btrim(b.articulo)) = '809E'
       and coalesce(btrim(g.tanda), '') <> ''
     order by b.order_id, b.np_idx
  loop
    empresa := _n9_r.empresa; order_id := _n9_r.order_id; np_idx := _n9_r.np_idx;
    np_label := _n9_r.np_label; tanda := _n9_r.g_tanda;
    cod_origen := '809E'; cod_destino := '809';
    cajas_origen := _n9_r.cajas; cajas_destino := _n9_r.cajas;

    _n9_verd := case
      when exists (select 1 from public."Registros_Produccion_Virgilio" r
                    where upper(btrim(split_part(r.texto, '|', 1))) = upper(btrim(_n9_r.g_tanda))
                      and coalesce(btrim(r.legajo), '') not in ('0', '1'))
        then 'no: la tanda ya empezo'
      when exists (select 1 from public."Movimientos_Stock" p
                    where p.tipo = 'picking' and upper(btrim(split_part(p.ref, '|', 1))) = upper(btrim(_n9_r.g_tanda)))
        then 'no: la tanda ya se pickeo'
      when exists (select 1 from public."Entregas_Virgilio" e where btrim(e.np) = btrim(_n9_r.np_label))
        then 'no: la NP ya tiene armado'
      when exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = btrim(_n9_r.np_label))
        then 'no: la NP ya se facturo'
      when exists (select 1 from public."GV_NP_Cambio_Codigo" k
                    where k.empresa = _n9_r.empresa and k.order_id = _n9_r.order_id
                      and k.np_idx = _n9_r.np_idx and k.cod_origen = '809E')
        then 'no: la NP ya esta cambiada'
      when exists (select 1 from public."PPP_Web_Base" x
                    where x.empresa = _n9_r.empresa and x.order_id = _n9_r.order_id
                      and x.np_idx = _n9_r.np_idx and upper(btrim(x.articulo)) = '809')
        then 'no: la NP ya trae 809'
      when coalesce(_n9_r.cajas, 0) <= 0
        then 'no: sin cajas'
      when _n9_r.cajas > _n9_rest
        then 'no: no entra entera en el cupo (quedan ' || _n9_rest || ')'
      when _n9_r.cajas > _n9_disp
        then 'no: el stock del 809 no alcanza (' || _n9_disp || ')'
      else 'cambiar'
    end;

    if _n9_verd <> 'cambiar' then
      accion := _n9_verd;
    else
      if not _n9_sim then
        insert into public."GV_NP_Cambio_Codigo" as x
          (empresa, order_id, np_idx, np_label, tanda, cod_origen, cod_destino, factor,
           cajas_origen, cajas_destino, stock_sec, stock_ppal, motivo, creado_por)
        values (_n9_r.empresa, _n9_r.order_id, _n9_r.np_idx, _n9_r.np_label, _n9_r.g_tanda,
                '809E', '809', 1, _n9_r.cajas, _n9_r.cajas, _n9_disp, null,
                'Luis 05/10: las cajas del 809 nacional salen primero (stock_sec = stock del 809)',
                coalesce(p_por, 'sistema'))
        on conflict on constraint "GV_NP_Cambio_Codigo_empresa_order_id_np_idx_cod_origen_key" do update
          set cod_destino = excluded.cod_destino, factor = excluded.factor,
              cajas_origen = excluded.cajas_origen, cajas_destino = excluded.cajas_destino,
              tanda = excluded.tanda, stock_sec = excluded.stock_sec;

        update public."PPP_Web_Base" w set articulo = '809'
         where w.empresa = _n9_r.empresa and w.order_id = _n9_r.order_id and w.np_idx = _n9_r.np_idx
           and w.articulo = _n9_r.articulo;
      end if;
      accion := case when _n9_sim then 'cambiaria' else 'cambiado' end;
      _n9_rest := _n9_rest - _n9_r.cajas;
      _n9_disp := _n9_disp - _n9_r.cajas;
    end if;
    cupo_restante := _n9_rest; stock_809 := _n9_disp;
    return next;
  end loop;
end $fn$;

revoke all on function public.gv_web_np_809_nacional(boolean, text) from public, anon;
grant execute on function public.gv_web_np_809_nacional(boolean, text) to authenticated, service_role;

-- interruptores (Luis: «d3 hardcode»; el cupo es un dato, no un deploy)
insert into public."PPP_Web_Config" (clave, valor, descripcion) values
  ('np_809_nacional_activo', 1, 'v26.93: en NP de CH el 809E se cambia por el 809 nacional (las cajas de M16 salen primero)'),
  ('np_809_nacional_cupo',   9, 'v26.93: cajas de 809E de CH que se cambian por 809 (las 9 que hay en M16)')
on conflict (clave) do update set valor = excluded.valor, descripcion = excluded.descripcion;

-- cron: 3 minutos después de cada corrida de la Edge Function (cron 73 = */5 9-23 UTC); jobid 134
select cron.schedule('gv-np-809-nacional', '3-59/5 9-23 * * *',
  $$select count(*) from public.gv_web_np_809_nacional(false)$$);

-- centinelas (el patrón sale del CÓDIGO, no del comentario)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('trg_normalizar_empresa_stock','funcion', 'tipo IN \(''separado'',''ajuste''\)', 'En un dual, el facturado sin empresa la toma tambien de un ajuste de la tanda (traslado X|MOV-Y); si no, cae en Mixto y deja una fila fantasma en Stocks', 'Luis 05/10', 'v26.93'),
 ('gv_web_np_809_nacional','funcion', 'np_809_nacional_cupo', 'Las 9 cajas del 809 nacional salen primero: en NP de CH el 809E se cambia por 809 hasta agotar el cupo', 'Luis 05/10', 'v26.93'),
 ('gv_web_np_809_nacional','funcion', 'la tanda ya empezo', 'El cambio 809E a 809 no toca una tanda empezada por un operario', 'Luis 05/10', 'v26.93'),
 ('gv_web_np_809_nacional','funcion', 'la tanda ya se pickeo', 'El cambio 809E a 809 no toca una tanda con picking', 'Luis 05/10', 'v26.93'),
 ('gv_web_np_809_nacional','funcion', 'Entregas_Virgilio', 'El cambio 809E a 809 no toca una NP ya armada', 'Luis 05/10', 'v26.93'),
 ('gv_web_np_809_nacional','funcion', 'Facturacion_NP', 'El cambio 809E a 809 no toca una NP ya facturada', 'Luis 05/10', 'v26.93');
