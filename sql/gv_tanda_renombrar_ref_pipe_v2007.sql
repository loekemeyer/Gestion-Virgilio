-- v20.07 (2026-09-18) — Los `ref` con PIPE también viajan al renombrar, y se corrigen E03G y D71B
-- =============================================================================================
-- EL AGUJERO. El facturado no anota el movimiento con la tanda sola: lo anota **`TANDA|NP`**
-- (`E03G|CH 0010`). El renombrador comparaba por igualdad exacta —`upper(btrim(ref)) = v_a`— así
-- que esas filas nunca matcheaban y se quedaban con el código VIEJO mientras el picking, el
-- armado, las Entregas y la Facturación viajaban al nuevo.
--
-- Estaba anotado desde el problema 421 (*"ni los `ref` con pipe (`tanda|NP`, `NP|CP`)"*) y nunca
-- se había tapado. Medido el 18/09, con las dos tandas que lo mostraban:
--
--   tanda vieja   se quedó con      tanda nueva   quedó con      suma
--   E03G          facturado −140    E44A          +149 −9 = +140   0
--   D71B          facturado  −72    E40A          + 78 −6 =  +72   0
--
-- ⚠ **Ninguna caja se pierde: la suma da cero.** El depósito estaba bien. Lo que mentía era la
-- pila POR TANDA — E44A decía tener 140 cajas esperando facturarse que ya se habían facturado, y
-- E03G, que hoy no tiene ni un pedido, mostraba −140. Y con esas dos filas clavadas en rojo,
-- `gv_stock_afacturar_tanda_negativa` dejaba de servir para el caso real: es el mismo desgaste
-- que se comió a otro centinela antes de la v19.77.
--
-- ── EL ARREGLO (1): que el renombrador los mueva ───────────────────────────────────────────
-- Va pegado al update de siempre, dentro de `gv_ppp_tanda_renombrar`. Misma fusión que el resto
-- del bloque de stock y por la misma razón: `facturado` está dentro de `mov_stock_pipeline_dedup`,
-- así que si el destino ya tiene esa fila hay que SUMAR, no chocar. Y el DELETE va antes del
-- UPDATE porque `trigger_actualizar_saldo_stock` no corre en DELETE.

  create temp table if not exists _tr_pipe (id_dest bigint primary key, suma numeric) on commit drop;
  delete from _tr_pipe where true;
  insert into _tr_pipe (id_dest, suma)
  select d.id, sum(v.delta)
    from public."Movimientos_Stock" v
    join public."Movimientos_Stock" d
      on d.tipo = v.tipo and d.deposito = v.deposito
     and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
     and coalesce(d.empresa, '') = coalesce(v.empresa, '')
     and upper(btrim(coalesce(d.ref, ''))) = v_b || substr(upper(btrim(v.ref)), length(v_a) + 1)
     and d.tipo in ('picking', 'separado', 'facturado')
   where upper(btrim(coalesce(v.ref, ''))) like v_a || '|%'
     and v.tipo in ('picking', 'separado', 'facturado')
   group by d.id;

  delete from public."Movimientos_Stock" v
   where upper(btrim(coalesce(v.ref, ''))) like v_a || '|%'
     and v.tipo in ('picking', 'separado', 'facturado')
     and exists (select 1 from public."Movimientos_Stock" d
                  where d.tipo = v.tipo and d.deposito = v.deposito
                    and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
                    and coalesce(d.empresa, '') = coalesce(v.empresa, '')
                    and upper(btrim(coalesce(d.ref, ''))) = v_b || substr(upper(btrim(v.ref)), length(v_a) + 1)
                    and d.tipo in ('picking', 'separado', 'facturado'));

  update public."Movimientos_Stock" d set delta = d.delta + f.suma
    from _tr_pipe f where d.id = f.id_dest;

  update public."Movimientos_Stock" m
     set ref = v_b || substr(btrim(m.ref), length(v_a) + 1)
   where upper(btrim(coalesce(m.ref, ''))) like v_a || '|%';

-- PROBADO CORRIÉNDOLO (ZZ85Z → ZZ86Z, filas de descarte borradas después):
--   ZZ85Z         (sin pipe) → ZZ86Z          ......... el camino viejo sigue igual
--   ZZ85Z|NPX  5             → ZZ86Z|NPX  5   ......... rename simple
--   ZZ85Z|NPY  3 + ZZ86Z|NPY 7 → ZZ86Z|NPY 10 ......... FUSIONÓ, sin violar el unique

-- ── EL ARREGLO (2): las dos tandas viejas ───────────────────────────────────────────────────
-- Con el renombrador ya arreglado, la corrección es llamarlo. No hizo falta SQL a mano: E03G y
-- D71B no tenían programación ni Entregas ni Facturación (todo eso ya estaba en E44A y E40A),
-- así que el renombre movió exactamente lo que faltaba — los 20 movimientos del facturado, las
-- 36 etiquetas de lío de E03G y los 4 candados, que también estaban colgados del código viejo.
--
--   select public.gv_ppp_tanda_renombrar('E03G','E44A','v20.07: el facturado habia quedado con el codigo viejo');
--   select public.gv_ppp_tanda_renombrar('D71B','E40A','v20.07: el facturado habia quedado con el codigo viejo');
--
-- Backups: zz_backups."GV_Backup_E03G_D71B_Movs_20260918" (366),
--          zz_backups."GV_Backup_E03G_D71B_Lock_20260918" (4) y "…_Lios_20260918" (36).
--
-- DESPUÉS:
--   E44A a_facturar ... +149 −149 = 0     E40A a_facturar ... +78 −78 = 0
--   E03G y D71B ....... sin un solo movimiento
--   gv_stock_afacturar_tanda_negativa (clase tanda) ... VACÍA (eran 50 filas)
--   picking duplicado · reglas perdidas · empresa fantasma · drenaje cruzado · góndola negativa ... 0
--   pickeado negativo ... 1, D53A (−2, de agosto, ajena)
--   candados huérfanos ... 12 → 7
