-- =====================================================================
--  reconciliar_pipeline_stock() — v16.92 (2026-09-14)
--
--  QUÉ SE ROMPIÓ (medido, no supuesto)
--  Al 14/09 había 13 códigos con saldo NEGATIVO, todos en el mismo depósito
--  (`a_facturar`, −1 o −2, 16 cajas), y su espejo positivo en `separar_pedidos`.
--  No era stock físico mal contado: era la MISMA caja descontada dos veces.
--
--    1. Varias NP quedaron armadas DOS veces (98490, 98532, 98533, 98583…).
--       Ej.: la NP 98532 se armó en la tanda D60E (09/09) y otra vez en E10A (11/09).
--    2. El 11/09 18:34 se corrigió a mano: 40 movimientos `ajuste` en `a_facturar`
--       (−57 cajas) con su contrapartida +57 en `separar_pedidos`, y el ref escrito
--       como TEXTO LIBRE: 'reversa armado duplicado NP 98490 tanda D47C (backup …)'.
--       El 13/09 00:38 se sumó otro igual (−1, 'correccion 221 NP 98532: …').
--    3. La ETAPA 3 calculaba el neto por tanda sumando SOLO 'separado' + 'facturado'.
--       Los 'ajuste' NO entraban → para esas tandas seguía viendo net>0 y volvía a
--       insertar el `facturado`. La ETAPA 4 sí sumaba 'ajuste', pero emparejaba por
--       `split_part(ref,'|',1)`, o sea sólo si el ref arranca con el NP: un ref de
--       texto libre tampoco entraba.
--    4. El cron 68 corrió el 14/09 06:21–06:40 y facturó de nuevo esas tandas
--       (refs D60E, E10A|98532, D72B|44613, D72C|44616, 98532|CP…) → negativo.
--
--  Tamaño real: de las 41 filas del ajuste manual, 36 (47 cajas) se drenaron DOS
--  veces — 13 cajas de tandas ya facturadas ANTES de la reversa y 34 de tandas que
--  el cron facturó DESPUÉS. Sólo 16 cajas quedaron visibles como negativo; las
--  otras 31 se comieron en silencio saldo de otras tandas del mismo código.
--
--  EL FIX (tres cosas)
--   (a) Las dos etapas suman `ajuste` además de separado/facturado/cp.
--   (b) Un `ajuste` se atribuye a su tanda/NP aunque el ref sea texto libre:
--       se extrae `tanda XXXX` / `NP NNNNN` con regex, y si no hay, se cae al
--       `split_part(ref,'|',1)` de siempre.
--   (c) CLAMP anti-negativo: el facturado que se inserta nunca puede superar el
--       saldo disponible del artículo en `a_facturar`. Si varias tandas del mismo
--       artículo entran en la misma corrida, el disponible se reparte con una
--       ventana acumulada (si no, todas verían el mismo disponible y sobre-drenarían).
--       Cuando hay que recortar, el ref lleva sufijo `|PARCIAL` para que se vea en
--       la auditoría; el guard por tanda lo sigue reconociendo porque compara por
--       `split_part(ref,'|',1)`.
--
--  (b) arregla la causa; (c) es el cinturón para cualquier ajuste futuro cuyo ref
--  no mencione ni tanda ni NP: con el clamp, `a_facturar` no puede quedar negativo.
--
--  Rollback: sql/backups/reconciliar_pipeline_stock_pre_v1692_20260914.sql
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cutoff timestamptz;
  n1 int := 0; n2 int := 0; n3 int := 0; n4 int := 0;
begin
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='cutoff_ts'),
                  '2026-06-26 00:01:00-03'::timestamptz)
    into v_cutoff;

  n1 := public.reconciliar_pipeline_stock_etapa1();
  n2 := public.reconciliar_pipeline_stock_etapa2();

  -- ETAPA 3 — FACTURADO. v12.44: guard por tanda en CUALQUIER empresa (evita doble
  -- drenaje contra un facturado por-NP Mixto ya existente). La empresa correcta la
  -- lleva el INSERT. v16.92: entra 'ajuste' (atribuido por regex si el ref es texto
  -- libre) y clamp contra el saldo disponible.
  with mov as (
    select m.cod_art art, coalesce(m.empresa,'Mixto') empresa, m.delta,
           case
             when m.tipo = 'separado' then upper(trim(m.ref))
             -- v16.92: un ajuste manual suele venir con ref de texto libre
             -- ('reversa armado duplicado NP 98490 tanda D47C (backup ...)').
             when m.tipo = 'ajuste'   then upper(coalesce(
                    nullif(substring(m.ref from 'tanda ([A-Za-z0-9]+)'), ''),
                    trim(split_part(m.ref, '|', 1))))
             else upper(trim(split_part(m.ref, '|', 1)))
           end tanda
    from "Movimientos_Stock" m
    where m.deposito = 'a_facturar' and m.tipo in ('separado','facturado','ajuste')
  ),
  src as (
    select tanda, art, empresa, sum(delta) net from mov group by 1,2,3
  ),
  -- v16.92: saldo REAL del articulo (todos los tipos), para no drenar de mas.
  saldo as (
    select cod_art art, coalesce(empresa,'Mixto') empresa, sum(delta) disp
    from "Movimientos_Stock" where deposito = 'a_facturar' group by 1,2
  ),
  tandanp as (
    select upper(btrim(tanda)) tanda, btrim(np) np from "GV_PPP_Entregados_Historico" where coalesce(btrim(np),'')<>''
    union select upper(btrim(tanda)), btrim(np) from "GV_PPP_Programacion_Diaria" where coalesce(btrim(np),'')<>''
  ),
  cand as (
    select s.tanda, s.art, s.empresa, s.net, sa.disp
    from src s
    join saldo sa on sa.art = s.art and sa.empresa = s.empresa
    where s.net > 0 and sa.disp > 0
      and not exists (select 1 from "Movimientos_Stock" m
                      where m.tipo='facturado' and m.deposito='a_facturar'
                        and (upper(trim(m.ref))=s.tanda or upper(trim(split_part(m.ref,'|',1)))=s.tanda))
      and exists (select 1 from tandanp pp where pp.tanda=s.tanda)
      and not exists (
        select 1 from tandanp pp
        where pp.tanda=s.tanda
          and not exists (select 1 from "Facturacion_NP" f where trim(f.np)=pp.np)
      )
  ),
  -- Reparte el disponible entre las tandas del mismo articulo+empresa que caen en
  -- ESTA corrida: sin la ventana acumulada todas verian el mismo `disp`.
  rep as (
    select c.*,
           greatest(0, least(c.net, c.disp - coalesce(sum(c.net) over (
             partition by c.art, c.empresa order by c.tanda
             rows between unbounded preceding and 1 preceding), 0))) drenar
    from cand c
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select r.art, 'a_facturar', -r.drenar, 'facturado',
         case when r.drenar < r.net then r.tanda||'|PARCIAL' else r.tanda end,
         'pipeline', r.empresa
  from rep r
  where r.drenar > 0
  on conflict do nothing;
  get diagnostics n3 = row_count;

  -- ETAPA 4 — CP. v12.44: guard por np/tanda en cualquier empresa.
  -- v16.92: el ajuste se empareja tambien por 'NP NNNNN' del texto libre, y clamp.
  with cp_nps as (
    select distinct upper(trim(split_part(ref,'|',1))) np
    from "Movimientos_Stock" where deposito='a_facturar' and tipo='cp'
  ),
  movcp as (
    select case
             when m.tipo = 'ajuste' then upper(coalesce(
                    nullif(substring(m.ref from 'NP ([0-9]+)'), ''),
                    trim(split_part(m.ref, '|', 1))))
             else upper(trim(split_part(m.ref, '|', 1)))
           end np,
           m.cod_art art, coalesce(m.empresa,'Mixto') empresa, m.delta
    from "Movimientos_Stock" m
    where m.deposito='a_facturar' and m.tipo in ('cp','facturado','ajuste')
  ),
  grp as (
    select np, art, empresa, sum(delta) net from movcp
    where np in (select np from cp_nps) group by 1,2,3
  ),
  saldo as (
    select cod_art art, coalesce(empresa,'Mixto') empresa, sum(delta) disp
    from "Movimientos_Stock" where deposito='a_facturar' group by 1,2
  ),
  cand as (
    select g.np, g.art, g.empresa, g.net, sa.disp
    from grp g
    join saldo sa on sa.art = g.art and sa.empresa = g.empresa
    where g.net > 0 and sa.disp > 0
      and not exists (select 1 from "Movimientos_Stock" m2 where m2.tipo='facturado'
                      and m2.ref = g.np||'|CP')
      and exists (select 1 from "Facturacion_NP" f where trim(f.np)=g.np)
  ),
  rep as (
    select c.*,
           greatest(0, least(c.net, c.disp - coalesce(sum(c.net) over (
             partition by c.art, c.empresa order by c.np
             rows between unbounded preceding and 1 preceding), 0))) drenar
    from cand c
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, ubicacion, legajo, empresa)
  select r.art, 'a_facturar', -r.drenar, 'facturado', r.np||'|CP', '__cp__', 'pipeline', r.empresa
  from rep r
  where r.drenar > 0
  on conflict do nothing;
  get diagnostics n4 = row_count;

  return format('ok etapa1=%s etapa2=%s etapa3=%s etapa4=%s cutoff=%s', n1, n2, n3, n4, v_cutoff::text);
exception when others then
  return 'error: '||sqlerrm;
end;
$function$;
