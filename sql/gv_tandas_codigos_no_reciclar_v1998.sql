-- v19.98 (2026-09-18) — UN CÓDIGO DE TANDA NO SE RECICLA NUNCA MÁS
-- =============================================================================================
-- Decisión de Thomas (18/09), después de una semana entera de incidentes con la misma raíz.
--
-- EL DIAGNÓSTICO, EN UNA LÍNEA: el código de tanda ES la identidad. No hay un id estable abajo,
-- así que "mover una tanda" se implementa como "renombrar ese texto en N tablas", y cada tabla
-- que se olvida queda mintiendo. Eso solo sería un dato viejo. Lo que lo vuelve un dato
-- MENTIROSO es el reciclaje: el código liberado vuelve a la bolsa y otra tanda lo ADOPTA, con lo
-- que la fila olvidada pasa a hablar de la tanda equivocada.
--
-- Los cinco incidentes de la semana son el mismo bug cambiando de tabla olvidada:
--   eventos PKC (campo 1) ........ picking del inquilino anterior ........... 421 / v19.80
--   Movimientos_Stock + unique ... fusionar dos tandas armadas era imposible . 407 / v19.69
--   GV_Tandas_Lock ............... "ya la agarró Jhonny" .................... v19.96
--   localStorage del celular ..... el operario trabado con E12M ............. v19.92
--   restauración de ENT/TAL ...... la red de seguridad cosida al lado ....... v19.97
--
-- MEDIDO ANTES DE TOCAR: 1.087 códigos con huella histórica (eventos, Entregas, candado,
-- facturación, líos, anuladas). 440 ya estaban bloqueados; **647 se podían reciclar hoy**. De
-- esos 647, sólo TRES son de la serie viva: E03F, E03G y E11B — exactamente los que aparecieron
-- esta semana con candado ajeno y comprometido en negativo. Los otros 644 son series A/B/C/D
-- viejas, así que bloquearlos no le saca ningún código a nadie.
--
-- LO QUE NO SE TOCA: `gv_ppp_tanda_codigo_nuevo` sigue REUSANDO la base y el NN del camión del
-- día a propósito (E12A, E12B, E12C… es el mismo camión). El cambio sólo mueve la ÚLTIMA letra.
-- Y `ppp_web_proxima_letra` queda como está: sumarle el ledger la haría leer bases raras que hay
-- en la historia (BO, CO, TA) y correr la serie a cualquier lado.
--
-- Rollback: `drop` del `or exists` del ledger en `gv_ppp_web_codigo_tomado` (el resto es aditivo
-- y no molesta), `select cron.unschedule('gv-tandas-codigos-usados')`.
-- =============================================================================================

-- 1. LA MEMORIA QUE NO SE BORRA -------------------------------------------------------------
create table if not exists public."GV_Tandas_Codigos_Usados" (
  codigo      text primary key,
  primera_vez timestamptz not null default now(),
  fuente      text
);
alter table public."GV_Tandas_Codigos_Usados" enable row level security;
revoke insert, update, delete, truncate on public."GV_Tandas_Codigos_Usados" from anon, authenticated;
grant select on public."GV_Tandas_Codigos_Usados" to anon, authenticated;
drop policy if exists "GV_Tandas_Codigos_Usados_select" on public."GV_Tandas_Codigos_Usados";
create policy "GV_Tandas_Codigos_Usados_select" on public."GV_Tandas_Codigos_Usados"
  for select to anon, authenticated using (true);

-- 2. QUIÉN LA LLENA ---------------------------------------------------------------------------
-- Barre las 11 tablas donde un código de tanda deja rastro. Idempotente (`on conflict do
-- nothing`), 590 ms la corrida completa. El filtro `^[A-Z]+[0-9]+[A-Z]+$` deja afuera la basura.
create or replace function public.gv_tandas_codigos_usados_sync(p_desde interval default null)
 returns integer language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare v_n int; v_d timestamptz := case when p_desde is null then '-infinity'::timestamptz else now() - p_desde end;
begin
  insert into public."GV_Tandas_Codigos_Usados" (codigo, fuente)
  select cod, fuente from (
    select upper(btrim(texto)) cod, 'evento' fuente from public."Registros_Produccion_Virgilio"
      where opcion in ('EP','TP','AP','TAP','PUB','APX','EPX') and ts_cliente >= v_d
    union all select upper(btrim(tanda)), 'entregas'    from public."Entregas_Virgilio"          where creado >= v_d
    union all select upper(btrim(tanda)), 'lock'        from public."GV_Tandas_Lock"             where ts >= v_d
    union all select upper(btrim(tanda)), 'facturacion' from public."Facturacion_NP"
    union all select upper(btrim(tanda)), 'lio'         from public."Etiquetas_Lio"
    union all select upper(btrim(tanda)), 'anulada'     from public."GV_Tanda_Anulada"
    union all select upper(btrim(tanda)), 'prog_web'    from public."PPP_Web_Programacion"
    union all select upper(btrim(tanda)), 'prog_isis'   from public."GV_PPP_Programacion_Diaria"
    union all select upper(btrim(tanda)), 'override'    from public."GV_PPP_Prog_Override"
    union all select upper(btrim(codigo)),'tanda_web'   from public."PPP_Web_Tandas"
    union all select upper(btrim(ref)),   'stock'       from public."Movimientos_Stock"
      where tipo in ('picking','separado','facturado')
  ) z
  where cod ~ '^[A-Z]+[0-9]+[A-Z]+$'
  on conflict (codigo) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

select public.gv_tandas_codigos_usados_sync();   -- semilla: 1.140 códigos el 18/09

select cron.schedule('gv-tandas-codigos-usados', '*/10 * * * *',
  $$select public.gv_tandas_codigos_usados_sync();$$);   -- jobid 95

-- 3. QUIÉN LA LEE -----------------------------------------------------------------------------
create or replace function public.gv_ppp_web_codigo_tomado(p_codigo text)
 returns boolean language sql stable set search_path to 'public','pg_temp' as $function$
  -- v19.69 (problema 407): un código que ya no figura en ninguna programación pero TIENE stock del
  -- pipeline sigue estando tomado. Si se recicla, los movimientos de la tanda vieja quedan bajo el
  -- mismo `ref` que los de la nueva: el índice `mov_stock_pipeline_dedup` frena el renombre
  -- («duplicate key») o, peor, la fusión mezcla cajas de dos tandas de épocas distintas. El
  -- `exists` sale por ese mismo índice —0,1 ms medidos— así que el loop que busca letra libre no
  -- se encarece.
  --
  -- v19.98 (Thomas, 18/09) — UN CÓDIGO DE TANDA NO SE RECICLA NUNCA MÁS.
  -- El stock no alcanzaba como memoria: un código se libera al renombrarse la tanda (sus filas se
  -- van al nombre nuevo) y volvía a la bolsa aunque hubiera tenido picking, armado, líos, candado
  -- y remitos. Ahí nace todo lo de esta semana: la fila que alguna tabla se olvidó de renombrar no
  -- queda huérfana, la ADOPTA otra tanda, y el dato pasa de viejo a mentiroso.
  select exists (select 1 from public."GV_Tandas_Codigos_Usados" where codigo = upper(btrim(p_codigo)))
      or exists (select 1 from public."GV_PPP_Programacion_Diaria" where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Programacion"    where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Tandas"          where codigo = p_codigo and estado <> 'descartada')
      or exists (select 1 from public."GV_PPP_Prog_Override"    where tanda = p_codigo)
      or exists (select 1 from public."Movimientos_Stock" m
                  where upper(btrim(m.ref)) = upper(btrim(p_codigo))
                    and m.tipo in ('picking', 'separado', 'facturado'));
$function$;

-- 4. Y EL RENOMBRE LO ANOTA EN EL MOMENTO EXACTO EN QUE EL CÓDIGO SE LIBERA -------------------
-- El cron lo haría igual, pero cada 10 min. Esto cierra la ventana de una tanda creada y
-- renombrada entre dos corridas. Va en `gv_ppp_tanda_renombrar`, arriba de todo, antes de mover
-- nada (el cuerpo completo y vivo de esa función está en sql/gv_tanda_lock_renombrar_v1996.sql
-- más este bloque):
--
--   insert into public."GV_Tandas_Codigos_Usados" (codigo, fuente) values (v_a, 'renombrada')
--     on conflict (codigo) do nothing;
--   insert into public."GV_Tandas_Codigos_Usados" (codigo, fuente) values (v_b, 'renombrada')
--     on conflict (codigo) do nothing;

-- =============================================================================================
-- PRUEBAS CORRIDAS (no leídas), con códigos de descarte borrados después
-- =============================================================================================
--   · E03F / E03G / E11B  → `gv_ppp_web_codigo_tomado` pasó de false a TRUE.
--   · `gv_ppp_tanda_renombrar('ZZ94Z','ZZ95Z')` → las dos quedaron en el ledger con
--     fuente='renombrada' y tomado=true.
--   · Los dos generadores siguen contestando y rápido: `gv_ppp_web_tanda_codigo_nuevo()` y
--     `gv_ppp_tanda_codigo_nuevo('2026-09-22','Zona 2 - CABA')` → E63A, 63 ms los dos juntos.
--
-- ⚠ Una prueba que NO sirve: pedir el `tomado` en el MISMO statement que el renombre. La función
--   es STABLE, así que usa el snapshot del statement y no ve la fila que se acaba de insertar —
--   da `false` y parece que no anduvo. Hay que preguntarlo en una sentencia aparte.
--
-- Chequeo: select count(*) from public."GV_Tandas_Codigos_Usados";   -- 1.140 al 18/09
