-- v18.71 (2026-09-16) — los dos pendientes que quedaron del lock: el monitor que contaba horas
-- de gente que ya se fue, y el anular que el celular deshacía solo.
--
-- ############################################################################################
-- 1. gv_tanda_status — una fase abierta por alguien que FICHÓ SALIDA no está "en curso"
-- ############################################################################################
-- El 16/09 a las 8 de la mañana el monitor mostraba «JC 17h54» en E25A y «FO 16h18» en E23A.
-- Los dos habían fichado FJ («terminé día») a las 17 del día anterior sin cerrar, así que el
-- chip siguió corriendo toda la noche y al supervisor le parecía que estaban trabajando.
--
-- FJ y cerrar un picking son cosas independientes en el modelo, y eso no cambia. Lo que cambia
-- es la LECTURA: si hay un FJ posterior a la apertura, la fase está ABANDONADA. La duración se
-- congela en ese FJ — lo que se trabajó de verdad: 2,8 h y 0,9 h, no 17,9 y 16,3.
--
-- ⚠ El FJ que importa es el PRIMERO después de abrir, no el último del operario. Con el último,
-- una tanda abierta hace un mes daría una duración de un mes.
--
-- Vista NUEVA: `vista_tanda_status` la comparte Producción Virgilio (5 usos en su index.html).

create or replace view public.gv_tanda_status as
select b.*,
       fp.ts as pick_fj_ts,
       fa.ts as arm_fj_ts,
       (b.last_pick_op = 'EP' and fp.ts is not null) as pick_abandonado,
       (b.last_arm_op  = 'AP' and fa.ts is not null) as arm_abandonado
  from public.vista_tanda_status b
  left join lateral (
    select min(r.ts_cliente) ts from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'FJ' and r.legajo = b.pick_legajo and r.ts_cliente >= b.pick_start_ts
  ) fp on b.last_pick_op = 'EP'
  left join lateral (
    select min(r.ts_cliente) ts from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'FJ' and r.legajo = b.arm_legajo and r.ts_cliente >= b.arm_start_ts
  ) fa on b.last_arm_op = 'AP';
alter view public.gv_tanda_status set (security_invoker = true);
grant select on public.gv_tanda_status to anon, authenticated;

-- ############################################################################################
-- 2. Anular deja de BORRAR el evento — el celular lo resucitaba
-- ############################################################################################
-- `Registros_Produccion_Virgilio` tiene un UNIQUE sobre `client_id`, y el front postea con
-- `Prefer: resolution=ignore-duplicates`. Eso es lo que hace que un reenvío de la cola offline
-- no duplique nada... siempre que la fila siga ahí.
--
-- Al BORRARLA, su client_id queda libre: ya no hay contra qué chocar y el reenvío entra como
-- evento nuevo. Pasó el 15/09 con E25A — borrado 16:56, reinsertado 17:17 por el celular de JC
-- al fichar FJ, con el mismo `ts_cliente` y un `id` nuevo. La anulación duró 21 minutos.
--
-- La salida barata: **no borrar, cambiar el código de opción** (EP → EPX, PKC → PKCX).
--   · la fila sigue ocupando su client_id  → el reenvío choca y se descarta;
--   · ningún consumidor la cuenta          → los 21 funciones y 11 vistas que leen este log
--     filtran por `opcion = 'EP'` / `'PKC'` con igualdad exacta (verificado: ninguna usa
--     LIKE 'EP%' ni regex), así que no hay que tocar ni una;
--   · y queda el rastro de que hubo una anulación, con fecha y motivo en `descripcion`.
--
-- La alternativa era una columna `gv_anulado` y enseñarles a los 32 consumidores a saltearla.
-- Un solo olvido = un picking anulado que sigue contando.

create or replace function public.gv_anular_picking_virgilio(p_legajo text, p_tanda text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_leg   text := btrim(coalesce(p_legajo,''));
  v_tanda text := upper(btrim(coalesce(p_tanda,'')));
  v_id uuid; v_ts timestamptz; v_hecho boolean; v_nota text;
begin
  if v_leg = '' or v_tanda = '' then return 'faltan_datos'; end if;

  select r.id, coalesce(r.ts_cliente, r.created_at) into v_id, v_ts
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'EP' and r.legajo = v_leg
     and upper(btrim(coalesce(r.texto,''))) = v_tanda
     and coalesce(r.ts_cliente, r.created_at) > now() - interval '3 days'
   order by coalesce(r.ts_cliente, r.created_at) desc limit 1;
  if v_id is null then return 'sin_ep'; end if;

  select exists (
    select 1 from public."Registros_Produccion_Virgilio" c
     where c.opcion in ('TP','TAP')
       and upper(btrim(split_part(coalesce(c.texto,''),'|',1))) = v_tanda
       and not public.es_legajo_test(c.legajo)) into v_hecho;

  v_nota := 'anulado ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','DD/MM HH24:MI');

  if v_hecho then
    update public."Registros_Produccion_Virgilio"
       set opcion = 'PKCX', descripcion = 'Picking anulado (la tanda ya estaba hecha) · ' || v_nota
     where opcion = 'PKC' and legajo = v_leg
       and upper(btrim(coalesce(texto,''))) like v_tanda || '|%'
       and coalesce(ts_cliente, created_at) >= v_ts;
    update public."Registros_Produccion_Virgilio"
       set opcion = 'EPX', descripcion = 'Picking anulado (la tanda ya estaba hecha) · ' || v_nota
     where id = v_id;
    begin perform public.gv_tanda_lock_anular(v_tanda, 'picking', v_leg); exception when others then null; end;
    return 'ep_fantasma_limpiado';
  end if;

  update public."Registros_Produccion_Virgilio"
     set opcion = 'PKCX', descripcion = 'Picking anulado · ' || v_nota
   where opcion = 'PKC' and legajo = v_leg
     and upper(btrim(coalesce(texto,''))) like v_tanda || '|%'
     and coalesce(ts_cliente, created_at) >= v_ts;
  update public."Registros_Produccion_Virgilio"
     set opcion = 'EPX', descripcion = 'Picking anulado · ' || v_nota
   where id = v_id;

  update public."Movimientos_Stock" set delta = 0
   where tipo = 'picking' and upper(btrim(ref)) = v_tanda and delta <> 0
     and coalesce(legajo,'') = v_leg and ts >= v_ts;

  begin perform public.gv_tanda_lock_anular(v_tanda, 'picking', v_leg); exception when others then null; end;
  return 'ok';
end $$;
revoke execute on function public.gv_anular_picking_virgilio(text,text) from public;
grant execute on function public.gv_anular_picking_virgilio(text,text) to anon, authenticated;

-- Prueba del ciclo completo contra la base (client_id 'prueba_reenvio_1866', ya borrado):
--   1. entra el EP                                          → 1 fila, opcion 'EP'
--   2. gv_anular_picking_virgilio(...)                      → 'ok'
--   3. el celular REENVÍA el mismo evento (on conflict do nothing, que es lo que manda el front)
--      → la fila sigue siendo 'EPX'. NO revivió. Antes se insertaba una fila nueva con 'EP'.
--
-- Rollback:
--   drop view public.gv_tanda_status;
--   ... y volver el cuerpo de gv_anular_picking_virgilio a los DELETE (sql/..._v1870.sql).
