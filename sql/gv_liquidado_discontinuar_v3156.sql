-- v31.56 (Luis, 16/10/2026): "cuando se termine de facturar el último 574 (sin E, el nacional)
-- quiero que salga de la lista y ahí queda efectivamente como discontinuado".
--
-- Reemplaza la condición de la v30.30 (PKC + remito CRN + saldo total = 0), que con el −1
-- fantasma del 574 en terminado (F47A/F48N/F97A, ver v31.54) no se iba a cumplir nunca.
--
-- Recorre la LISTA de liquidación (GV_Pick_Liquidar, activo) y, por cada código viejo:
--   1) toma las tandas donde se pickeó el viejo desde `desde` (picking neto > 0 a separar_pedidos;
--      la tanda anulada -X no cuenta),
--   2) no queda NADA del viejo por levantar: ningún depósito con saldo > 0 (un negativo es
--      diferencia de conteo, no mercadería),
--   3) cada una de esas tandas está armada (tiene entrega del código del pedido) y TODAS sus NP
--      con ese código están facturadas (Facturacion_NP.facturado_at).
-- Si se cumple: sale de la lista (GV_Pick_Liquidar.activo = false) y alta en
-- Articulos_Discontinuados → su trigger saca SÓLO el código viejo del mapa (F50 es del 574E y no se toca) y deja de aparecer en stock/OC.
-- `tanda` devuelta = la última facturada. Idempotente. Cron 160 cada 10 min de 8 a 20 (ART).
-- Simular: select * from gv_liquidado_discontinuar(true);
create or replace function public.gv_liquidado_discontinuar(p_simular boolean default false)
returns table(cod text, tanda text, discontinuado boolean)
language plpgsql security definer set search_path = public as $f$
-- v31.56-liquidado-facturado
declare r record; v_tanda text; v_pend int; v_pos boolean;
begin
  for r in select upper(btrim(g.cod_liq)) cl, upper(btrim(g.cod_pedido)) cp, g.empresa emp, g.desde, g.nota
             from "GV_Pick_Liquidar" g where g.activo
  loop
    v_tanda := null;
    -- 2) nada del viejo con saldo positivo en ningún depósito
    select coalesce(bool_or(greatest(coalesce(v.terminado,0), coalesce(v.separar_pedidos,0), coalesce(v.a_facturar,0),
                                     coalesce(v.excedente,0), coalesce(v.racks,0), coalesce(v.racks_ch,0),
                                     coalesce(v.a_guardar,0), coalesce(v.para_envasar,0)) > 0), false)
      into v_pos from vista_saldos_stock v where upper(v.cod_art) = r.cl;
    if v_pos then continue; end if;
    -- 1) + 3) tandas con el viejo pickeado y su facturación
    with tnd as (
      select upper(btrim(m.ref)) t
        from "Movimientos_Stock" m
       where m.tipo = 'picking' and m.deposito = 'separar_pedidos' and m.creado >= r.desde
         and regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = r.cl
         and upper(btrim(m.ref)) !~ '-X$'
       group by 1 having sum(m.delta) > 0),
    np as (
      select t.t, en.np, f.facturado_at
        from tnd t
        left join public.gv_entregas_norm en on en.tanda = t.t and en.artn = r.cp
        left join "Facturacion_NP" f on f.np = en.np and f.facturado_at is not null)
    select count(*) filter (where np.np is null or np.facturado_at is null),
           (array_agg(np.t order by np.facturado_at desc nulls last))[1]
      into v_pend, v_tanda
      from np;
    if v_tanda is null or v_pend > 0 then continue; end if;
    if not p_simular then
      update "GV_Pick_Liquidar" g set activo = false
       where g.activo and upper(btrim(g.cod_liq)) = r.cl and upper(btrim(g.cod_pedido)) = r.cp;
      insert into "Articulos_Discontinuados"(cod, motivo)
      values (r.cl, 'liquidado en ' || r.cp || ' (v31.56): se facturó el último · tanda ' || v_tanda)
      on conflict do nothing;
    end if;
    cod := r.cl; tanda := v_tanda; discontinuado := not p_simular; return next;
  end loop;
end $f$;

select cron.alter_job(160, schedule => '7-57/10 11-23 * * *');

insert into "GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo)
values ('gv_liquidado_discontinuar', 'funcion', 'set activo = false',
        'v31.56: cuando se factura la última NP con el código liquidado (574), sale de GV_Pick_Liquidar (activo=false) y queda en Articulos_Discontinuados. Sin esto el 574 sigue en la lista de liquidar.',
        'Luis', 'v31.56', true);

-- Rollback: volver a correr sql/gv_liquidado_discontinuar_v3030.sql,
-- select cron.alter_job(160, schedule => '13 8 * * *'); y pasar a activo=false la fila v31.56 de GV_Reglas_Centinela.
