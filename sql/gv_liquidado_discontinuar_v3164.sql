-- v31.64 (Luis, 16/10/2026): "en armado van a ver que falta un 574 y se ajusta desde el operario
-- en el armado. Con eso el stock queda en 0, saldado (y ahí sí, discontinualo)".
-- Suma una segunda vía a la de la v31.56 (que sigue valiendo, la usan 636/635 de Chef):
--   A) v31.64 SALDADO: cada tanda donde se pickeó el viejo está ARMADA (tiene entrega del código
--      del pedido) y el viejo quedó en 0 en TODOS los depósitos (ni positivo ni negativo);
--   B) v31.56 FACTURADO: ningún depósito del viejo > 0 y todas las NP de esas tandas con el
--      código del pedido facturadas (Facturacion_NP.facturado_at).
-- Si se cumple: sale de la lista (GV_Pick_Liquidar.activo = false) y alta en
-- Articulos_Discontinuados (libera la góndola F50). El faltante del pedido se completa
-- con el código del pedido (574E) desde Completar pedido (pkLiqPedidoDe, index.html).
-- Simular: select * from gv_liquidado_discontinuar(true);
create or replace function public.gv_liquidado_discontinuar(p_simular boolean default false)
returns table(cod text, tanda text, discontinuado boolean)
language plpgsql security definer set search_path = public as $f$
-- v31.64-liquidado-saldado (+ v31.56-liquidado-facturado)
declare r record; v_tanda text; v_sin_armar int; v_sin_fact int; v_pos boolean; v_nocero boolean; v_via text;
begin
  for r in select upper(btrim(g.cod_liq)) cl, upper(btrim(g.cod_pedido)) cp, g.empresa emp, g.desde, g.nota
             from "GV_Pick_Liquidar" g where g.activo
  loop
    v_tanda := null;
    select coalesce(bool_or(greatest(coalesce(v.terminado,0), coalesce(v.separar_pedidos,0), coalesce(v.a_facturar,0),
                                     coalesce(v.excedente,0), coalesce(v.racks,0), coalesce(v.racks_ch,0),
                                     coalesce(v.a_guardar,0), coalesce(v.para_envasar,0)) > 0), false),
           coalesce(bool_or(coalesce(v.terminado,0) <> 0 or coalesce(v.separar_pedidos,0) <> 0 or coalesce(v.a_facturar,0) <> 0
                            or coalesce(v.excedente,0) <> 0 or coalesce(v.racks,0) <> 0 or coalesce(v.racks_ch,0) <> 0
                            or coalesce(v.a_guardar,0) <> 0 or coalesce(v.para_envasar,0) <> 0), false)
      into v_pos, v_nocero from vista_saldos_stock v where upper(v.cod_art) = r.cl;
    if v_pos then continue; end if;   -- queda mercadería del viejo: se sigue liquidando
    with tnd as (
      select upper(btrim(m.ref)) t, max(m.creado) ult
        from "Movimientos_Stock" m
       where m.tipo = 'picking' and m.deposito = 'separar_pedidos' and m.creado >= r.desde
         and regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = r.cl
         and upper(btrim(m.ref)) !~ '-X$'
       group by 1 having sum(m.delta) > 0),
    np as (
      select t.t, t.ult, en.np, f.facturado_at
        from tnd t
        left join public.gv_entregas_norm en on en.tanda = t.t and en.artn = r.cp
        left join "Facturacion_NP" f on f.np = en.np and f.facturado_at is not null)
    select count(distinct np.t) filter (where np.np is null),
           count(*) filter (where np.np is null or np.facturado_at is null),
           (array_agg(np.t order by np.ult desc))[1]
      into v_sin_armar, v_sin_fact, v_tanda
      from np;
    if v_tanda is null then continue; end if;
    v_via := case when not v_nocero and v_sin_armar = 0 then 'stock saldado tras el armado'
                  when v_sin_fact = 0 then 'se facturó el último' end;
    if v_via is null then continue; end if;
    if not p_simular then
      update "GV_Pick_Liquidar" g set activo = false
       where g.activo and upper(btrim(g.cod_liq)) = r.cl and upper(btrim(g.cod_pedido)) = r.cp;
      insert into "Articulos_Discontinuados"(cod, motivo)
      values (r.cl, 'liquidado en ' || r.cp || ' (v31.64): ' || v_via || ' · tanda ' || v_tanda)
      on conflict do nothing;
    end if;
    cod := r.cl; tanda := v_tanda; discontinuado := not p_simular; return next;
  end loop;
end $f$;

update "GV_Reglas_Centinela" set regla = 'v31.64: cuando el código liquidado (574) queda en 0 en todos los depósitos y sus tandas están armadas (o se facturó la última NP, v31.56), sale de GV_Pick_Liquidar (activo=false) y queda en Articulos_Discontinuados. Sin esto el 574 sigue en la lista con la góndola F50 ocupada.', version = 'v31.64'
 where objeto = 'gv_liquidado_discontinuar' and patron = 'set activo = false';

-- Rollback: volver a correr sql/gv_liquidado_discontinuar_v3156.sql.
