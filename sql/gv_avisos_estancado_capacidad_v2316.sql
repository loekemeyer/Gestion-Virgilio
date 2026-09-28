-- v23.16 (28/09) — dos avisos de Telegram que mentian. Aplicados sobre la definicion VIVA.
--
-- 1) STOCK ESTANCADO (reporte_agentes_stock_estancado): nombraba tandas que ya salieron (D72A).
--    Sumaba por CODIGO y le ponia la primera tanda que aparecia despues de la ultima vez que el
--    codigo llego a cero. D72A cierra en cero (287 pickeadas / separadas / facturadas); las cajas
--    abiertas del 958E (1) y 982E (5) son de D47B (separadas el 27/08, sin facturar).
--    Ahora la tanda es la que tiene la PILA abierta (saldo > 0 en su ref), y solo refs con forma de
--    tanda: el texto libre de un ajuste ("v16.91 neteo doble drenaje ...") ya no sale como tanda.
--    Si hay mas de una pila abierta: "D47B (+1)".
--
-- 2) CAPACIDAD SIN PROYECCION (reporte_agentes_capacidad_sin_maximo): listaba los SECUNDARIOS
--    (323, 332-338, 565, 574, 809), que no tienen proyeccion propia a proposito (v22.72: se suma al
--    principal). 24 -> 14 codigos.
--
-- Probado en transaccion abortada (las dos funciones tragan errores con `exception when others`,
-- asi que se miro el texto encolado, no el "no exploto").

do $x$ declare d text; n text; old_cte text;
begin
  d := pg_get_functiondef('public.reporte_agentes_stock_estancado()'::regprocedure);
  if d ~ '_te_pila' then raise notice 'estancado ya aplicado'; else
  old_cte := substring(d from '(tanda_cod as \(.*?order by r\.deposito, r\.cod, r\.ts asc, r\.id asc\s*\))');
  if old_cte is null then raise exception 'no matchea tanda_cod'; end if;
  n := replace(d, old_cte, $r$tanda_cod as (
    select deposito, cod,
           (array_agg(tanda order by desde))[1]
             || case when count(*) > 1 then ' (+' || (count(*) - 1) || ')' else '' end as tanda
    from (select deposito, cod, upper(btrim(split_part(ref, '|', 1))) as tanda, min(ts) as desde
            from mv
           where deposito in ('separar_pedidos', 'a_facturar')
             and upper(btrim(split_part(ref, '|', 1))) ~ '^([A-Z][0-9]{2}[A-Z]|PRUEBA[0-9]+)$'
           group by 1, 2, 3
          having sum(delta) > 0.5) _te_pila
    group by deposito, cod
  )$r$);
  n := replace(n, 'left join pppmap pm on pm.tanda = upper(btrim(tc.tanda))',
                  'left join pppmap pm on pm.tanda = upper(btrim(split_part(tc.tanda, '' '', 1)))');
  if n !~ 'split_part\(tc\.tanda' then raise exception 'no matchea el join pppmap'; end if;
  execute n;
  end if;

  d := pg_get_functiondef('public.reporte_agentes_capacidad_sin_maximo()'::regprocedure);
  if d ~ '_cs_sec' then raise notice 'capacidad ya aplicado'; else
  n := replace(d, '      and not exists (select 1 from disc d where d.codn = c.codn))',
    '      and not exists (select 1 from disc d where d.codn = c.codn)
      and not exists (select 1 from public.gv_proyeccion_articulo _cs_sec
                        where _cs_sec.es_secundario
                          and upper(regexp_replace(trim(_cs_sec.cod), ''^0+(.)'', ''\1'')) = c.codn))');
  if n = d then raise exception 'no matchea el filtro disc'; end if;
  execute n;
  end if;
end $x$;
