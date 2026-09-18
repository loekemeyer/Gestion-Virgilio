-- v19.77 — Los dos centinelas de stock: el de etiqueta de empresa dejaba de servir, y
-- faltaba el que caza el picking duplicado por renombre de tanda.
-- Problemas 416 y 420. §3.jj de docs/SUPABASE-GESTION-VIRGILIO.md
--
-- 1) gv_stock_empresa_fantasma
--    Calculaba fantasma = sum(greatest(saldo,0)) - sum(saldo) por (cod, deposito). Con UNA
--    sola empresa y saldo negativo eso da 0 - (-N) = N, o sea que disparaba con cualquier
--    sobre-pickeo aunque no existiera ninguna pila positiva del otro lado y por lo tanto
--    ninguna caja fantasma. Medido el 18/09: 5 filas, 0 con dos empresas. Un centinela que
--    CLAUDE.md declara "vacia = todo bien" y esta permanentemente rojo no lo mira nadie, y
--    el split real (el de D72A, problema 390) pasa de largo.
--    Ahora fantasma = least(positivo, negativo): son las cajas que una etiqueta muestra en
--    positivo mientras la otra las debe. Con una sola pila da 0 y la fila no sale.
--    Los negativos comunes ya los lista gv_stock_negativos, con descripcion y que hacer.
--
-- 2) gv_stock_picking_duplicado (NUEVO)
--    gv_ppp_tanda_renombrar renombra los eventos de ciclo (EP/TP/AP/TAP/PUB/AUB por el
--    update de texto exacto; ENT/TAL por gv_evento_set_tanda) pero NO los PKC:
--    gv_evento_tanda('PKC', ...) devuelve NULL. reconciliar_pipeline_stock_etapa1 (cron 68,
--    cada 10 min) deriva la tanda del campo 1 del PKC, no encuentra filas con ese ref
--    -el renombre las movio- y las INSERTA de nuevo. mov_stock_pipeline_dedup no lo frena
--    porque el ref es distinto. El 18/09 duplico 4 tandas: +461 cajas en Pickeados y
--    -443 en gondola.
--    La firma es precisa y por eso no tiene falsos positivos: misma huella de picking,
--    el codigo fantasma tiene los PKC, el vivo no tiene NINGUNO, y el fantasma ya no esta
--    en ninguna programacion. Sin la condicion de los PKC salian ademas dos pares viejos
--    (D19A/C83C, D10F/C80E) que son coincidencia: un solo codigo, una sola caja, y cada
--    tanda con su propio PKC.

create or replace view public.gv_stock_empresa_fantasma as
with e as (
  select regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') as cod,
         m.deposito,
         coalesce(nullif(m.empresa, ''), 'Mixto') as empresa,
         sum(m.delta) as saldo,
         max(m.ts) as ultimo
    from public."Movimientos_Stock" m
   where m.deposito = any (array['a_guardar','terminado','excedente','racks','racks_ch','para_envasar'])
   group by 1, 2, 3
), t as (
  select e.cod, e.deposito,
         sum(e.saldo) as total,
         sum(greatest(e.saldo, 0)) as positivo,
         -sum(least(e.saldo, 0)) as negativo
    from e group by 1, 2
), du as (
  select distinct regexp_replace(upper(btrim(codigos_duales.cod)), '^0+(?=.)', '') as cod
    from public.codigos_duales
)
select t.cod, t.deposito, t.total, t.positivo,
       least(t.positivo, t.negativo) as fantasma,
       du.cod is not null as es_dual,
       case when du.cod is not null
              then 'REAL: el codigo es dual, son dos pilas separadas'
            else 'etiqueta: codigo no dual, una sola pila' end as riesgo,
       (select string_agg((e2.empresa || ': ') || e2.saldo, '  ' order by e2.empresa)
          from e e2 where e2.cod = t.cod and e2.deposito = t.deposito and e2.saldo <> 0) as detalle,
       (select max(e3.ultimo) from e e3
         where e3.cod = t.cod and e3.deposito = t.deposito and e3.saldo < 0) as ultimo_negativo
  from t left join du on du.cod = t.cod
 where least(t.positivo, t.negativo) > 0;

alter view public.gv_stock_empresa_fantasma set (security_invoker = true);

create or replace view public.gv_stock_picking_duplicado as
with p as (
  select upper(btrim(m.ref)) as tanda,
         count(*) as codigos,
         sum(m.delta) as cajas,
         md5(string_agg(regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') || ':' || m.delta, ','
             order by regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', ''))) as huella,
         min(m.ts) as primer_mov
    from public."Movimientos_Stock" m
   where m.tipo = 'picking' and m.deposito = 'separar_pedidos'
     and m.ts >= now() - interval '90 days'
     and upper(btrim(coalesce(m.ref, ''))) ~ '^[A-Z][0-9]{2}[A-Z]$'
   group by 1
), pk as (
  select upper(btrim(split_part(r.texto, '|', 1))) as tanda, count(*) as n
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'PKC' group by 1
)
select a.tanda      as tanda_fantasma,
       b.tanda      as tanda_viva,
       a.codigos,
       a.cajas,
       a.primer_mov as fantasma_desde,
       b.primer_mov as viva_desde,
       (select coalesce(sum(m2.delta), 0) from public."Movimientos_Stock" m2
         where m2.tipo = 'picking' and m2.deposito = 'terminado'
           and upper(btrim(m2.ref)) = a.tanda) as gondola_de_mas,
       'El picking de una misma tanda esta contado DOS veces, con dos codigos. Pasa al renombrar una tanda: los eventos PKC se quedan con el codigo viejo (gv_evento_tanda no los resuelve para PKC) y el cron 68 vuelve a insertar las filas con ese codigo. Firma: el codigo fantasma tiene los PKC, el vivo no tiene ninguno, y el fantasma ya no esta en ninguna programacion.' as que_significa
  from p a
  join p b on a.huella = b.huella and a.primer_mov > b.primer_mov
  join pk ka on ka.tanda = a.tanda
 where coalesce((select n from pk where pk.tanda = b.tanda), 0) = 0
   and not exists (select 1 from public."PPP_Web_Programacion" w where upper(btrim(w.tanda)) = a.tanda)
   and not exists (select 1 from public."GV_PPP_Programacion_Diaria" d where upper(btrim(d.tanda)) = a.tanda);

alter view public.gv_stock_picking_duplicado set (security_invoker = true);
grant select on public.gv_stock_picking_duplicado to anon, authenticated;

-- PRUEBA del centinela de etiqueta: se rompe a proposito, dentro de un bloque que aborta.
-- Tiene que salir 1 fila con fantasma=5. Leer la vista no prueba nada.
-- do $$
-- declare v int; f numeric;
-- begin
--   insert into public."Movimientos_Stock"(cod_art,deposito,delta,tipo,ref,legajo,empresa)
--   values ('__TESTFANT__','terminado', 5,'ajuste','__PRUEBA_FANT_A__','t','LK'),
--          ('__TESTFANT__','terminado',-5,'ajuste','__PRUEBA_FANT_B__','t','CH');
--   select count(*), max(fantasma) into v, f
--     from public.gv_stock_empresa_fantasma where cod='__TESTFANT__';
--   raise exception 'PRUEBA -> filas=% fantasma=%', v, f;
-- end $$;

-- CHEQUEOS
-- select * from public.gv_stock_empresa_fantasma;    -- vacia = ninguna etiqueta partida
-- select * from public.gv_stock_picking_duplicado;   -- vacia = ningun picking contado dos veces
-- select * from public.gv_stock_negativos;           -- los sobre-pickeos comunes viven aca
