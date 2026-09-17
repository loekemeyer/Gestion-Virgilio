-- ============================================================================
-- v19.51 — DESARMAR UNA NP YA FACTURADA: SE COMPENSA EL ASIENTO
-- Gestión Virgilio · proyecto hrxfctzncixxqmpfhskv · 2026-09-17
-- ============================================================================
--
-- Decisión del dueño (Luis, 17/09), cerrando el problema 392:
--   *"No, porque no quiero ponerme a cruzar notas de crédito. Asumí que si se desarma
--    un pedido ya facturado significa que hay nota de crédito que lo compensa, así que
--    compensá asiento solo."*
--
-- O sea: la opción (B). La factura NO se toca desde acá — nada de borrar la fila de
-- `Facturacion_NP` ni de encolar anulaciones en ISIS. Lo único que hace el desarme es
-- dejar el STOCK bien.
--
-- EL PROBLEMA
-- -----------
-- Cuando una NP se factura, su drenaje saca las cajas de `a_facturar` dando por hecho que
-- salieron del depósito. Si después se cancela, no salieron — pero el desarme volvía a
-- sacar de `a_facturar`, que ya estaba en cero, y el depósito quedaba en negativo. Pasó con
-- la NP 98507 (Perez Zarate, tanda D53C): −3 cajas, y el stock total 3 cajas corto.
--
-- LA SOLUCIÓN: la REVERSA
-- -----------------------
-- Antes de devolver la mercadería, el desarme repone lo que el facturado había descontado.
-- Queda una fila `desarme` de +N en `a_facturar` con la descripción "Reversa del facturado
-- de la NP X (tanda T): …", y enseguida la salida de −N. Neto: cero. La pila nunca queda
-- negativa y el stock total cierra.
--
-- ============================================================================
-- 1. `gv_ppp_np_devolucion` — DOS ARREGLOS, no uno
-- ============================================================================
-- (a) **La pila se medía con `ref = tanda` EXACTO**, así que no veía los drenajes por NP
--     (`tanda|NP`) ni los desarmes de otras NP de la misma tanda (que salen con `ref = NP`).
--     Creía que las cajas seguían ahí. Es el mismo pozo que el front ya había tapado en su
--     v5.96 con `_stockAfacturarRestanteTanda`. Ahora mide `ref = tanda`, `ref = tanda|…` y
--     los desarmes atribuidos por el "(tanda XXXX)" de la descripción.
--
-- (b) **Columna nueva `rev_fact`**: cuántas cajas hay que reponer porque esta NP ya las
--     drenó al facturarse. Los dos formatos de `ref` del facturado son los mismos que usa
--     `revertir_drenaje_facturado()`: `tanda|NP` y `NP|CP`.
--
-- ⚠ Y `dren` RESTA lo ya repuesto. Sin eso, desarmar dos veces la misma NP devuelve la
--   mercadería dos veces — se midió corriendo el desarme dos veces seguidas, no leyendo el
--   código. La primera vuelta devolvía 24 cajas y la segunda otras 24.
--
-- ⚠ Cambia el tipo de retorno, así que va DROP + CREATE (no hay `OR REPLACE` que valga).
--   La llaman `gv_ppp_np_desarmar` y `gv_ppp_np_cancelar_previo` (la pantalla de
--   confirmación), las dos por nombre de columna: la columna nueva no les molesta.
--
-- El CREATE completo va ABAJO (sección 4): el repo tiene que poder recrear la función,
-- no alcanza con decir que está aplicada en la base.

-- ============================================================================
-- 2. `gv_ppp_np_desarmar` — escribe la reversa
-- ============================================================================
-- En el `cross join lateral` de depósitos se agregó una fila más, ANTES de la salida:
--
--   ('a_facturar',       1, d.rev_fact,  'reversa'),
--   ('a_facturar',      -1, d.de_fact,   'salida'),
--   ('separar_pedidos', -1, d.de_sep,    'salida'),
--   ('terminado',        1, d.a_term,    'salida'),
--   ('excedente',        1, d.a_exc,     'salida'),
--   ('a_guardar',        1, d.a_guardar, 'salida')
--
-- y la descripción pasó a depender de `x.etq`. ⚠ La de la reversa TIENE que llevar el
-- "(tanda XXXX)": es por ahí que la vuelven a encontrar el centinela
-- `gv_stock_afacturar_tanda_negativa` y el CTE `sal` de la función de arriba.
--
-- El mensaje que ve el supervisor lo dice: *"⚠ la NP ya estaba facturada: se repuso el
-- facturado de N cajas (se compensa con nota de crédito)"*.
--
-- El guard `zzz_facturado_no_negativo` (v19.49) no interfiere: mira `tipo = 'facturado'`
-- y estas filas son `desarme`.

-- ============================================================================
-- 3. CÓMO SE PROBÓ — corriendo el desarme de verdad, dentro de una transacción abortada
-- ============================================================================
--
-- do $prueba$ … perform public.gv_ppp_np_desarmar('98497', 'PRUEBA …', 'prueba', …);
--            … raise exception 'RESULTADO >>> %', …; end; $prueba$;
--
-- | prueba | qué se esperaba | qué dio |
-- |---|---|---|
-- | NP 98497 (ya facturada, pila D53C en 0) | a_facturar neto 0 | **0** — 34 filas: 17 reversas y 17 salidas · a_guardar +24 ✔ |
-- | la misma, segunda vuelta | no devolver nada | *"no había mercadería movida: no se devolvió nada"* ✔ |
-- | NP LK 0054 (sin facturar, tanda E03F con pila viva) | igual que siempre | a_facturar **−19** · a_guardar +19 · **0 filas de reversa** ✔ |
-- | `gv_ppp_np_cancelar_previo('98497')` (la pantalla) | las mismas cajas | 17 art / 24 cajas ✔ |
--
-- Nada quedó vivo: 0 filas en `Movimientos_Stock`, `GV_Desarmes` y `NP_Canceladas`.
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- Las definiciones anteriores están en el historial de git (v19.50 y anteriores).
-- `gv_ppp_np_devolucion` vuelve con DROP + CREATE de la versión de 8 columnas (sin
-- `rev_fact`) y `gv_ppp_np_desarmar` con un CREATE OR REPLACE sacando la fila 'reversa'
-- del `cross join lateral` y `v_rev` del mensaje.
-- ⚠ No alcanza con revertir una sola: la fila 'reversa' del desarme necesita la columna.
-- ============================================================================

-- ============================================================================
-- 4. EL CREATE COMPLETO — `gv_ppp_np_devolucion`
-- ============================================================================
drop function if exists public.gv_ppp_np_devolucion(text,text);

create function public.gv_ppp_np_devolucion(p_np text, p_tanda text default null::text)
 returns table(cod_art text, empresa text, org_term numeric, org_exc numeric, total numeric,
               de_fact numeric, de_sep numeric, rev_fact numeric, a_guardar numeric)
 language sql
 stable
 set search_path to 'public','pg_temp'
as $function$
with np as (
  select regexp_replace(btrim(p_np), '\.0+$', '') as np
), t as (
  /* La tanda, por las MISMAS cuatro fuentes que `gv_ppp_prog_arbol` y en el mismo orden: la
     programación viva primero, y después lo que ya salió del espejo de ISIS (que es amnésico). */
  select coalesce(
    nullif(btrim(coalesce(p_tanda, '')), ''),
    (select regexp_replace(btrim(p.tanda),'\s+$','') from public.gv_ppp_programacion_diaria p, np
      where regexp_replace(btrim(p.np), '\.0+$','') = np.np limit 1),
    (select btrim(w.tanda) from public."PPP_Web_Programacion" w, np
      where upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)) = upper(np.np) limit 1),
    (select btrim(f.tanda) from public."Facturacion_NP" f, np
      where regexp_replace(btrim(f.np::text), '\.0+$','') = np.np
        and coalesce(nullif(btrim(f.tanda), ''), '') <> '' limit 1),
    (select btrim(h.tanda) from public."GV_PPP_Entregados_Historico" h, np
      where regexp_replace(btrim(h.np), '\.0+$','') = np.np
        and coalesce(nullif(btrim(h.tanda), ''), '') <> '' limit 1)
  ) as tanda
), ped as (
  select public.canon_cod(i.art) ck, sum(i.cajas)::numeric cajas
    from public.gv_ppp_np_items i, np where i.np = np.np group by 1
), sal as (
  /* v19.51 — LA PILA DE LA TANDA, ENTERA. Antes esto era `ref = tanda` EXACTO, y por eso no
     veía los drenajes por NP (`tanda|NP`) ni los desarmes de otras NP de la misma tanda (que
     salen con `ref = NP`): creía que las cajas seguían ahí y las devolvía de nuevo. Es el
     mismo pozo que el front ya había tapado en su v5.96 y el que dejó la NP 98507 con
     a_facturar en -3 (problema 392). Un desarme se le atribuye a su tanda por el
     "(tanda XXXX)" de la descripción, igual que el CTE `dev` de más abajo. */
  select public.canon_cod(m.cod_art) ck,
         (array_agg(m.cod_art order by length(m.cod_art)))[1] cod_art,
         (array_agg(m.empresa) filter (where m.empresa is not null))[1] empresa,
         coalesce(sum(m.delta) filter (where m.deposito = 'a_facturar'), 0)      fact,
         coalesce(sum(m.delta) filter (where m.deposito = 'separar_pedidos'), 0) sep,
         coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'terminado' and m.delta < 0), 0) org_term,
         coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'excedente' and m.delta < 0), 0) org_exc
    from public."Movimientos_Stock" m, t
   where upper(btrim(m.ref)) = upper(btrim(t.tanda))
      or left(upper(btrim(m.ref)), length(btrim(t.tanda)) + 1) = upper(btrim(t.tanda)) || '|'
      or (m.tipo in ('desarme','ajuste') and m.descripcion like '%(tanda ' || t.tanda || ')%')
   group by 1
), dren as (
  /* v19.51 — lo que ESTA NP ya drenó de a_facturar al facturarse Y TODAVÍA NO SE REPUSO. Los
     dos formatos de ref del facturado son los mismos que usa `revertir_drenaje_facturado()`.
     Si el pedido se cancela después de facturado, la mercadería nunca salió: hay que reponer
     esto antes de devolverlo. ⚠ Y hay que RESTAR lo ya repuesto: sin eso, desarmar dos veces
     la misma NP devuelve la mercadería dos veces (medido). */
  select ck, greatest(sum(q), 0) qty from (
    select public.canon_cod(m.cod_art) ck, -m.delta q
      from public."Movimientos_Stock" m, t, np
     where m.deposito = 'a_facturar' and m.tipo = 'facturado' and m.delta < 0
       and (upper(btrim(m.ref)) = upper(btrim(t.tanda)) || '|' || upper(np.np)
         or upper(btrim(m.ref)) = upper(np.np) || '|CP')
    union all
    select public.canon_cod(m.cod_art), -m.delta
      from public."Movimientos_Stock" m, np
     where m.deposito = 'a_facturar' and m.tipo in ('desarme','ajuste') and m.delta > 0
       and upper(btrim(m.ref)) = upper(np.np)
  ) z group by ck
), dev as (
  select public.canon_cod(m.cod_art) ck,
         coalesce(sum(m.delta) filter (where m.deposito = 'terminado'), 0) tt,
         coalesce(sum(m.delta) filter (where m.deposito = 'excedente'), 0) ee
    from public."Movimientos_Stock" m, t
   where m.tipo = 'desarme' and m.delta > 0
     and m.descripcion like '%(tanda ' || t.tanda || ')%'
   group by 1
), c as (
  select s.cod_art, s.empresa, s.fact, s.sep,
         greatest(s.org_term - coalesce(dv.tt, 0), 0) as org_term,
         greatest(s.org_exc  - coalesce(dv.ee, 0), 0) as org_exc,
         coalesce(dr.qty, 0) as dren,
         least(p.cajas, greatest(s.fact, 0) + coalesce(dr.qty, 0) + greatest(s.sep, 0)) as total
    from ped p
    join sal s on s.ck = p.ck
    left join dev  dv on dv.ck = p.ck
    left join dren dr on dr.ck = p.ck
)
select c.cod_art, c.empresa, c.org_term, c.org_exc, c.total,
       least(c.total, greatest(c.fact, 0) + c.dren)                        as de_fact,
       c.total - least(c.total, greatest(c.fact, 0) + c.dren)              as de_sep,
       least(c.dren, greatest(least(c.total, greatest(c.fact, 0) + c.dren)
                              - greatest(c.fact, 0), 0))                   as rev_fact,
       c.total                                                             as a_guardar
  from c where c.total > 0;
$function$;

-- ============================================================================
-- 5. EL PEDAZO QUE CAMBIÓ DE `gv_ppp_np_desarmar`
-- ============================================================================
-- El resto de la función quedó igual; lo que cambió es el INSERT de los movimientos, el
-- temp table que lo alimenta (ahora trae `v.rev_fact`), el `v_rev` del resumen y la línea
-- del mensaje. La definición viva completa:
--   select pg_get_functiondef('public.gv_ppp_np_desarmar(text,text,text,boolean,boolean,boolean,boolean)'::regprocedure);
--
--   create temp table _gv_dev on commit drop as
--   select v.cod_art, v.empresa, v.org_term, v.org_exc, v.total, v.de_fact, v.de_sep, v.rev_fact,
--          0::numeric as a_term, 0::numeric as a_exc, v.a_guardar
--     from public.gv_ppp_np_devolucion(v_np, v_tanda) v;
--
--   insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
--   select now(), d.cod_art,
--          case when x.etq = 'reversa'
--               then 'Reversa del facturado de la NP ' || v_np || ' (tanda ' || v_tanda
--                    || '): el pedido se cancela despues de facturado, asi que la mercaderia nunca salio '
--                    || 'y se repone lo que el facturado habia descontado. Se compensa con nota de credito. '
--               else case when v_ag and not v_vuelve then 'Cancelacion del pedido ' else 'Desarme del pedido ' end
--                    || v_np || ' (tanda ' || v_tanda || '): '
--          end || v_just,
--          x.dep, x.signo * x.cant, 'desarme', v_np, nullif(btrim(p_por), ''), d.empresa
--     from _gv_dev d
--     cross join lateral (values
--       ('a_facturar',       1, d.rev_fact,  'reversa'),
--       ('a_facturar',      -1, d.de_fact,   'salida'),
--       ('separar_pedidos', -1, d.de_sep,    'salida'),
--       ('terminado',        1, d.a_term,    'salida'),
--       ('excedente',        1, d.a_exc,     'salida'),
--       ('a_guardar',        1, d.a_guardar, 'salida')
--     ) as x(dep, signo, cant, etq)
--    where x.cant > 0;
--
-- ⚠ La descripción de la reversa TIENE que llevar el "(tanda XXXX)": es por ahí que la
--   vuelven a encontrar el centinela y el CTE `sal`.
-- ============================================================================
