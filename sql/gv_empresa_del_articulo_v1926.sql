-- ════════════════════════════════════════════════════════════════════════════════════
-- v19.26 (Luis, 2026-09-16/17) — LA EMPRESA DE UN MOVIMIENTO LA DA EL ARTÍCULO
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Pedido textual de Luis: *"para todos los que no son duales, necesito que siempre viajen
-- con la empresa correspondiente (que es el dato que aparece ahí en la columna LK/CH)"* y
-- *"si tienen 438E para guardar sepan de qué empresa es y dónde lo tienen que poner"*.
--
-- ── El concepto, que es lo que costó entender ───────────────────────────────────────
-- Un código NO dual es UNA sola pila en UN solo estante, y el dueño es el ARTÍCULO, no el
-- pedido: un artículo de Loekemeyer que sale en un pedido de Chef SIGUE SIENDO de Loeke
-- (para eso existe el sufijo L — 505L es el 505 de Loeke facturado por Chef, y el picking
-- se hace igual de la góndola Loeke). Antes el trigger escribía 'Mixto' en esa rama y la
-- app etiquetaba por el PEDIDO, así que el saldo quedaba partido entre entradas sin
-- etiqueta y salidas etiquetadas al revés.
--
-- Los DUALES son otra cosa y NO se tocan: 437E, 438E, 439E y 809E son dos artículos
-- distintos con el mismo número (809E: Corta Queso en CH, Corta Pizza Familiar en LK).
-- Ahí la etiqueta dice de qué PILA salió la caja, y eso no se deduce del pedido.
--
-- ⚠⚠ LECCIÓN CARA DEL 16/09: se intentó etiquetar los movimientos viejos del 809E "por el
-- pedido" y se rompieron los números en pantalla (CH terminado pasó de 110 a −119). El
-- motivo: los movimientos anteriores al conteo del 01/08 ya SUMAN CERO —lo de antes
-- (+400 racks, +360 racks_ch, +79 góndola) lo cancela exacto el reset de ese día— así que
-- etiquetar una pata y dejar su contrapartida sin etiquetar inventa un negativo.
-- Regla que quedó: **a los duales no se les toca la etiqueta histórica.** Lo que necesitan
-- es un conteo físico, no una deducción.
--
-- ⚠⚠ Y LA OTRA: el índice único `mov_stock_pipeline_dedup` incluye `empresa`. Si la
-- historia dice CH y el trigger nuevo escribe LK, el ON CONFLICT del reconciliador NO
-- matchea y **duplica el picking**. Pasó de verdad: la corrida de las 18:20 del 16/09
-- re-insertó 126 filas de D72A y E11B. Por eso el orden de aplicación es obligatorio:
--   1) apagar los crons 34, 57, 68, 74, 81
--   2) poner el trigger
--   3) alinear la historia (las filas cuya empresa ≠ la del artículo)
--   4) correr los reconciliadores A MANO y confirmar 0 filas nuevas
--   5) recién ahí prender los crons
--
-- ════════════════════════════════════════════════════════════════════════════════════

-- ── 1. El caché artículo → empresa ──────────────────────────────────────────────────
-- Existe porque la versión "viva" cuesta 10,5 ms y el trigger corre en el camino caliente
-- del picking. Con el caché son 1,8 ms (un movimiento completo, con todos los triggers,
-- ~4 ms). Lo refresca el cron 92 cada 15 min.
create table if not exists public."GV_Articulo_Empresa_Cache" (
  cod_canon     text primary key,
  empresa       text not null check (empresa in ('LK','CH')),
  fuente        text,
  refrescado_at timestamptz not null default now()
);
alter table public."GV_Articulo_Empresa_Cache" enable row level security;
revoke insert, update, delete, truncate on public."GV_Articulo_Empresa_Cache" from anon, authenticated;
drop policy if exists gv_art_emp_cache_lectura on public."GV_Articulo_Empresa_Cache";
create policy gv_art_emp_cache_lectura on public."GV_Articulo_Empresa_Cache"
  for select to anon, authenticated using (true);

-- ── 2. La regla, en un solo lugar ───────────────────────────────────────────────────
-- Orden: la GÓNDOLA manda (es el dato que el operario ve en la columna LK/CH), después la
-- lista de precios para los códigos sin góndola, y último los racks.
-- Devuelve NULL a propósito para los DUALES (viven en las dos góndolas) y para los
-- huérfanos: ahí NO se inventa nada.
--
-- ⚠ NO usar `gv_articulo_empresa` (la vista vieja): dice que 439 códigos son LK y sólo 4
-- CH, porque toma `gv_uxb_lk` —que es la tabla de unidades por caja, no de propiedad—
-- como si fuera "es de LK", y los 101 códigos de Chef están todos ahí. No la lee nadie.
create or replace function public.gv_empresa_de_articulo_vivo(p_cod text)
returns text language sql stable as $fn$
  with base as (select regexp_replace(upper(btrim(regexp_replace(coalesce(p_cod,''),'([0-9E])L$','\1'))),'^0+(?=.)','') cc),
  gond as (select case when count(distinct g.empresa)=1 then min(g.empresa) end emp
             from public.gv_lugar_articulo g, base b
            where regexp_replace(upper(btrim(g.cod)),'^0+(?=.)','') = b.cc),
  lista as (select case when l and not c then 'LK' when c and not l then 'CH' end emp from (
              select exists(select 1 from public.precios_venta p, base b
                             where regexp_replace(upper(btrim(p.cod)),'^0+(?=.)','') = b.cc) l,
                     exists(select 1 from public.precios_venta_chef p, base b
                             where regexp_replace(upper(btrim(p.cod)),'^0+(?=.)','') = b.cc) c) z),
  -- v19.27: Racks_Planimetria, NO Ubicaciones_Articulos (esa quedo congelada el 10/08 y
  -- tiene codigos que no existen, como 809E-QUESO / 809E-PIZZA).
  racks as (select case when count(distinct replace(upper(r.emp),'LOKE','LK'))=1
                        then min(replace(upper(r.emp),'LOKE','LK')) end emp
              from public."Racks_Planimetria" r, base b
             where upper(r.emp) in ('LK','CH','LOKE')
               and regexp_replace(upper(btrim(r.cod_art)),'^0+(?=.)','') = b.cc)
  select coalesce((select emp from gond),(select emp from lista),(select emp from racks));
$fn$;
revoke execute on function public.gv_empresa_de_articulo_vivo(text) from anon, authenticated;

-- La que usa el trigger: lee el caché y, si el artículo no está cacheado (uno nuevo),
-- cae a la versión viva. Verificado: 0 diferencias entre las dos sobre los 357 códigos
-- que tienen movimientos.
create or replace function public.gv_empresa_de_articulo(p_cod text)
returns text language sql stable as $fn$
  select coalesce(
    (select c.empresa from public."GV_Articulo_Empresa_Cache" c
      where c.cod_canon = regexp_replace(upper(btrim(regexp_replace(coalesce(p_cod,''),'([0-9E])L$','\1'))),'^0+(?=.)','')),
    public.gv_empresa_de_articulo_vivo(p_cod));
$fn$;
revoke execute on function public.gv_empresa_de_articulo(text) from anon, authenticated;

-- ── 3. El refresco del caché (cron 92, cada 15 min) ─────────────────────────────────
create or replace function public.gv_refrescar_articulo_empresa()
returns integer language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare n int;
begin
  with gond as (
    select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cc,
           case when count(distinct empresa)=1 then min(empresa) end emp
      from public.gv_lugar_articulo group by 1),
  lkp as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cc from public.precios_venta where btrim(cod) <> ''),
  chp as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cc from public.precios_venta_chef where btrim(cod) <> ''),
  lista as (select coalesce(l.cc,c.cc) cc,
                   case when l.cc is not null and c.cc is not null then null
                        when l.cc is not null then 'LK' else 'CH' end emp
              from lkp l full join chp c on c.cc = l.cc),
  rck as (select regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') cc,
                 case when count(distinct replace(upper(emp),'LOKE','LK'))=1
                      then min(replace(upper(emp),'LOKE','LK')) end emp
            from public."Racks_Planimetria" where upper(emp) in ('LK','CH','LOKE') group by 1),
  todos as (select cc from gond union select cc from lista union select cc from rck),
  final as (
    select t.cc, coalesce(g.emp, li.emp, r.emp) emp,
           case when g.emp is not null then 'gondola'
                when li.emp is not null then 'lista_precios'
                when r.emp is not null then 'racks' end fuente
      from todos t
      left join gond  g  on g.cc  = t.cc
      left join lista li on li.cc = t.cc
      left join rck   r  on r.cc  = t.cc)
  insert into public."GV_Articulo_Empresa_Cache"(cod_canon, empresa, fuente, refrescado_at)
  select cc, emp, fuente, now() from final where emp is not null and cc <> ''
  on conflict (cod_canon) do update
     set empresa = excluded.empresa, fuente = excluded.fuente, refrescado_at = now();
  get diagnostics n = row_count;
  -- lo que dejo de estar (un articulo que salio de la gondola y de las listas) se borra
  delete from public."GV_Articulo_Empresa_Cache" where refrescado_at < now() - interval '1 second';
  return n;
end $fn$;
revoke execute on function public.gv_refrescar_articulo_empresa() from public, anon, authenticated;

select cron.schedule('gv-refrescar-articulo-empresa', '*/15 * * * *',
                     'select pg_advisory_xact_lock(5768); select public.gv_refrescar_articulo_empresa();');

-- ── 4. El trigger ───────────────────────────────────────────────────────────────────
-- Dos cambios respecto de la v18.86:
--   (a) la rama NO DUAL toma la empresa del artículo en vez de escribir 'Mixto', y sale
--       ahí mismo: no necesita heredar de la tanda ni del montón de A Guardar, porque el
--       artículo ya lo dice. Pisa lo que venga del front, que es el punto del pedido.
--   (b) la NP se busca en LOS DOS lados de la barra. El formato normal es TANDA|NP
--       (D33B|98329) pero también llega NP|TEXTO (44619|CP), y mirando sólo el segundo
--       campo esa fila caía en Mixto: la entrada quedaba CH y la salida sin empresa, y el
--       saldo del 438E se partía en +14 / −14 (eso es lo que Luis vio en pantalla).
--       El guard de largo 4-6 no es cosmético: sin él 'D33B' da "33" y un ref como
--       'D06E|FIX_..._20260811' da "20260811", que empresa_de_np resolvería como LK.
create or replace function public.trg_normalizar_empresa_stock()
 returns trigger language plpgsql as $function$
DECLARE v_base text; v_dual boolean; v_np text; v_emp2 text; v_explicita boolean; v_tanda text; v_art text;
BEGIN
  IF NEW.deposito = 'insumos' THEN
    NEW.cod_art := regexp_replace(NEW.cod_art,'\s+(LK|CH|LOKE)$','');
    RETURN NEW;
  END IF;

  v_explicita := NEW.empresa IS NOT NULL AND NEW.empresa IN ('LK','CH');

  IF NEW.cod_art ~ '\s+(LK|LOKE)$' THEN NEW.empresa:='LK'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+(LK|LOKE)$','');
  ELSIF NEW.cod_art ~ '\s+CH$' THEN NEW.empresa:='CH'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+CH$',''); END IF;
  IF NEW.cod_art ~ '[0-9E]L$' THEN
    NEW.empresa := 'LK';
    NEW.cod_art := regexp_replace(NEW.cod_art,'([0-9E])L$','\1');
    v_explicita := true;
  END IF;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)),'^0+(?=.)','');
  SELECT true INTO v_dual FROM public.codigos_duales WHERE regexp_replace(upper(btrim(cod)),'^0+(?=.)','')=v_base LIMIT 1;

  -- (a) v19.26 — código NO dual: manda el artículo
  IF NOT COALESCE(v_dual,false) THEN
    v_art := public.gv_empresa_de_articulo(NEW.cod_art);
    NEW.empresa := coalesce(v_art, nullif(NEW.empresa,''), 'Mixto');
    IF NEW.empresa NOT IN ('LK','CH') THEN NEW.empresa := 'Mixto'; END IF;
    RETURN NEW;
  END IF;

  -- ── de acá para abajo, SOLO códigos duales (437E, 438E, 439E, 809E) ──────────────

  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa
  -- de ESE picking (si es una sola). Si no, cae en 'Mixto' y no se netea.
  v_tanda := upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)));
  IF NOT v_explicita
     AND NEW.deposito IN ('separar_pedidos','a_facturar','terminado')
     AND v_tanda ~ '^[A-Z][0-9]{2}[A-Z]$' THEN
    SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
      INTO v_emp2
      FROM public."Movimientos_Stock" m
     WHERE m.tipo='picking' AND m.deposito='separar_pedidos'
       AND m.empresa IN ('LK','CH')
       AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
       AND upper(btrim(split_part(m.ref,'|',1))) = v_tanda;
    IF v_emp2 IS NOT NULL THEN
      NEW.empresa := v_emp2;
      RETURN NEW;
    END IF;
  END IF;

  -- v18.86: un `guardado` SIN empresa hereda la del montón que está en A Guardar.
  IF NOT v_explicita
     AND NEW.tipo LIKE 'guardado%'
     AND NEW.deposito IN ('a_guardar','terminado','excedente') THEN
    SELECT CASE WHEN count(*) = 1 THEN max(q.emp) END INTO v_emp2 FROM (
      SELECT COALESCE(NULLIF(m.empresa,''),'Mixto') AS emp
        FROM public."Movimientos_Stock" m
       WHERE m.deposito = 'a_guardar' AND m.delta > 0
         AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
       GROUP BY 1
    ) q;
    IF v_emp2 IN ('LK','CH') THEN
      NEW.empresa := v_emp2;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.empresa IS NULL OR NEW.empresa = 'Mixto' THEN
    -- (b) v19.26 — la NP puede venir de CUALQUIERA de los dos lados de la barra
    v_np := nullif(regexp_replace(split_part(coalesce(NEW.ref,''),'|',2),'\D','','g'),'');
    IF v_np IS NULL OR length(v_np) NOT BETWEEN 4 AND 6 THEN
      v_np := nullif(regexp_replace(split_part(coalesce(NEW.ref,''),'|',1),'\D','','g'),'');
      IF v_np IS NOT NULL AND (length(v_np) NOT BETWEEN 4 AND 6
                               OR split_part(upper(btrim(coalesce(NEW.ref,''))),'|',1) ~ '[A-Z]')
      THEN v_np := NULL; END IF;
    END IF;
    IF v_np IS NOT NULL THEN NEW.empresa := public.empresa_de_np(v_np); END IF;

    IF (NEW.empresa IS NULL OR NEW.empresa = '' OR NEW.empresa = 'Mixto')
       AND NEW.deposito = 'a_facturar' AND NEW.tipo = 'facturado' THEN
      SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
        INTO v_emp2
        FROM public."Movimientos_Stock" m
       WHERE m.deposito='a_facturar' AND m.tipo='separado'
         AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
         AND upper(btrim(split_part(m.ref,'|',1))) = upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)))
         AND m.empresa IN ('LK','CH');
      IF v_emp2 IS NOT NULL THEN NEW.empresa := v_emp2; END IF;
    END IF;
    IF NEW.empresa IS NULL OR NEW.empresa = '' THEN NEW.empresa := 'Mixto'; END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ════════════════════════════════════════════════════════════════════════════════════
-- CHEQUEOS (los 14 casos que se corrieron antes de aplicar, todos dentro de una
-- transacción que se revierte). Resultado: 14/14.
--   505   sin empresa            -> LK      (no dual: manda el artículo)
--   505   con CH                 -> LK      (pedido de Chef, artículo de Loeke)
--   097   sin empresa            -> CH
--   505L  sin empresa            -> LK      (pela la L)
--   029   sin empresa            -> Mixto   (huérfano: NO inventa)
--   029   con LK                 -> LK      (huérfano: respeta lo que vino)
--   438E  ref 44619|CP           -> CH      (dual: NP adelante de la barra)
--   438E  ref W99G|98329         -> LK      (dual: NP atrás)
--   809E  ref W33Z               -> Mixto   (W33Z NO es la NP 33)
--   809E  ref W06Z|FIX_20260811  -> Mixto   (20260811 NO es una NP)
--   809E  con CH                 -> CH      (dual: respeta lo explícito)
--   438E LK                      -> LK      (dual: sufijo en el código)
--   066   sin empresa            -> LK
--   insumo                       -> sale temprano, sin tocar empresa
--
-- Y después de aplicar:
--   select public.reconciliar_pipeline_stock();   -- 0 filas nuevas = no duplicó
--   select count(*) from public.gv_stock_empresa_fantasma;  -- bajó de 61 a 5
--   select count(*) from public.vista_saldos_stock where terminado<0 or racks<0 ...;  -- 2
-- ════════════════════════════════════════════════════════════════════════════════════

-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────
-- 1) La definición anterior del trigger está en
--    zz_backups."GV_Backup_Fn_NormalizarEmpresa_20260916" (columna def).
-- 2) Las filas: zz_backups."GV_Backup_MovStock_empresa_backfill_20260916" (54.914, el
--    backfill del 16/09) y zz_backups."GV_Backup_MovStock_empresa_alineadas_20260916"
--    (466, las que tenían la etiqueta del criterio viejo). Las dos tienen empresa_antes.
--    update public."Movimientos_Stock" m set empresa = b.empresa_antes
--      from zz_backups."GV_Backup_..." b where b.id = m.id;
--    ⚠ Apagar antes `trigger_actualizar_saldo_stock`: corre FOR EACH ROW y reescanea la
--      tabla entera por fila.
-- 3) select cron.unschedule('gv-refrescar-articulo-empresa');
-- 4) drop table public."GV_Articulo_Empresa_Cache";
--    drop function public.gv_empresa_de_articulo(text), public.gv_empresa_de_articulo_vivo(text),
--                  public.gv_refrescar_articulo_empresa();

-- ════════════════════════════════════════════════════════════════════════════════════
-- v19.27 (Luis, 2026-09-17) — LA FUENTE DE RACKS ERA LA TABLA VIEJA
-- ════════════════════════════════════════════════════════════════════════════════════
-- El tercer fallback (racks) leia `Ubicaciones_Articulos`, que **quedo congelada el
-- 2026-08-10**: 872 filas, nadie la escribe desde entonces. La viva es
-- `Racks_Planimetria` (154 filas, ultima carga 16/09), que es la que mueven
-- racks_plani_ingreso / _descontar / _mover, registrar_baja_racks y vista_insumos.
--
-- Como se noto: buscando donde estaban fisicamente las cajas del 809E, la tabla vieja
-- decia que en el rack AD5 habia un codigo `809E-QUESO` y en Y12 un `809E-PIZZA`. Los dos
-- son inventos de esa tabla: 0 movimientos en Movimientos_Stock, 0 en el deposito insumos,
-- y son los unicos dos codigos con guion que tiene. La viva dice `809E` y el rack de LK es
-- AE11, no Y12.
--
-- Impacto del cambio de fuente, medido: 7 codigos resuelven distinto (2 son los inventados,
-- 2 son duales donde la funcion devuelve NULL igual) y **0 movimientos** quedan con una
-- etiqueta que no coincida con el catalogo. El cache paso de 374 a 371 codigos.
--
-- Ademas se corrigieron 26 sectores de `Racks_Planimetria` a los que les faltaba el cero
-- (AD5 -> AD05, X1 -> X01, N3 -> N03 ...): 27 de los 29 que no existian en GV_Lugar eran
-- ese mismo error de tipeo. Backup: zz_backups."GV_Backup_RacksPlani_sectores_20260917".
-- Quedan 3 sin corregir a proposito: O2 y O5 (no existen en ninguna forma) y Z7 (su gemelo
-- Z07 existe pero es GONDOLA, no rack).
--
-- Rollback de los sectores:
--   update public."Racks_Planimetria" r set sector = b.sector
--     from zz_backups."GV_Backup_RacksPlani_sectores_20260917" b where b.id = r.id;
-- ════════════════════════════════════════════════════════════════════════════════════
