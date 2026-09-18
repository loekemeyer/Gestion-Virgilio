-- v19.80 — El evento PKC lleva la tanda en el CAMPO 1 y nadie lo renombraba (problemas 420 y 421)
-- ============================================================================================
-- SINTOMA: al renombrar («📅 Cambiar de día») o fusionar una tanda, 10 minutos después el picking
-- reaparecía bajo el código VIEJO, y la fusión se deshacía sola. Al 18/09: 7 pares de tandas con
-- el mismo picking contado dos veces, 868 cajas fantasma y 843 cajas de menos en góndola.
--
-- CAUSA: `gv_evento_tanda_campo` no declaraba PKC, así que ni el UPDATE de
-- `gv_ppp_tanda_renombrar` ni el de `gv_ppp_nps_mover_a` lo alcanzaban (el primer UPDATE de
-- renombrar sólo matchea cuando el texto ENTERO es la tanda, y un PKC es `tanda|art|…`).
-- Los PKC quedaban con el código viejo y el cron 68 (`reconciliar_pipeline_stock_etapa1`) volvía
-- a insertar el picking con ese código. Y peor: el upsert de la etapa1 hace
-- `DO UPDATE SET delta = excluded.delta`, o sea que además PISA la suma de la fusión.
--
-- MEDIDO en transacción abortada, ANTES del fix:
--   fusión   E12M -> E12I : 40+38=78  -> renombrado 0/78  -> tras el cron 40/48 = 88  (+10)
--   renombre E12M -> ZZ9Z : 40        -> renombrado 0/40  -> tras el cron 40/40 = 80  (duplicado)
-- Y DESPUÉS del fix, contra la función ya aplicada:
--   fusión   E12M -> E12I : 78 -> 78   ✅
--   renombre E12J -> ZZ9Z : 100 -> 100 ✅
--
-- ⚠ NO afecta a `gv_ppp_nps_mover_a`, el otro llamador: filtra por campo 1 = NP, y PKC/PSP/FGU/
-- SSG/RAG llevan ahí la TANDA, que nunca tiene formato de NP (`LK 0006`, `98615`). Medido
-- moviendo LK 0029 de E12A: 66 PKC antes, 66 después, 0 migrados.
--
-- ⚠ TP/TAP/AP/EP/PUB/AUB/APX/EPX NO van acá: su texto ES la tanda sola y ya los agarra el primer
-- UPDATE de `gv_ppp_tanda_renombrar`. El censo del 18/09 sobre los eventos desde el 01/09 dice
-- qué opción lleva la tanda en qué campo; los que faltaban son exactamente estos cinco.

create or replace function public.gv_evento_tanda_campo(p_opcion text)
returns integer language sql immutable as $function$
  select case upper(btrim(coalesce(p_opcion, '')))
           when 'CCN' then 2 when 'CCR' then 2 when 'CRN' then 2 when 'FSS' then 2
           when 'CRA' then 2 when 'FCO' then 2 when 'ENT' then 2
           when 'TAL' then 3
           when 'FAL' then 5
           when 'NPD' then 7
           -- v19.80: tanda en el campo 1
           when 'PKC' then 1 when 'PSP' then 1 when 'FGU' then 1
           when 'SSG' then 1 when 'RAG' then 1
           else null
         end;
$function$;

-- Centinela: si alguien vuelve a sacar PKC de acá, `gv_reglas_perdidas` lo grita.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_evento_tanda_campo','funcion','''PKC''\s+then\s+1',
 'Los eventos que llevan la tanda en el campo 1 (PKC, PSP, FGU, SSG, RAG) tienen que estar declarados aca, o al renombrar/fusionar una tanda sus PKC se quedan con el codigo viejo y el cron 68 vuelve a insertar el picking con ese codigo: 849 cajas duplicadas en 7 tandas al 18/09. Problemas 420 y 421.',
 'Thomas','v19.80')
on conflict do nothing;

-- ============================================================================================
-- LIMPIEZA de los 4 pares con diagnóstico cerrado (461 cajas)
-- ============================================================================================
-- La firma que los separa de los otros 3: el fantasma quedó SÓLO con PKC y PSP — sus TP/TAP/AP/
-- EP/PUB sí viajaron a la tanda viva, que es justo lo que hace `gv_ppp_tanda_renombrar`. En
-- E12A/E12S, E12E/E37F y E12J/E12G hay TP de los DOS lados: ésos no pasaron (sólo) por un
-- renombre y se dejaron abiertos a propósito.
--
-- Backups (los eventos son lo único que NO se recalcula; el stock de picking sale de ellos):
--   zz_backups."GV_Backup_PKC_Fantasma_20260918"       118 filas
--   zz_backups."GV_Backup_MovStock_Fantasma_20260918"  962 filas
--
-- Se corrió como un bloque único que se abortaba solo si los números no cerraban:
--   · los eventos del fantasma pasan a la viva (ahora sí, porque la función de arriba ya los cubre)
--   · se borra el picking duplicado del fantasma en separar_pedidos/terminado/excedente
--   · ⚠ los `facturado` con ref `tanda|NP` NO se tocan: son el problema 417, aparte
--   · se corre la etapa1 y se recalcula `stocks_carga_rapida` de cada código tocado
--     (`trigger_actualizar_saldo_stock` es AFTER INSERT OR UPDATE y NO corre en DELETE)
--   · guardas: 0 filas de picking fantasma, las tandas vivas con las MISMAS cajas que antes,
--     y el centinela bajando de 7 a 3
--
-- Resultado verificado corriendo `reconciliar_pipeline_stock()` de verdad después: los fantasmas
-- NO vuelven. E12R 184 · E44A 149 · E40A 78 · E41A 50, intactas.
--
--   E03F -> E12R   50 eventos   184 cajas
--   E03G -> E44A   35 eventos   149 cajas
--   D71B -> E40A   25 eventos    78 cajas
--   E11B -> E41A    5 eventos    50 cajas

-- Chequeo (tiene que dar 3, y ninguno de los 4 de arriba):
--   select * from public.gv_stock_picking_duplicado;
--   select * from public.gv_reglas_perdidas;        -- vacía

-- ============================================================================================
-- gv_stock_picking_duplicado v19.80 — la huella exacta se comía la mitad de los casos
-- ============================================================================================
-- La versión vieja exigía md5(set completo art:delta) idéntico Y que el fantasma no estuviera en
-- ninguna programación. Demasiado duro: al 18/09 marcaba 4 de 7 pares. Se le escapaban
-- E12A/E12S (el fantasma sigue programado y tiene 2 códigos de más), E12E/E37F y E12J/E12G —
-- y E12A/E12S es justo el peor, porque las DOS salen el 21/09 con el mismo picking.
--
-- ⚠ El fantasma es el MÁS NUEVO de los dos (lo re-crea el cron 68 cada 10 min), no el más viejo.
-- Copiar la comparación de fechas al revés deja la vista en cero, sin avisar. La firma nueva ya
-- es asimétrica por sí sola (la viva no tiene NINGÚN PKC, el fantasma sí), así que va sin fechas.
--
-- Calibrado el 18/09: devuelve exactamente los 7 pares reales, cero falsos positivos. Con solape
-- de >= 3 códigos a secas daban 300+, por coincidencia casual entre tandas viejas.

create or replace view public.gv_stock_picking_duplicado
with (security_invoker = true) as
with st as (
  select upper(btrim(m.ref)) tanda, upper(btrim(m.cod_art)) art, sum(m.delta) q, min(m.ts) primer_mov
    from public."Movimientos_Stock" m
   where m.tipo = 'picking' and m.deposito = 'separar_pedidos'
     and upper(btrim(coalesce(m.ref, ''))) ~ '^[A-Z][0-9]{2}[A-Z]$'
     and m.ts >= now() - interval '90 days'
   group by 1, 2 having sum(m.delta) <> 0
), pk as (
  select upper(btrim(split_part(r.texto, '|', 1))) tanda, count(*) n
    from public."Registros_Produccion_Virgilio" r where r.opcion = 'PKC' group by 1
), tot as (
  select tanda, count(*) cods, sum(q) cajas, min(primer_mov) primer_mov from st group by 1
)
select f.tanda                                   as tanda_fantasma,
       v.tanda                                   as tanda_viva,
       tf.cods                                   as codigos,
       tf.cajas                                  as cajas,
       tf.primer_mov                             as fantasma_desde,
       tv.primer_mov                             as viva_desde,
       (select coalesce(sum(m2.delta), 0) from public."Movimientos_Stock" m2
         where m2.tipo = 'picking' and m2.deposito = 'terminado'
           and upper(btrim(m2.ref)) = f.tanda)   as gondola_de_mas,
       'El picking de una misma tanda esta contado DOS veces, con dos codigos. Pasa al renombrar o '
       'fusionar una tanda: hasta la v19.80 los eventos PKC se quedaban con el codigo viejo porque '
       'gv_evento_tanda_campo no declaraba PKC, y el cron 68 volvia a insertar las filas con ese '
       'codigo (y encima pisaba la fusion, porque la etapa1 hace DO UPDATE SET delta). Firma: la '
       'tanda viva no tiene NINGUN PKC y el fantasma si, con el mismo picking.'::text as que_significa,
       round(100.0 * count(*) / tf.cods)         as pct_solape,
       exists (select 1 from public."PPP_Web_Programacion" w where upper(btrim(w.tanda)) = f.tanda)
    or exists (select 1 from public."GV_PPP_Programacion_Diaria" d where upper(btrim(d.tanda)) = f.tanda)
                                                 as fantasma_programado
  from st v
  join st f  on f.art = v.art and f.q = v.q and f.tanda <> v.tanda
  join tot tv on tv.tanda = v.tanda
  join tot tf on tf.tanda = f.tanda
 where coalesce((select n from pk where pk.tanda = v.tanda), 0) = 0
   and coalesce((select n from pk where pk.tanda = f.tanda), 0) > 0
 group by f.tanda, v.tanda, tf.cods, tf.cajas, tf.primer_mov, tv.primer_mov, tv.cods
having count(*) >= 3
   and 100.0 * count(*) / tv.cods >= 80
   and 100.0 * count(*) / tf.cods >= 80;

alter view public.gv_stock_picking_duplicado set (security_invoker = true);
