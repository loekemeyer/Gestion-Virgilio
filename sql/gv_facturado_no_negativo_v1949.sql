-- ============================================================================
-- v19.49 — EL DOBLE DRENAJE DE a_facturar (caso D66D) Y EL GUARD QUE LO FRENA
-- Gestión Virgilio · proyecto hrxfctzncixxqmpfhskv · 2026-09-17
-- Pedido de Luis: "borrá las 12 … asegurándote de que para adelante no haya error"
-- ============================================================================
--
-- QUÉ PASÓ
-- --------
-- La tanda D66D se separó el 10/09: +159 cajas a `a_facturar`. Se drenó en cuatro
-- pasos, y los cuatro suman exactamente 159:
--
--   ref                filas  suma   cuándo
--   D66D|98633           18    -74   10/09 16:07
--   D66D|98634            3     -5   10/09 16:08
--   D66D|98668            2    -60   10/09 16:11
--   D66D  (barrido)      12    -20   10/09 16:11   ← este ES el drenaje de la NP 98648
--   ---------------------------------------------
--                              -159  → pila en 0
--
-- El 17/09 a las 14:05 entró un quinto drenaje, `D66D|98648`, con las MISMAS 12
-- filas y los MISMOS deltas que el barrido (12 de 12 idénticas, verificado código
-- por código). La pila quedó en **-20**.
--
-- POR QUÉ NO LO FRENÓ NADA
-- ------------------------
-- 1. El índice único `mov_stock_pipeline_dedup` lleva el `ref` en la clave, y
--    `D66D` y `D66D|98648` son dos refs distintos. Para el ON CONFLICT no son la
--    misma fila.
-- 2. Los dos reconciliadores de backend SÍ tienen el guard por tanda
--    (`reconciliar_pipeline_stock` etapa 3 y `gv_reconciliar_facturado_web`:
--    `not exists (… upper(trim(m.ref))=s.tanda or split_part(m.ref,'|',1)=s.tanda)`),
--    así que ninguno de los dos escribió esto — además escriben con
--    `legajo='pipeline'` y estas filas vinieron con `legajo=''` y `ubicacion='98648'`,
--    o sea del FRONT (`stockSalidaFacturadoNP`, index.html).
-- 3. El front tiene su propio tope (`_stockAfacturarRestanteTanda`, v5.96, que
--    justamente suma `ref = tanda` + `ref = tanda|NP`), y con ese tope el drenaje
--    habría dado 0. O sea que la copia que corrió NO era la del repo: un celular con
--    el `index.html` viejo cacheado alcanza para reponer el bug.
--
-- ⚠ Ésa es la lección: un guard que vive SOLO en el front no protege nada, porque
--   no se controla qué versión está corriendo cada operario. Va en el backend.
--
-- QUÉ ALCANCE TUVO
-- ----------------
-- Sólo D66D. El barrido a destiempo (una NP drena DESPUÉS del barrido de su tanda)
-- pasó además en E12C (17/09), D14B (03/08) y 97923 (31/07), pero esas tandas cierran
-- en 0: ahí el drenaje por NP era legítimo. Por eso el guard NO se escribió contra el
-- ORDEN de los drenajes sino contra el SALDO, que es el invariante de verdad.
--
-- Y por eso tampoco alcanzaba `gv_stock_negativos`: agrega por código SIN mirar la
-- tanda, así que el saldo positivo de otra tanda tapa el agujero. De los 12 códigos
-- que D66D dejó en negativo, esa vista mostraba 3.
--
-- ============================================================================
-- 1. BACKUP Y BORRADO DE LAS 12 FILAS DUPLICADAS
-- ============================================================================

create table zz_backups."GV_Backup_D66D_doble_drenaje_20260917" as
  select * from public."Movimientos_Stock" where id between 69971466 and 69971477;
alter table zz_backups."GV_Backup_D66D_doble_drenaje_20260917" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_D66D_doble_drenaje_20260917"
  from anon, authenticated;

delete from public."Movimientos_Stock"
 where id between 69971466 and 69971477
   and deposito='a_facturar' and tipo='facturado' and upper(btrim(ref))='D66D|98648';
-- 12 filas. Después: select public.refresh_stocks_carga_rapida(); select public.refresh_stock_view();
-- ⚠ `trigger_actualizar_saldo_stock` es AFTER INSERT OR UPDATE, NO corre con DELETE:
--    sin los dos refresh, stocks_carga_rapida queda con el saldo viejo.

-- Verificación: la pila de D66D cierra en 0.
--   select coalesce(sum(delta),0) from public."Movimientos_Stock"
--    where deposito='a_facturar' and upper(split_part(btrim(ref),'|',1))='D66D';   -- 0
-- gv_stock_negativos pasó de 3 filas a 1 (522E -1, que es de otro caso: el cierre a
-- mano de la NP 97870, anterior a esto).

-- ============================================================================
-- 2. EL LOG DE LO QUE EL GUARD FRENA
-- ============================================================================

create table if not exists public."GV_Stock_Drenaje_Bloqueado" (
  id          bigserial primary key,
  ts          timestamptz not null default now(),
  cod_art     text,
  ref         text,
  tanda       text,
  deposito    text,
  tipo        text,
  delta       numeric,
  empresa     text,
  saldo_tanda numeric,
  motivo      text
);
alter table public."GV_Stock_Drenaje_Bloqueado" enable row level security;
revoke insert, update, delete, truncate on public."GV_Stock_Drenaje_Bloqueado" from anon, authenticated;

comment on table public."GV_Stock_Drenaje_Bloqueado" is
 'v19.49 - Cada fila es un drenaje de a_facturar que el guard zzz_facturado_no_negativo frenó porque la pila de esa tanda ya estaba en cero. Si tiene filas, alguien (front viejo cacheado, reconciliador, carga a mano) está intentando facturar dos veces la misma tanda. Origen: doble drenaje de D66D (17/09).';

-- ============================================================================
-- 3. EL GUARD
-- ============================================================================
-- Descarta la fila (RETURN NULL) en vez de tirar una excepción a propósito: el
-- drenaje lo manda un proceso automático en lotes, y un `raise` mataría el batch
-- entero — incluidas las filas legítimas de los otros códigos. Y el operario no
-- tiene nada que hacer con el aviso. Queda anotado en el log, que es donde se mira.

create or replace function public.trg_facturado_no_negativo()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare v_tanda text; v_base text; v_saldo numeric;
begin
  -- Solo el drenaje de a_facturar. Todo lo demas pasa derecho.
  if NEW.tipo <> 'facturado' or NEW.deposito <> 'a_facturar' or coalesce(NEW.delta,0) >= 0 then
    return NEW;
  end if;

  v_tanda := upper(btrim(split_part(btrim(coalesce(NEW.ref,'')),'|',1)));

  -- SOLO cuando el ref empieza con un CODIGO DE TANDA (E12C, D66D). Ahi la pila esta
  -- garantizado bajo el mismo prefijo: el 'separado' entra con ref = tanda y los
  -- drenajes salen con ref = tanda o tanda|NP.
  -- NO se mide cuando el prefijo es una NP ('98507', 'LK 0034'): el drenaje de CP
  -- sale con ref = NP|CP contra una pila que se lleva por tanda, asi que medirla por
  -- prefijo daria un bloqueo falso. Tampoco los refs de texto libre de las
  -- correcciones a mano, que netean contra OTRO ref.
  if v_tanda !~ '^[A-Z][0-9]{2}[A-Z]$' then
    return NEW;
  end if;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)), '^0+(?=.)', '');

  -- La pila de la tanda, SIN mirar empresa: el doble drenaje de D66D (17/09) y el
  -- picking duplicado de D72A (problema 390) pasaron justamente porque una etiqueta
  -- de empresa distinta hacia que el mismo movimiento pareciera otro.
  select coalesce(sum(m.delta),0) into v_saldo
    from public."Movimientos_Stock" m
   where m.deposito = 'a_facturar'
     and regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '') = v_base
     and upper(btrim(split_part(btrim(coalesce(m.ref,'')),'|',1))) = v_tanda;

  if v_saldo <= 0 then
    insert into public."GV_Stock_Drenaje_Bloqueado"
      (cod_art, ref, tanda, deposito, tipo, delta, empresa, saldo_tanda, motivo)
    values (NEW.cod_art, NEW.ref, v_tanda, NEW.deposito, NEW.tipo, NEW.delta, NEW.empresa, v_saldo,
            'la pila de esa tanda ya estaba en '||v_saldo::text||': drenar de nuevo dejaba a_facturar en negativo');
    return null;   -- fila descartada, sin error: el operario no tiene nada que hacer con esto
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists zzz_facturado_no_negativo on public."Movimientos_Stock";
create trigger zzz_facturado_no_negativo
  before insert on public."Movimientos_Stock"
  for each row execute function public.trg_facturado_no_negativo();

-- Va al lado de `zzz_guardado_no_negativo`, que es el mismo patrón para `a_guardar`.
-- No pisa a `zz_normalizar_empresa`: el saldo se mide SIN empresa, así que el orden
-- entre los dos triggers no cambia el resultado.

-- ============================================================================
-- 4. EL CENTINELA
-- ============================================================================

drop view if exists public.gv_stock_afacturar_tanda_negativa;
create view public.gv_stock_afacturar_tanda_negativa as
with m as (
  select upper(btrim(split_part(btrim(coalesce(ref,'')),'|',1))) clave,
         regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') cod,
         delta, ts
    from public."Movimientos_Stock"
   where deposito = 'a_facturar'
)
select clave,
       case when clave ~ '^[A-Z][0-9]{2}[A-Z]$' then 'tanda' else 'np' end clase,
       cod,
       round(sum(delta),2) saldo,
       count(*) movimientos,
       max(ts) ultimo_mov,
       case when clave ~ '^[A-Z][0-9]{2}[A-Z]$'
            then 'La pila de esa tanda se drenó dos veces (facturado duplicado). Lo frena el guard zzz_facturado_no_negativo.'
            else 'Drenaje por NP (tipico CP, ref = NP|CP) sin la fila de entrada bajo esa misma NP. El guard NO lo toca: la pila se lleva por tanda. Revisar a mano.'
       end que_significa
  from m
 where clave ~ '^([A-Z][0-9]{2}[A-Z]|[0-9]{4,6}|(LK|CH) ?[0-9]{4})$'
 group by 1,3
having round(sum(delta),2) < 0
 order by 2, 4;

alter view public.gv_stock_afacturar_tanda_negativa set (security_invoker = true);

comment on view public.gv_stock_afacturar_tanda_negativa is
 'v19.49 - CENTINELA. clase=tanda vacia = todo bien (lo sostiene el guard zzz_facturado_no_negativo). gv_stock_negativos NO ve esto: agrega por codigo sin mirar la tanda, asi que el saldo positivo de otra tanda lo tapa — el 17/09 mostraba 3 de los 12 codigos que el doble drenaje de D66D habia dejado en negativo. clase=np son drenajes de CP sin entrada bajo la misma NP: OTRO problema, todavia sin resolver.';

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('trg_facturado_no_negativo','funcion','GV_Stock_Drenaje_Bloqueado',
        'Un facturado sobre a_facturar cuya pila de tanda ya esta en cero se DESCARTA (return null) y se anota en GV_Stock_Drenaje_Bloqueado. Sin esto vuelve el doble drenaje que dejo D66D en -20 el 17/09.',
        'Luis','v19.49')
on conflict do nothing;

-- ============================================================================
-- 5. CÓMO SE PROBÓ (con INSERT de verdad, no leyendo la función)
-- ============================================================================
--
--   -- (a) el drenaje que causó el problema: tiene que FRENARSE
--   insert into public."Movimientos_Stock"(cod_art,deposito,delta,tipo,ref,legajo,empresa)
--   values ('315','a_facturar',-1,'facturado','D66D|98648','__prueba__','LK');
--     → 0 filas en Movimientos_Stock, 1 en GV_Stock_Drenaje_Bloqueado ✔
--
--   -- (b) un drenaje legítimo (pila E03F/510 = 23): tiene que PASAR
--   insert into … values ('510','a_facturar',-2,'facturado','E03F|__PRUEBA__','__prueba__','LK');
--     → 1 fila ✔
--
--   -- (c) un drenaje de CP (ref = NP|CP): tiene que PASAR
--   insert into … values ('522E','a_facturar',-1,'facturado','98507|CP','__prueba__','LK');
--     → 1 fila ✔
--
--   -- (d) una corrección a mano con ref de texto libre: tiene que PASAR
--   insert into … values ('315','a_facturar',-1,'facturado','CIERRE A MANO … TANDA D66D','__prueba__','LK');
--     → 1 fila ✔
--
--   delete from public."Movimientos_Stock" where legajo='__prueba__';
--   delete from public."GV_Stock_Drenaje_Bloqueado" where ref='D66D|98648';
--   select public.refresh_stocks_carga_rapida();
--
-- ⚠ La (c) y la (d) son la razón por la que el guard NO se aplica a cualquier ref:
--   la primera versión miraba también las NP y habría frenado los drenajes de CP.
--   Lo destapó el centinela, no la lectura del código.
--
-- ============================================================================
-- 6. LO QUE QUEDA ABIERTO
-- ============================================================================
--
-- `select * from public.gv_stock_afacturar_tanda_negativa where clase='np';`
-- devuelve 11 filas (-20 cajas) en dos claves: `LK 0034` (7 códigos, 15/09) y
-- `98507` (4 códigos, 17/09). Cada una tiene UN SOLO movimiento bajo esa clave, y es
-- negativo: son drenajes de CP sin la fila de entrada bajo la misma NP. NO es el
-- mismo problema que D66D y NO se tocó nada de eso.
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
--   drop trigger if exists zzz_facturado_no_negativo on public."Movimientos_Stock";
--   drop function if exists public.trg_facturado_no_negativo();
--   drop view if exists public.gv_stock_afacturar_tanda_negativa;
--   delete from public."GV_Reglas_Centinela" where objeto='trg_facturado_no_negativo';
--   insert into public."Movimientos_Stock" select * from zz_backups."GV_Backup_D66D_doble_drenaje_20260917";
--   select public.refresh_stocks_carga_rapida();
-- ============================================================================

-- ============================================================================
-- APÉNDICE — las 8 filas del 920 que quedaron 'Mixto' (mismo día, otro origen)
-- ============================================================================
-- `gv_stock_empresa_fantasma` cantó el código 920 en a_guardar con CH:+15 / Mixto:-15
-- (total 0, o sea etiqueta, no cajas). Las 8 filas son de entre las 13:58 y las 15:09
-- del 17/09 — la ventana en la que la regla del artículo NO estaba en el trigger
-- (problema 390, repuesta a las 16:04). `gv_empresa_de_articulo('920')` = CH y el
-- código está en góndola, así que hoy el trigger las etiquetaría bien: medido con un
-- insert de prueba, da CH.
--
-- create table zz_backups."GV_Backup_920_mixto_20260917" as
--   select * from public."Movimientos_Stock" m
--    where m.ts >= (now() - interval '2 days') and coalesce(m.empresa,'Mixto')='Mixto'
--      and m.deposito <> 'insumos' and public.gv_empresa_de_articulo(m.cod_art) is not null;
-- alter table zz_backups."GV_Backup_920_mixto_20260917" enable row level security;
-- revoke insert, update, delete, truncate on zz_backups."GV_Backup_920_mixto_20260917" from anon, authenticated;
--
-- update public."Movimientos_Stock" set empresa='CH'
--  where id in (select id from zz_backups."GV_Backup_920_mixto_20260917");   -- 8 filas
--
-- El UPDATE no dispara `zz_normalizar_empresa` (es BEFORE INSERT), así que no hay
-- recursión. Huella del saldo por (código, depósito) SIN empresa, antes y después:
-- 72816c64382f5d206a57384041ca0477 = 72816c64382f5d206a57384041ca0477 → no se movió
-- una sola caja. `gv_stock_empresa_fantasma` pasó de 1 a 0.
-- ============================================================================
