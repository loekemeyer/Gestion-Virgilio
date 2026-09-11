-- =====================================================================
-- gv_reconciliar_aguardar.sql — idea 4259 (2026-09-11)
-- COMPLETAR DESDE "A GUARDAR" en la fase de picking (pop-up al cerrar).
--
-- Problema que resuelve: hoy el picking descuenta SIEMPRE de góndola. Si el
-- operario agarra una caja que físicamente está en "a guardar" (recepción sin
-- bajar a góndola), el sistema igual descuenta góndola → góndola negativa y
-- a_guardar inflado (caso 395 / NP 98613 / D68F, 2026-09-10).
--
-- Modelo (pedido del dueño, 2026-09-11): al terminar de agarrar todos los
-- códigos del picking, el sistema mira los FALTANTES que tienen saldo SOLO en
-- "a guardar" (racks NO — el excedente ya se usa en la fase 1 del picking) y
-- salta un pop-up para ir a buscarlos. El operario marca cuántas agarró y el
-- movimiento es:
--     a_guardar        -N
--     separar_pedidos  +N   (queda en "Pickeados" y sigue el pipeline normal:
--                            armado TAP → a_facturar → facturado)
-- Góndola NO se toca.
--
-- Event-sourced, mismo patrón que PKC (single writer server-side):
--  · El front emite un evento opcion='PKA', texto = "TANDA|ART|N" (N = TOTAL
--    absoluto agarrado de a_guardar para ese art en esa tanda). Respeta el
--    legajo de prueba (no persiste) y la cola offline, igual que PKC.
--  · Esta función lee los PKA (último por tanda|art = total absoluto) y hace el
--    UPSERT idempotente de las dos filas con tipo='aguardar'. Recalcula cada
--    corrida (DO UPDATE) → re-marcar o corregir la cantidad no descuenta de más.
--  · Clamp por artículo al a_guardar DISPONIBLE (excluyendo nuestras propias
--    filas 'aguardar'), con ventana por tanda → nunca deja a_guardar negativo.
--
-- Por qué tipo='aguardar' (NO 'picking'): la reconciliación de picking
-- (reconciliar_pipeline_stock_etapa1, rama B.3) recalcula 'terminado' como
-- -(separar_pedidos + excedente) mirando SOLO filas tipo='picking'. Si estas
-- filas fueran 'picking', ese +N de separar_pedidos volvería a descontar
-- góndola. Con tipo propio quedan fuera de ese cálculo → góndola intacta.
--
-- Objeto NUEVO con prefijo gv_ (no toca objetos de Producción). Índice de dedup
-- propio (no pisa mov_stock_pipeline_dedup). Cron con prefijo gv-.
-- Rollback: ver docs/ROLLBACK-PRODUCCION.md.
-- =====================================================================

-- 1) Índice de dedup propio para las filas de completar-desde-a_guardar.
--    Una fila por (tanda, art, empresa, depósito) con tipo='aguardar'.
create unique index if not exists mov_stock_aguardar_dedup
  on public."Movimientos_Stock" (upper(btrim(ref)), upper(btrim(cod_art)), coalesce(empresa, ''::text), deposito)
  where tipo = 'aguardar';

-- 2) Reconciliador.
create or replace function public.gv_reconciliar_aguardar()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_cutoff timestamptz; n int := 0;
begin
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='cutoff_ts'),
                  '2026-06-26 00:01:00-03'::timestamptz) into v_cutoff;

  with pka as (
    -- último PKA por (tanda, art) = total ABSOLUTO agarrado de a_guardar
    select upper(btrim(split_part(texto,'|',1))) tanda,
           upper(btrim(split_part(texto,'|',2))) art,
           (array_agg(coalesce(nullif(regexp_replace(split_part(texto,'|',3),'[^0-9.\-]','','g'),'')::numeric, 0)
                      order by ts_cliente desc nulls last))[1] as n,
           (array_agg(legajo::text order by ts_cliente desc nulls last))[1] as leg
    from "Registros_Produccion_Virgilio"
    where opcion='PKA'
      and coalesce(split_part(texto,'|',2),'') <> ''
      and ts_cliente >= v_cutoff
    group by 1,2
  ),
  ag as (
    -- a_guardar DISPONIBLE por art, EXCLUYENDO nuestras propias filas 'aguardar'
    -- (si no, cada corrida se auto-restringiría con lo que ya bajó)
    select upper(btrim(cod_art)) art,
           sum(delta) filter (where not (tipo='aguardar')) as disp
    from "Movimientos_Stock"
    where deposito='a_guardar'
    group by 1
  ),
  alloc as (
    -- clamp: no más que lo agarrado (n) ni que el a_guardar disponible;
    -- ventana por tanda para no repartir el mismo a_guardar a dos tandas
    select p.tanda, p.art, p.leg,
           least(
             greatest(p.n, 0),
             greatest(0, coalesce(a.disp, 0)
               - coalesce(sum(greatest(p.n,0)) over (partition by p.art order by p.tanda
                          rows between unbounded preceding and 1 preceding), 0))
           ) as q
    from pka p
    left join ag a on a.art = p.art
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  select art, 'a_guardar',       -q, 'aguardar', tanda, coalesce(leg,'pipeline') from alloc
  union all
  select art, 'separar_pedidos',  q, 'aguardar', tanda, coalesce(leg,'pipeline') from alloc
  on conflict (upper(btrim(ref)), upper(btrim(cod_art)), coalesce(empresa, ''::text), deposito)
    where tipo = 'aguardar'
  do update set delta = excluded.delta, legajo = excluded.legajo;

  get diagnostics n = row_count;
  return n;
end
$$;

-- 3) Solo el cron (postgres) la corre. La anon key NO.
revoke all on function public.gv_reconciliar_aguardar() from public;
revoke all on function public.gv_reconciliar_aguardar() from anon;
revoke all on function public.gv_reconciliar_aguardar() from authenticated;

-- 4) Cron cada 2 min (prefijo gv-). Idempotente, barato (pocos PKA por día).
--    (ejecutar por separado; cron.schedule falla si ya existe con ese nombre)
-- select cron.schedule('gv-reconciliar-aguardar', '*/2 * * * *',
--                       $$ select public.gv_reconciliar_aguardar(); $$);
