-- ============================================================================
-- v16.99 — La alarma de clientes en riesgo mira las DOS empresas juntas
--
-- Proyecto: LK (kwkclwhmoygunqmlegrg). Reemplaza la version de gv_clientes_riesgo
-- que dejo `sql/gv_cliente_canon_v1693.sql` (punto 5 de ese archivo).
--
-- POR QUE
-- Thomas (14/09): "Chef y LK usan codigos diferentes. Tenemos clientes que
-- compran en los dos, clientes que solo le compran a uno, clientes que antes le
-- compraban a uno y despues pasaron a comprarle al otro. Cada empresa usa su
-- propia convencion de codigos (un cliente que tiene codigo 102 en LK puede
-- estar en CH con codigo 333). Queremos hacer el analisis limpio (a lo mejor
-- pasaron de comprarle a LK a comprarle a CH y la venta real no cayo)."
--
-- La union por CUIT ya la hace gv_cliente_canon (un cliente = un cliente_id =
-- su CUIT, con el codigo que tenga en cada empresa). Al 14/09 hay 183 clientes
-- que facturan en las dos empresas y practicamente ninguno comparte numero:
-- Aboudi Moussa es chef:2648 / lk:1800, Aimetta es chef:2460 / lk:490, etc.
--
-- LO QUE CAMBIA ACA son dos cosas del informe:
--
--   1) UN SOLO CORTE CALENDARIO PARA TODOS. Antes cada empresa se comparaba
--      contra su propio ultimo mes. Asi no se puede ver una migracion: si el
--      cliente dejo LK en mayo y arranco en Chef en junio, con ventanas
--      corridas los dos movimientos no caen en el mismo trimestre. Ahora las
--      dos empresas se miden en los MISMOS meses.
--
--   2) COLUMNAS NUEVAS: `lk_ahora` / `lk_pico` / `ch_ahora` / `ch_pico` para ver
--      de donde sale cada caja, y `migracion` ('paso de LK a Chef' / 'paso de
--      Chef a LK') cuando una empresa bajo y la otra subio. Un cliente que
--      migro sigue apareciendo en la vista, pero con el cartel puesto: la venta
--      real no cayo, cambio de empresa.
--
--   3) `chef_incompleto`: el cliente factura por Chef pero NO tiene ninguna fila
--      de Chef despues del corte del feed de Chef (al 14/09, 2026-06). Ahi la
--      caida puede ser mentira y no hay con que probarlo.
--
-- ⚠ AL 14/09 LAS 3 "MIGRACIONES" Y LOS 7 `chef_incompleto` DE LA ALARMA SON EL
-- MISMO ARTEFACTO DE CARGA, NO MOVIMIENTOS COMERCIALES: los batches `julio_26`
-- y `ago-26` metieron facturas de Chef con empresa='lk' (19 y 21 codigos que
-- solo existen en el padron de Chef: Dorinka, Del Plastic, Ierakuin, Clapera,
-- Superimperio...). Hasta que eso se acomode, esas filas hay que leerlas con
-- esta nota al lado. Ver §3.ec de docs/SUPABASE-GESTION-VIRGILIO.md.
--
-- ROLLBACK: drop view if exists public.gv_clientes_riesgo;  y volver a crear la
-- del punto 5 de sql/gv_cliente_canon_v1693.sql.
-- ============================================================================

drop view if exists public.gv_clientes_riesgo;
create view public.gv_clientes_riesgo
with (security_invoker = true) as
with m as (
  select v.cliente_id, v.empresa, date_trunc('month', v.fecha)::date mes, sum(v.boxes) cajas
    from public.gv_ventas_cliente v group by 1, 2, 3
), corte as (
  -- UN solo corte calendario para todos: para ver si un cliente paso de LK a
  -- Chef hay que mirar las dos empresas en los MISMOS meses
  select max(mes) mes_corte from m
), kk as (
  select m.cliente_id, m.empresa,
         (extract(year  from age((select mes_corte from corte), m.mes)) * 12
        + extract(month from age((select mes_corte from corte), m.mes)))::int as k,
         sum(m.cajas) cajas
    from m group by 1, 2, 3
), serie as (
  select c.cliente_id, e.empresa, g.k, coalesce(sum(kk.cajas), 0) cajas,
         ((select mes_corte from corte) - (g.k || ' months')::interval)::date as mes
    from (select distinct cliente_id from m) c
    cross join (values ('lk'), ('chef')) e(empresa)
    cross join generate_series(0, 25) g(k)
    left join kk on kk.cliente_id = c.cliente_id and kk.empresa = e.empresa and kk.k = g.k
   group by 1, 2, 3, 5
), roll as (
  select cliente_id, empresa, k, mes,
         sum(cajas) over (partition by cliente_id, empresa order by k
                          rows between current row and 2 following) trim_emp
    from serie
), tot as (
  select cliente_id, k, min(mes) mes,
         sum(trim_emp)                               as trimestre,
         sum(trim_emp) filter (where empresa = 'lk')   as trim_lk,
         sum(trim_emp) filter (where empresa = 'chef') as trim_ch
    from roll group by 1, 2
), pico as (
  -- el pico se busca en ventanas que NO solapan con el trimestre actual
  -- (terminan 3 meses o mas atras): si no, un cliente que compra a saltos
  -- "cae" siempre
  select distinct on (cliente_id) cliente_id, mes mes_pico,
         trimestre pico, trim_lk pico_lk, trim_ch pico_ch
    from tot where k between 3 and 21 order by cliente_id, trimestre desc, k
), act as (
  select cliente_id, trimestre trim_actual, trim_lk act_lk, trim_ch act_ch from tot where k = 0
), gap as (
  -- el feed de Chef no llega hasta el corte general Y el cliente factura por
  -- Chef: ahi la caida puede ser mentira y no hay con que probarlo.
  -- Al 14/09 los dos feeds llegan a 2026-08, asi que no marca a nadie.
  select c.cliente_id,
         (exists (select 1 from m where m.cliente_id = c.cliente_id and m.empresa = 'chef'
                    and m.mes > (select mes_corte from corte) - interval '12 months')
          and (select mes_corte from public.gv_ventas_corte_empresa where empresa = 'chef')
              < (select mes_corte from corte)
         ) as chef_incompleto
    from (select distinct cliente_id from m) c
)
select n.cliente, a.cliente_id,
       a.trim_actual::int, p.pico::int, to_char(p.mes_pico, 'YYYY-MM') as mes_pico,
       round(100.0 * (a.trim_actual - p.pico) / nullif(p.pico, 0))::int as caida_pct,
       a.act_lk::int as lk_ahora, p.pico_lk::int as lk_pico,
       a.act_ch::int as ch_ahora, p.pico_ch::int as ch_pico,
       case when a.act_lk < p.pico_lk and a.act_ch > p.pico_ch then 'pasó de LK a Chef'
            when a.act_ch < p.pico_ch and a.act_lk > p.pico_lk then 'pasó de Chef a LK'
            else null end as migracion,
       g.chef_incompleto,
       (select max(fecha) from public.gv_ventas_cliente v where v.cliente_id = a.cliente_id) as ultima_compra
  from act a
  join pico p using (cliente_id)
  join gap  g using (cliente_id)
  join (select distinct cliente_id, cliente from public.gv_cliente_canon) n on n.cliente_id = a.cliente_id
 where a.trim_actual > 0 and p.pico > 0;

comment on view public.gv_clientes_riesgo is
  'v16.99 - clientes cayendo, por CUIT y con las dos empresas en los mismos meses. migracion avisa si la venta se paso de una empresa a la otra (no cayo); chef_incompleto avisa que al feed de Chef le faltan meses. Filtro tipico: pico >= 300 and caida_pct <= -30.';

-- ---------------------------------------------------------------------------
-- Medido al 2026-09-14 (pico >= 300 y caida <= -30 %):
--   40 clientes en la alarma · 3 con migracion · 7 con chef_incompleto ·
--   33 caida limpia. Los 3 + 7 son TODOS del artefacto julio_26 / ago-26.
--   Cencosud: 3.965 vs 4.664 = -15 %, todo por Chef, sin migracion -> NO esta
--   cayendo, y no aparece en la alarma. Relca no aparece: no vende por LK.
-- ---------------------------------------------------------------------------

-- ============================================================================
-- ANEXO v16.99 — julio y agosto de Chef estaban cargados como LK
--
-- Thomas (14/09): "datos de agosto de chef deberíamos tener". Tenia razon:
-- estaban, pero adentro de los batches `julio_26` y `ago-26`, con empresa='lk'.
--
-- COMO SE PROBO. `junio_26` es carga PURA de LK y `chef_hist_xlsx_202607` es la
-- carga propia de Chef, asi que sirven de patron:
--   - Hay 20 articulos que en junio vendio SOLO Chef (701, 706, 718, 722, 723,
--     725E, 727E, 731, 735, 801, 825, 839, 840, 859, 862, 901, 908, 909, 922,
--     936E...). En `junio_26` (LK puro) aparecen en CERO filas. En `julio_26`
--     aparecen en 314 filas y en `ago-26` en 370.
--   - Casi todos esos codigos ya venian en la carga propia de Chef de junio, y
--     la mayoria no tiene ni nombre en el padron de LK.
--
-- REGLA APLICADA (conservadora): el codigo se marca como Chef si
--   (A) compro algun articulo que solo vende Chef, O
--   (B) el codigo ya venia en `chef_hist_xlsx_202607`,
-- Y ADEMAS no aparece en `junio_26` (que es carga pura de LK). Esa ultima
-- condicion deja afuera los ambiguos — un codigo que factura de los dos lados —
-- que quedan como LK hasta que alguien los mire de verdad.
--
-- RESULTADO: 67 filas en GV_Ventas_Correccion. Chef pasa a tener
-- julio 3.802 cajas / 29 clientes y agosto 5.220 / 35, contra junio 3.873 / 46
-- de su propia carga: el mismo orden de magnitud.
--
-- EFECTO EN LA ALARMA (pico >= 300, caida <= -30 %): 39 clientes, 0 con
-- `chef_incompleto` (los dos feeds llegan a 2026-08) y 0 falsas migraciones.
-- Dorinka queda 100 % Chef y su caida es real (-55 %); Clapera pasa de -88 % a
-- -41 % porque le aparecieron julio y agosto.
--
-- MIGRACIONES REALES que quedan a la vista (antes invisibles):
--   Horcada Marcelo   lk:85   -> chef:85    LK 1.194 -> 0, Chef 0 -> 939  (-21 %, NO cayo)
--   Grupo Maravillas  lk:2469 -> chef:1980  LK 134 -> 0,   Chef 0 -> 37   (-72 %, migro Y cayo)
--   Supermercado Remo lk:3972 +  chef:448   LK 107 -> 74,  Chef 0 -> 471  (+409 %)
--   13 clientes con migracion en total; 11 sin caida.
--
-- ROLLBACK: delete from public."GV_Ventas_Correccion"
--            where import_batch in ('julio_26','ago-26') and empresa_real = 'chef';
--           (ojo: eso borra tambien las dos filas del 2444/Cencosud de la v16.93)
-- ============================================================================

with ch_items as (
  select item_code from public.sales_lines
   where import_batch = 'chef_hist_xlsx_202607' and invoice_date::date between '2026-06-01' and '2026-06-30'
  except
  select item_code from public.sales_lines where import_batch = 'junio_26'
), a as (
  select distinct s.import_batch, s.customer_code
    from public.sales_lines s join ch_items i on i.item_code = s.item_code
   where s.import_batch in ('julio_26','ago-26')
), b as (
  select distinct s.import_batch, s.customer_code
    from public.sales_lines s
   where s.import_batch in ('julio_26','ago-26')
     and s.customer_code in (select customer_code from public.sales_lines where import_batch = 'chef_hist_xlsx_202607')
), lk_vivo as (
  select distinct customer_code from public.sales_lines where import_batch = 'junio_26'
), final as (
  select u.import_batch, u.customer_code,
         (u.customer_code in (select customer_code from a where a.import_batch = u.import_batch)) sig_item,
         (u.customer_code in (select customer_code from b where b.import_batch = u.import_batch)) sig_padron
    from (select * from a union select * from b) u
   where u.customer_code not in (select customer_code from lk_vivo)
)
insert into public."GV_Ventas_Correccion" (import_batch, customer_code, empresa_real, duplicado, motivo, creado_por)
select f.import_batch, f.customer_code, 'chef', false,
  'Factura de Chef cargada con empresa=lk. Senales: '
   || case when f.sig_item and f.sig_padron then 'compro articulos que solo vende Chef Y el codigo ya venia en la carga propia de Chef'
           when f.sig_item then 'compro articulos que solo vende Chef'
           else 'el codigo ya venia en la carga propia de Chef (chef_hist_xlsx_202607)' end
   || '; y el codigo NO aparece en junio_26, que es carga pura de LK. Cliente Chef: '
   || coalesce((select p.business_name from public.chef_padron p where p.cod_cliente::text = f.customer_code), '(sin nombre)') || '.',
  'Claude (pedido de Thomas 14/09)'
  from final f
 on conflict (import_batch, coalesce(customer_code,'*')) do nothing;

-- ============================================================================
-- CORRECCION v17.10 — la señal (B) sola no alcanzaba: se sacaron 14 filas
--
-- Thomas pidio un dry run antes de tocar la carga. Haciendolo aparecio una
-- fuente INDEPENDIENTE que no se habia usado: `public.fact_live`, que el cron 38
-- refresca cada 30 min desde `virgilio.comprobantes_venta` y que trae la empresa
-- del campo `marca` del comprobante ('CH' -> chef). O sea: Gestion ya sabe, por
-- cada comprobante, de que empresa es.
--
-- Cruzado contra el anexo anterior, delataba 12 codigos mal marcados. Mirando
-- sus articulos se ve el error: son 5xx/3xx del catalogo de Loekemeyer, SIN
-- sufijo L (ej. 448 = 34, 057, 248, 315, 501..; 85 = 248, 392, 501, 502, 505..).
-- Son ventas de LK.
--
-- CAUSA: la señal (B) del anexo — "el codigo ya venia en la carga propia de
-- Chef" — no prueba nada por si sola. Un mismo numero es un cliente en LK y
-- otro en Chef (justo lo que dispara todo este trabajo), asi que que el numero
-- aparezca en Chef no hace de Chef a ESTAS filas.
--
-- REGLA NUEVA: (B) ya no alcanza sola. Se conserva la marca solo si ademas hay
-- evidencia propia de las filas:
--    * todas sus lineas llevan sufijo L  (se facturo por Chef), o
--    * la mitad o mas de sus lineas son articulos que LK no vende, o
--    * el codigo no existe en el padron de LK y si en el de Chef.
-- Se borraron 14 filas (1.780 cajas) que no cumplian ninguna.
--
-- VALIDACION contra fact_live despues del borrado: julio 25 ok / 0 discrepan,
-- agosto 25 ok / 0 discrepan. Antes: 3 y 9 discrepancias.
--
-- QUE CAMBIA EN LOS NUMEROS: Chef queda julio 3.242 y agosto 4.000 cajas
-- (contra junio 3.873 de su propia carga). Y se cae la "migracion" de Horcada
-- Marcelo y de Supermercado Remo: eran de este error, no movimientos reales.
-- Las 471 cajas de agosto del cod 448 vuelven a M.Sanchez (LK), que es de quien
-- son.
-- ============================================================================

with ch_items as (
  select item_code from public.sales_lines
   where import_batch = 'chef_hist_xlsx_202607' and invoice_date::date between '2026-06-01' and '2026-06-30'
  except
  select item_code from public.sales_lines where import_batch = 'junio_26'
), ev as (
  select f.id,
         count(s.*)                                      filas,
         count(*) filter (where s.item_code ~ 'L$')      filas_L,
         count(*) filter (where i.item_code is not null) filas_chef,
         (lkp.cod is null)     sin_padron_lk,
         (chp.cod is not null) en_padron_chef
    from public."GV_Ventas_Correccion" f
    join public.sales_lines s on s.import_batch = f.import_batch and s.customer_code = f.customer_code
    left join ch_items i on i.item_code = s.item_code
    left join (select cod_cliente::text cod from public.customers)   lkp on lkp.cod = f.customer_code
    left join (select cod_cliente::text cod from public.chef_padron) chp on chp.cod = f.customer_code
   where f.import_batch in ('julio_26','ago-26')
   group by f.id, lkp.cod, chp.cod
)
delete from public."GV_Ventas_Correccion" f
 using ev
 where f.id = ev.id
   and ev.filas_L <> ev.filas
   and ev.filas_chef * 2 < ev.filas
   and not (ev.sin_padron_lk and ev.en_padron_chef);

-- Chequeo contra la fuente independiente (tiene que dar 0 discrepancias):
--   with sl as (select s.customer_code cod, to_char(s.invoice_date::date,'YYYY-MM') ym,
--                      bool_or(f.customer_code is not null) marcado_chef
--                 from public.sales_lines s
--                 left join public."GV_Ventas_Correccion" f
--                   on f.import_batch = s.import_batch and f.customer_code = s.customer_code
--                where s.import_batch in ('julio_26','ago-26') group by 1,2),
--        fl as (select cod_cliente cod, ym, bool_or(empresa='chef') en_chef
--                 from public.fact_live where clase='FC' group by 1,2)
--   select sl.ym, count(*) filter (where sl.marcado_chef and fl.en_chef) ok,
--          count(*) filter (where sl.marcado_chef and fl.cod is not null and not fl.en_chef) discrepan
--     from sl left join fl on fl.cod = sl.cod and fl.ym = sl.ym group by 1;
