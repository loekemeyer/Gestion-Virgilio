-- ════════════════════════════════════════════════════════════════════
-- LA EMPRESA VIAJA DESDE LA RECEPCIÓN HASTA LA GÓNDOLA  (2026-09-11)
-- Pedido de Luis: "cuando el operario recibe y marca si es LK o CH, esa info
-- debería seguir a todos los códigos que ingresan".
--
-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  ⛔ NO APLICAR TODAVÍA — DECISIÓN DE LUIS, 2026-09-11             ║
-- ║                                                                  ║
-- ║  Este SQL se corre EN EL MISMO MOMENTO en que la rama            ║
-- ║  `claude/trusting-cerf-1w5v54` se mergea a `main`, NO ANTES.      ║
-- ║                                                                  ║
-- ║  Por qué: la base Supabase es la MISMA que usa la app en vivo.    ║
-- ║  Aplicar esto NO espera a ningún push — cambia el comportamiento  ║
-- ║  de la recepción en el instante en que se corre, con los          ║
-- ║  operarios pickeando. El front que lo acompaña viaja en la rama.  ║
-- ║                                                                  ║
-- ║  Orden al mergear:                                               ║
-- ║    1. traer `main` a la rama y correr la suite                   ║
-- ║    2. mergear la rama a `main` (el front sale por Pages)          ║
-- ║    3. recién ahí correr ESTE archivo en hrxfctzncixxqmpfhskv      ║
-- ║    4. verificar:                                                 ║
-- ║       select empresa, count(*) from "Movimientos_Stock"           ║
-- ║        where deposito='a_guardar' group by 1;                     ║
-- ║       select * from gv_saldos_stock_emp limit 5;                  ║
-- ║                                                                  ║
-- ║  Rollback: docs/ROLLBACK-PRODUCCION.md, entrada v15.71.           ║
-- ╚══════════════════════════════════════════════════════════════════╝
--
-- ── El problema ──────────────────────────────────────────────────────
-- El operario elige la línea (LK/CH) en la recepción y el front la manda en
-- `empresa` (recepcion.js:1898). Pero el trigger trg_normalizar_empresa_stock
-- la PISA: si el código no está en `codigos_duales` (4 filas), hace
-- `NEW.empresa := 'Mixto'` sin mirar lo que vino.
-- Medido el 11/09: de 651 recepciones, 645 quedaron en Mixto, 6 en LK y 0 en
-- CH. De las 2.572 cajas que hoy esperan en A Guardar, el sistema no sabe de
-- qué empresa es ninguna.
--
-- ── Los tres eslabones (los tres o ninguno) ──────────────────────────
--  1. RECEPCIÓN  → el trigger deja de pisar la empresa explícita (este archivo)
--  2. MG LEER    → stockFetchSaldos agrupa por código y funde los saldos de
--                  las dos empresas en un renglón (index.html)
--  3. MG ESCRIBIR→ mgConfirmar() no manda `empresa` (index.html)
-- Tocar sólo (1) deja el artículo LK en A Guardar y Mixto en góndola: el saldo
-- del mismo código queda partido por depósito y no concilia.
--
-- ⚠ Movimientos_Stock es TABLA COMPARTIDA. Al aplicar esto, anotarlo en
--   docs/ROLLBACK-PRODUCCION.md con el impacto medido.
-- ════════════════════════════════════════════════════════════════════

-- ── 1) Trigger: respetar la empresa que manda el front ───────────────
-- ÚNICO cambio respecto de la versión vigente: donde antes decía
--   IF NOT COALESCE(v_dual,false) THEN NEW.empresa := 'Mixto';
-- ahora sólo cae a 'Mixto' si NO vino una empresa explícita. Todo el resto
-- (pelado de sufijos, la L de Chef, derivar del NP, el drain de facturado)
-- queda igual.
create or replace function public.trg_normalizar_empresa_stock()
returns trigger language plpgsql as $fn$
DECLARE v_base text; v_dual boolean; v_np text; v_emp2 text; v_explicita boolean;
BEGIN
  IF NEW.deposito = 'insumos' THEN
    NEW.cod_art := regexp_replace(NEW.cod_art,'\s+(LK|CH|LOKE)$','');
    RETURN NEW;
  END IF;

  -- ¿el que inserta mandó una empresa REAL? ('Mixto' es el default de la
  -- columna, así que no cuenta como elección del operario)
  v_explicita := NEW.empresa IS NOT NULL AND NEW.empresa IN ('LK','CH');

  IF NEW.cod_art ~ '\s+(LK|LOKE)$' THEN NEW.empresa:='LK'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+(LK|LOKE)$','');
  ELSIF NEW.cod_art ~ '\s+CH$' THEN NEW.empresa:='CH'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+CH$',''); END IF;
  IF NEW.cod_art ~ '[0-9E]L$' THEN
    -- código terminado en L: pedido de CHEF que se pickea de la góndola de
    -- LOEKEMEYER. No es otro producto: dice de qué góndola se levanta.
    NEW.empresa := 'LK';
    NEW.cod_art := regexp_replace(NEW.cod_art,'([0-9E])L$','\1');
    v_explicita := true;
  END IF;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)),'^0+(?=.)','');
  SELECT true INTO v_dual FROM public.codigos_duales WHERE regexp_replace(upper(btrim(cod)),'^0+(?=.)','')=v_base LIMIT 1;

  IF NOT COALESCE(v_dual,false) THEN
    -- ⬇ EL CAMBIO: antes esto era `NEW.empresa := 'Mixto'` sin condición.
    IF NOT v_explicita THEN NEW.empresa := 'Mixto'; END IF;
  ELSE
    IF NEW.empresa IS NULL OR NEW.empresa = 'Mixto' THEN
      v_np := nullif(regexp_replace(split_part(coalesce(NEW.ref,''),'|',2),'\D','','g'),'');
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
  END IF;
  RETURN NEW;
END;
$fn$;

-- ── 2) Vista de saldos ABIERTA POR EMPRESA ───────────────────────────
-- `vista_saldos_stock` devuelve una fila por CÓDIGO (487 filas / 487 códigos)
-- y separa los duales inventando códigos sufijados ("437E LK"). Esta vista
-- nueva usa el código PELADO + la empresa en su propia columna, que es el
-- modelo al que vamos. Objeto nuevo: no toca la vieja ni a sus lectores.
create or replace view public.gv_saldos_stock_emp
with (security_invoker = true) as
with cfg as (select (select valor from public."Stock_Config" where clave='cutoff_ts' limit 1) cutoff)
select regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') cod,
       coalesce(nullif(m.empresa,''),'Mixto') empresa,
       max(m.descripcion) descripcion,
       sum(m.delta) filter (where m.deposito='terminado')       terminado,
       sum(m.delta) filter (where m.deposito='a_guardar')       a_guardar,
       sum(m.delta) filter (where m.deposito='excedente')       excedente,
       sum(m.delta) filter (where m.deposito='separar_pedidos') separar_pedidos,
       sum(m.delta) filter (where m.deposito='a_facturar')      a_facturar,
       sum(m.delta) filter (where m.deposito='racks')           racks,
       sum(m.delta) filter (where m.deposito='racks_ch')        racks_ch,
       sum(m.delta) filter (where m.deposito='para_envasar')    para_envasar,
       sum(m.delta) filter (where m.deposito='insumos')         insumos
from public."Movimientos_Stock" m, cfg
-- ⚠ la excepción de `inicial` NO es opcional: es la misma que tiene
-- `vista_saldos_stock`. Los conteos de apertura son el saldo de arranque y si el
-- cutoff los dejara afuera esta vista daría menos que la otra. Hoy no cambia nada
-- (0 filas `inicial` anteriores al cutoff, medido el 11/09), pero basta con que
-- alguien retrodate un conteo para que las dos vistas empiecen a discrepar.
where cfg.cutoff is null or m.tipo = 'inicial'
   or m.ts >= (replace(cfg.cutoff,' ','T'))::timestamptz
group by 1,2;

comment on view public.gv_saldos_stock_emp is
  'Saldos por (código PELADO, empresa). Reemplaza el artificio de vista_saldos_stock, que separa los duales inventando códigos sufijados ("437E LK"). Respeta el cutoff de Stock_Config. v1 2026-09-11, todavía sin lectores.';

-- ── 3) Backfill de lo que ya está en A Guardar ───────────────────────
-- Las 2.572 cajas que hoy esperan se pueden reasignar cruzando el remito
-- (Movimientos_Stock.ref) contra Control_Modo_OP, que guarda remito + linea.
-- MEDIDO el 11/09: resuelven 210 de 216 movimientos = 22.381 de 24.103 cajas
-- (93%). Los 6 que no resuelven quedan en Mixto.
--
-- ⚠ NO EJECUTAR sin decisión explícita: reescribe empresa en filas históricas
--   de una tabla compartida. Backup obligatorio antes.
--
-- update public."Movimientos_Stock" m
-- set empresa = c.linea
-- from public."Control_Modo_OP" c
-- where btrim(c.remito) = btrim(m.ref)
--   and m.deposito = 'a_guardar' and m.tipo = 'recepcion'
--   and m.empresa = 'Mixto' and c.linea in ('LK','CH')
--   and exists (select 1 from public.codigos_duales d
--               where regexp_replace(upper(btrim(d.cod)),'^0+(?=.)','')
--                   = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)',''));

-- ════════════════════════════════════════════════════════════════════
-- BACKFILL de A Guardar — VERSIÓN POR CATÁLOGO (mejor que la de por remito)
-- 2026-09-11. Idea de Luis: "si no hay ninguno dual, se les asigna el
-- correspondiente que ya tenemos".
--
-- Es correcto y cubre mucho más que cruzar por remito: para un código que NO
-- es dual, la empresa NO depende de quién lo trajo — el código pertenece a
-- una sola empresa, punto. Así que se deriva del catálogo, sin necesidad de
-- que exista el remito.
--
-- Se cruza contra DOS fuentes independientes y sólo se usa un código si la
-- fuente es inequívoca (una sola empresa):
--   1. GV_Lugar   — la empresa del LUGAR donde va el artículo
--   2. OC_Maximos — la línea del artículo
-- Cuando las dos opinan, coinciden; se prioriza el lugar.
--
-- MEDIDO el 11/09 sobre las 1.389 filas de a_guardar en 'Mixto':
--   1.385 se pueden derivar  (1.102 a LK · 283 a CH)
--       4 no                 (códigos 582 y 583, sin ficha en ningún lado)
--       0 duales             (ningún dual quedó en Mixto en a_guardar)
-- Los 4 que no resuelven tienen saldo 0: no afectan las 2.572 cajas vivas.
--
-- Esto incluye las 1.722 cajas del 29/06 que NO tenían remito real (su `ref`
-- dice "carga manual a guardar 29/06"): son 505, 513, 504, 321, 594 y 312,
-- ninguno dual, y los seis dan LK por las dos fuentes.
--
-- ⚠ NO EJECUTAR sin decisión explícita: reescribe `empresa` en filas
--   históricas de una tabla COMPARTIDA. Backup obligatorio antes, y anotarlo
--   en docs/ROLLBACK-PRODUCCION.md.
--
-- BACKUP:
--   create table public."GV_Backup_aguardar_empresa_20260911" as
--   select id, cod_art, empresa, deposito, delta, ts, ref
--     from public."Movimientos_Stock" where deposito='a_guardar' and empresa='Mixto';
-- ROLLBACK:
--   update public."Movimientos_Stock" m set empresa='Mixto'
--   from public."GV_Backup_aguardar_empresa_20260911" b where b.id = m.id;
--
-- with emp_cod as (   -- empresa por LUGAR, sólo si es inequívoca
--   select public.norm_cod(i.cod) c, min(l.empresa) e
--   from public."GV_Lugar_Item" i join public."GV_Lugar" l on l.sector = i.sector
--   where l.empresa in ('LK','CH')
--   group by 1 having count(distinct l.empresa) = 1
-- ), oc_cod as (      -- empresa por OC_Maximos, sólo si es inequívoca
--   select public.norm_cod(cod) c, min(btrim(linea)) e from public."OC_Maximos"
--   where btrim(linea) in ('LK','CH') group by 1 having count(distinct btrim(linea)) = 1
-- )
-- update public."Movimientos_Stock" m
-- set empresa = coalesce(e.e, o.e)
-- from (select 1) _
-- left join emp_cod e on true left join oc_cod o on true
-- where m.deposito = 'a_guardar' and m.empresa = 'Mixto'
--   and e.c = public.norm_cod(m.cod_art) and o.c = public.norm_cod(m.cod_art)
--   and coalesce(e.e, o.e) in ('LK','CH')
--   and not exists (select 1 from public.codigos_duales d
--                   where public.norm_cod(d.cod) = public.norm_cod(m.cod_art));
--
-- (la forma correcta del UPDATE, con los LEFT JOIN bien atados, se arma al
--  momento de ejecutarlo; lo de arriba documenta el CRITERIO, no la sintaxis final)
