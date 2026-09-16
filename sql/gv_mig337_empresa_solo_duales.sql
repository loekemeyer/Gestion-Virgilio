-- v18.97 — MIGRACIÓN 337 EMPAQUETADA: seis funciones listas para disparar al cierre.
--
-- Pedido de Luis (2026-09-16): *"prepará todo lo que necesites aparte (sin joder live) para
-- que cuando te diga se implemente"*.
--
-- Esto **crea las funciones, no las ejecuta**. Crear una función `gv_*` no toca ningún dato
-- ni ninguna pantalla: queda dormida hasta que alguien la llame. El análisis completo de por
-- qué el cambio es seguro está en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.ih y en
-- `sql/gv_empresa_solo_duales_v1895.sql`.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ⚠ POR QUÉ SON TRES FASES Y NO UNA SOLA FUNCIÓN
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Tentación natural: una función que haga todo. **No sirve**, y por un motivo concreto:
-- `cron.alter_job` es transaccional — hace un `UPDATE` sobre `cron.job`. Si el apagado de los
-- crons va DENTRO de la misma transacción que la migración, el scheduler **sigue viendo
-- `active = true`** hasta el commit, o sea hasta que la migración ya terminó: los crons nunca
-- quedan apagados durante la ventana, que es justo para lo que se los apagaba.
--
-- Por eso: fase 1 apaga y commitea · fase 2 migra · fase 3 verifica y prende.
--
--   select * from public.gv_mig337_simular();          -- cuando quieras, no escribe NADA
--   select * from public.gv_mig337_migrar(true);       -- ENSAYO: corre TODO y lo revierte
--   select * from public.gv_mig337_preparar();    -- apaga los crons + preflight
--   select * from public.gv_mig337_migrar();      -- el cambio, todo o nada
--   select * from public.gv_mig337_verificar();   -- reconciliadores + repesca + prende crons
--   select * from public.gv_mig337_rollback();    -- si algo sale mal: deshace TODO
--
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ⚠ Las definiciones de abajo están verificadas contra la base con el md5 del cuerpo
-- normalizado (sin comentarios ni espacios). Si se editan, re-verificar:
--   select p.proname, md5(regexp_replace(regexp_replace(regexp_replace(
--            p.prosrc,'/\*.*?\*/','','gs'),'--[^\n]*','','g'),'\s','','g'))
--     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and p.proname like 'gv_mig337%' order by 1;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT — los 7 chequeos. No escribe nada. Lo usan `simular` y `preparar`.
-- ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_mig337_preflight()
returns table(chequeo text, estado text, detalle text)
language plpgsql
as $fn$
declare
  v_ult_min numeric; v_abiertas int; v_filas int; v_col int; v_col_ag int;
  v_ancla boolean; v_ya boolean; v_duales int;
begin
  select round(extract(epoch from (now() - max(r.ts_cliente)))/60)
    into v_ult_min
    from public."Registros_Produccion_Virgilio" r
   where not public.es_legajo_test(r.legajo);
  chequeo := 'deposito quieto';
  estado  := case when coalesce(v_ult_min, 999) >= 30 then 'OK' else 'FRENA' end;
  detalle := 'ultimo evento de operario hace ' || coalesce(v_ult_min::text,'(nunca)') || ' min (hace falta >= 30)';
  return next;

  select count(*) into v_abiertas from (
    select upper(btrim(split_part(r.texto,'|',1))) t, r.legajo
      from public."Registros_Produccion_Virgilio" r
     where r.ts_cliente >= now() - interval '24 hours'
       and not public.es_legajo_test(r.legajo)
     group by 1,2
    having max(r.ts_cliente) filter (where r.opcion in ('EP','AP')) is not null
       and (max(r.ts_cliente) filter (where r.opcion in ('TP','TAP')) is null
         or max(r.ts_cliente) filter (where r.opcion in ('TP','TAP'))
          < max(r.ts_cliente) filter (where r.opcion in ('EP','AP')))
  ) z;
  chequeo := 'sin picking/armado abierto';
  estado  := case when v_abiertas = 0 then 'OK' else 'FRENA' end;
  detalle := v_abiertas || ' tanda(s) con EP sin TP o AP sin TAP en las ultimas 24 h';
  return next;

  with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales)
  select count(*) into v_filas
    from public."Movimientos_Stock" m
    left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
   where du.cod is null and m.empresa in ('LK','CH')
     and m.id not in (63471807, 63467166, 63476448);
  chequeo := 'filas a corregir'; estado := 'INFO';
  detalle := v_filas || ' filas de codigos NO duales con empresa LK/CH (medido el 16/09: 5.794)';
  return next;

  with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales),
  nd as (
    select m.cod_art, m.ref, m.deposito, m.tipo
      from public."Movimientos_Stock" m
      left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
     where du.cod is null and m.tipo in ('picking','separado','facturado')
       and m.id not in (63471807, 63467166, 63476448))
  select count(*) into v_col from (
    select 1 from nd group by upper(btrim(ref)), upper(btrim(cod_art)), deposito, tipo
     having count(*) > 1) z;
  chequeo := 'colisiones pipeline_dedup';
  estado  := case when v_col = 0 then 'OK' else 'FRENA' end;
  detalle := v_col || ' grupo(s) que chocarian (las 3 conocidas de D72A/520 ya estan excluidas)';
  return next;

  with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales),
  nd as (
    select m.ref, m.cod_art, m.deposito from public."Movimientos_Stock" m
      left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
     where du.cod is null and m.tipo = 'aguardar')
  select count(*) into v_col_ag from (
    select 1 from nd group by upper(btrim(ref)), upper(btrim(cod_art)), deposito
     having count(*) > 1) z;
  chequeo := 'colisiones aguardar_dedup';
  estado  := case when v_col_ag = 0 then 'OK' else 'FRENA' end;
  detalle := v_col_ag || ' grupo(s) que chocarian';
  return next;

  select position('  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa' in p.prosrc) > 0,
         position('v18.95: un codigo NO DUAL' in p.prosrc) > 0
    into v_ancla, v_ya
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'trg_normalizar_empresa_stock';
  chequeo := 'ancla del trigger';
  estado  := case when v_ya then 'YA APLICADO' when v_ancla then 'OK' else 'FRENA' end;
  detalle := case when v_ya then 'el bloque v18.95 ya esta en la funcion: la migracion ya corrio'
                  when v_ancla then 'el bloque v18.24 esta donde se espera'
                  else 'NO se encuentra el ancla: otra sesion reescribio el trigger, revisar a mano' end;
  return next;

  select count(*) into v_duales from public.codigos_duales;
  chequeo := 'codigos duales';
  estado  := case when v_duales = 4 then 'OK' else 'MIRAR' end;
  detalle := v_duales || ' duales (se esperaban 4: 437E, 438E, 439E, 809E)';
  return next;
end $fn$;
revoke execute on function public.gv_mig337_preflight() from public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- SIMULAR — corré esto cuando quieras. No escribe absolutamente nada.
-- ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_mig337_simular()
returns table(chequeo text, estado text, detalle text)
language sql as $fn$ select * from public.gv_mig337_preflight(); $fn$;
revoke execute on function public.gv_mig337_simular() from public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- FASE 1 — PREPARAR: apaga los 5 crons que escriben. Se niega si el preflight está en rojo.
-- ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_mig337_preparar()
returns table(chequeo text, estado text, detalle text)
language plpgsql
as $fn$
declare j int; v_frena int;
begin
  select count(*) into v_frena from public.gv_mig337_preflight() p where p.estado = 'FRENA';
  if v_frena > 0 then
    raise exception 'Preflight en rojo (% chequeo/s). Corre  select * from public.gv_mig337_simular();  y mira cual.', v_frena;
  end if;
  foreach j in array array[34, 57, 68, 74, 81] loop
    perform cron.alter_job(j, active := false);
  end loop;
  return query
    select 'crons apagados'::text, 'OK'::text,
           ('34 detectar-faltantes · 57 refresh_stocks_carga_rapida · 68 reconciliar-pipeline · ' ||
            '74 gv-reconciliar-facturado-web · 81 gv-reconciliar-aguardar')::text
    union all select * from public.gv_mig337_preflight();
end $fn$;
revoke execute on function public.gv_mig337_preparar() from public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- FASE 2 — MIGRAR: backup + trigger + vista + backfill. TODO O NADA (una transacción).
--   `gv_mig337_migrar(true)`  = ENSAYO: corre exactamente lo mismo y al final lo revierte.
--   `gv_mig337_migrar()`      = de verdad.
-- Se niega si el bloque ya está aplicado, y aborta si el md5 del saldo cambia.
-- ───────────────────────────────────────────────────────────────────────────────────────
drop function if exists public.gv_mig337_migrar();
create or replace function public.gv_mig337_migrar(p_ensayo boolean default false)
returns table(paso text, detalle text)
language plpgsql
as $fn$
declare
  d text; d0 text; n int; tot int := 0; vueltas int := 0;
  md5_antes text; md5_desp text; v_backup int; v_ya boolean;
begin
  perform pg_advisory_xact_lock(5768);

  select position('v18.95: un codigo NO DUAL' in p.prosrc) > 0 into v_ya
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'trg_normalizar_empresa_stock';
  if v_ya then
    raise exception 'El trigger YA tiene el bloque v18.95: la migracion ya corrio. Para rehacerla, primero gv_mig337_rollback().';
  end if;

  select md5(string_agg(z.cod_art || '|' || z.deposito || '|' || z.s, ',' order by z.cod_art, z.deposito))
    into md5_antes
    from (select m.cod_art, m.deposito, sum(m.delta) s from public."Movimientos_Stock" m group by 1,2) z;
  paso := '0 · md5 del saldo ANTES'; detalle := md5_antes; return next;

  if to_regclass('zz_backups."GV_Backup_MovStock_empresa_nodual_20260916"') is null then
    create table zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" as
    with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales)
    select m.id, m.empresa
      from public."Movimientos_Stock" m
      left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
     where du.cod is null and m.empresa in ('LK','CH');
    execute 'alter table zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" enable row level security';
    execute 'revoke insert, update, delete, truncate on zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" from anon, authenticated';
  end if;
  execute 'select count(*) from zz_backups."GV_Backup_MovStock_empresa_nodual_20260916"' into v_backup;
  paso := '1 · backup'; detalle := v_backup || ' filas en zz_backups.GV_Backup_MovStock_empresa_nodual_20260916 (RLS ON)'; return next;

  select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure) into d;
  d0 := d;
  d := replace(d,
    '  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa',
    '  -- v18.95: un codigo NO DUAL tiene UNA SOLA PILA FISICA (una gondola, un rack), asi que'  || chr(10) ||
    '  -- la empresa del movimiento no describe nada. Marcarla igual partia el saldo, porque se' || chr(10) ||
    '  -- marcaba ASIMETRICO: las salidas con LK/CH y las entradas historicas en Mixto, asi que' || chr(10) ||
    '  -- el - no cancelaba al +. Al 16/09 eran 62 codigos / 1.709 cajas y crecia todos los dias.'|| chr(10) ||
    '  -- Va ANTES de los bloques v18.24 y v18.86: esos dos eligen entre las DOS gondolas de un' || chr(10) ||
    '  -- dual, y aca no hay dos. Los duales son solo 4: 437E, 438E, 439E, 809E. Problema 337.'   || chr(10) ||
    '  IF NOT COALESCE(v_dual,false) THEN'                                                        || chr(10) ||
    '    NEW.empresa := ''Mixto'';'                                                               || chr(10) ||
    '    RETURN NEW;'                                                                             || chr(10) ||
    '  END IF;'                                                                                   || chr(10) ||
    '  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa');
  if d = d0 then raise exception 'el ancla del bloque v18.24 no matcheo: la funcion cambio, revisar'; end if;
  execute d;
  paso := '2 · trigger'; detalle := 'trg_normalizar_empresa_stock: NO dual -> empresa = Mixto, siempre'; return next;

  drop view if exists public.gv_ocupacion_lugar;
  create view public.gv_ocupacion_lugar
  with (security_invoker = true) as
  with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales),
  saldo as (
    select upper(btrim(m.cod_art)) as cod, upper(btrim(coalesce(m.empresa,''))) as empresa,
           case when m.deposito in ('racks','racks_ch') then 'rack'
                when m.deposito = 'insumos' then 'insumo' else 'gondola' end as destino,
           sum(m.delta) as saldo
      from public."Movimientos_Stock" m group by 1,2,3),
  saldo_tot as (select cod, destino, sum(saldo) saldo from saldo group by 1,2)
  select l.sector, l.tipo, l.empresa, l.orden, li.cod, li.clase, li.cajas_max,
         sum(li.cajas_max) over (partition by li.cod, l.empresa) as cajas_max_total_cod,
         coalesce(sd.saldo, st.saldo) as saldo_cod,
         case when sum(li.cajas_max) over (partition by li.cod, l.empresa) > 0
              then round(100 * coalesce(sd.saldo, st.saldo) / sum(li.cajas_max) over (partition by li.cod, l.empresa), 1)
         end as pct_ocupado_cod
    from public."GV_Lugar" l
    join public."GV_Lugar_Item" li on li.sector = l.sector and li.activo
    left join du dd on dd.cod = regexp_replace(upper(btrim(li.cod)),'^0+(?=.)','')
    left join saldo sd on dd.cod is not null and sd.cod = upper(btrim(li.cod))
         and sd.empresa = l.empresa and sd.destino = case when li.clase='insumo' then 'insumo' else l.tipo end
    left join saldo_tot st on dd.cod is null and st.cod = upper(btrim(li.cod))
         and st.destino = case when li.clase='insumo' then 'insumo' else l.tipo end
   where l.activo;
  execute 'alter view public.gv_ocupacion_lugar set (security_invoker = true)';
  paso := '3 · gv_ocupacion_lugar'; detalle := 'empresa solo para duales (problema 340)'; return next;

  loop
    vueltas := vueltas + 1;
    with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales),
    objetivo as (
      select m.id from public."Movimientos_Stock" m
        left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
       where du.cod is null and m.empresa in ('LK','CH')
         and m.id not in (63471807, 63467166, 63476448)
       order by m.id limit 1000)
    update public."Movimientos_Stock" x set empresa = 'Mixto' from objetivo o where x.id = o.id;
    get diagnostics n = row_count;
    tot := tot + n;
    exit when n = 0 or vueltas > 50;
  end loop;
  paso := '4 · backfill'; detalle := tot || ' filas pasadas a Mixto, en ' || vueltas || ' lote(s)'; return next;

  select md5(string_agg(z.cod_art || '|' || z.deposito || '|' || z.s, ',' order by z.cod_art, z.deposito))
    into md5_desp
    from (select m.cod_art, m.deposito, sum(m.delta) s from public."Movimientos_Stock" m group by 1,2) z;
  if md5_desp is distinct from md5_antes then
    raise exception 'EL SALDO CAMBIO (% -> %). Se revierte todo.', md5_antes, md5_desp;
  end if;
  paso := '5 · md5 del saldo DESPUES'; detalle := md5_desp || '  <- identico al de antes, OK'; return next;

  if coalesce(p_ensayo, false) then
    raise exception 'ENSAYO OK — se revierte todo. backfill: % filas en % lote(s) · md5 antes=despues=% · backup % filas', tot, vueltas, md5_desp, v_backup;
  end if;
end $fn$;
revoke execute on function public.gv_mig337_migrar(boolean) from public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- FASE 3 — VERIFICAR: repesca lo que se haya colado, corre los reconciliadores (0 = no
-- duplicó), mira los centinelas, y prende los crons.
-- ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_mig337_verificar()
returns table(chequeo text, estado text, detalle text)
language plpgsql
as $fn$
declare j int; n int; v_rec int; v_ag int; v_part int; v_fant numeric; v_dual int;
begin
  with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales),
  objetivo as (
    select m.id from public."Movimientos_Stock" m
      left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
     where du.cod is null and m.empresa in ('LK','CH')
       and m.id not in (63471807, 63467166, 63476448))
  update public."Movimientos_Stock" x set empresa = 'Mixto' from objetivo o where x.id = o.id;
  get diagnostics n = row_count;
  chequeo := 'repesca'; estado := case when n = 0 then 'OK' else 'CORREGIDO' end;
  detalle := n || ' fila(s) que se colaron durante la ventana'; return next;

  select public.reconciliar_pipeline_stock_etapa1() into v_rec;
  chequeo := 'reconciliar_pipeline_stock_etapa1';
  estado  := case when coalesce(v_rec,0) = 0 then 'OK' else 'MIRAR' end;
  detalle := coalesce(v_rec,0) || ' filas insertadas (0 = el ON CONFLICT sigue matcheando, el picking NO se duplico)';
  return next;

  select public.gv_reconciliar_aguardar() into v_ag;
  chequeo := 'gv_reconciliar_aguardar';
  estado  := case when coalesce(v_ag,0) = 0 then 'OK' else 'MIRAR' end;
  detalle := coalesce(v_ag,0) || ' filas insertadas'; return next;

  select count(*) into v_part from public.gv_stock_particion_sospechosa;
  chequeo := 'gv_stock_particion_sospechosa'; estado := 'INFO';
  detalle := v_part || ' fila(s)'; return next;

  select count(*) filter (where f.es_dual), coalesce(sum(f.fantasma),0)
    into v_dual, v_fant from public.gv_stock_empresa_fantasma f;
  chequeo := 'gv_stock_empresa_fantasma';
  estado  := case when v_dual = 0 then 'OK' else 'MIRAR' end;
  detalle := v_dual || ' codigo(s) DUALES con fantasma (tiene que ser 0) · ' || v_fant || ' cajas en total';
  return next;

  foreach j in array array[34, 57, 68, 74, 81] loop
    perform cron.alter_job(j, active := true);
  end loop;
  chequeo := 'crons prendidos'; estado := 'OK'; detalle := '34, 57, 68, 74, 81'; return next;
end $fn$;
revoke execute on function public.gv_mig337_verificar() from public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- ROLLBACK — deshace TODO de un tirón. Datos y trigger van juntos: mitad y mitad duplica
-- el picking (probado, ver §3.ih de docs/SUPABASE-GESTION-VIRGILIO.md).
-- ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_mig337_rollback()
returns table(paso text, detalle text)
language plpgsql
as $fn$
declare d text; n int; j int;
begin
  perform pg_advisory_xact_lock(5768);
  if to_regclass('zz_backups."GV_Backup_MovStock_empresa_nodual_20260916"') is null then
    raise exception 'No existe el backup: no hay con que revertir los datos.';
  end if;
  select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure) into d;
  execute regexp_replace(d, '  -- v18\.95: un codigo NO DUAL.*?  END IF;' || chr(10), '');
  paso := '1 · trigger'; detalle := 'bloque v18.95 removido'; return next;

  execute 'update public."Movimientos_Stock" m set empresa = b.empresa
             from zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" b
            where b.id = m.id and m.empresa is distinct from b.empresa';
  get diagnostics n = row_count;
  paso := '2 · datos'; detalle := n || ' filas devueltas a su LK/CH original'; return next;

  foreach j in array array[34, 57, 68, 74, 81] loop
    perform cron.alter_job(j, active := true);
  end loop;
  paso := '3 · crons'; detalle := 'prendidos'; return next;

  paso := '4 · gv_ocupacion_lugar';
  detalle := 'NO se revierte automaticamente (la nueva es la correcta). Para volver: sql/backups/gv_ocupacion_lugar_pre_v1895.sql';
  return next;
end $fn$;
revoke execute on function public.gv_mig337_rollback() from public, anon, authenticated;
