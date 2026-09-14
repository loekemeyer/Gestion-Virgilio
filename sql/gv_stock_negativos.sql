-- =====================================================================
--  gv_stock_negativos — el ⛔ con dueño (v17.01, 2026-09-14)
--
--  POR QUÉ EXISTE
--  El 11 y el 14/09 hubo 13 códigos en negativo (ver §3.eb). Al revisarlo apareció
--  que la detección NO había fallado: el trigger `trg_stock_negativo_telegram` avisó
--  las 13 veces, y `telegram_outbox` tiene los 13 mensajes enviados — incluidos 2 el
--  11/09 a las 18:34, en el mismo minuto en que la corrección manual dejó al 338 y
--  al 566E en negativo. Si alguien miraba ese aviso, los otros 11 no pasaban.
--  **No faltaba detección: faltaba que el ⛔ tuviera dueño.** Un mensaje de Telegram
--  no tiene dueño; una tarea de Planify sí.
--
--  ¿SE PUEDE AUTOMATIZAR LA CORRECCIÓN? Sólo la mitad, y la vista lo dice explícito:
--
--   • `contable` (a_facturar, separar_pedidos) — son PAPELES. Un negativo ahí siempre
--     es error de registro, nunca falta mercadería, y se corrige desde la base. Esta
--     mitad ya está automatizada: el clamp de la v16.92 hace que `a_facturar` no pueda
--     quedar negativo. Si igual aparece uno, significa que el clamp falló y es bug.
--   • `fisico` (terminado/góndola, excedente, racks, a_guardar, insumos) — significa que
--     se descontaron cajas que el sistema no sabía que estaban. **No es automatizable**:
--     nadie puede inventar de dónde salieron. Hay que ir y CONTAR. Lo que sí se
--     automatiza es el trabajo de acordarse, y eso es lo que hace este módulo.
--
--  QUÉ HACE
--   • `gv_stock_negativos` — vista de los negativos vivos, **canonizando el código**
--     (agrupa por `regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','')`). Esto no es
--     cosmético: medir por `cod_art` crudo hace ver negativos que no existen — pasó,
--     el 066 aparecía en -28 porque una grafía tenía el picking y la otra el saldo.
--   • `gv_stock_negativos_tarea()` — mantiene UNA sola tarea de Planify viva para Luis
--     Rial Otero (52, que es a quien el dueño derivó lo de stock). Si hay negativos la
--     crea, y en las corridas siguientes le **reescribe la nota** con lo que falta hoy
--     (regla del dueño: la nota se reescribe, no se le agrega texto encima). Si ya no
--     hay ninguno, cierra la tarea sola y no vuelve a molestar.
--   • cron `gv-stock-negativos-tarea` (jobid 86, lun–vie 08:00 ART / 11:00 UTC).
--
--  El aviso de Telegram NO se toca: sigue siendo la alerta inmediata. Esto es la red
--  de abajo, para lo que el aviso inmediato no alcanza a resolver en el día.
--
--  Probado con negativos simulados dentro de una transacción con ROLLBACK (un
--  `fisico` en racks y un `contable` en a_facturar, con el trigger de Telegram
--  deshabilitado para no mandar un ⛔ falso): crea UNA tarea, la segunda llamada la
--  actualiza sin duplicar, y clasifica bien las dos clases. Esa prueba encontró un
--  bug antes de que llegara al cron: `prio='alta'` viola `tasks_prio_check` (los
--  valores válidos son `normal` y `urgente`), y como la función atrapa la excepción,
--  el cron habría fallado en silencio todos los días.
--
--  Rollback: `select cron.unschedule('gv-stock-negativos-tarea');`
--            `drop function public.gv_stock_negativos_tarea();`
--            `drop view public.gv_stock_negativos;`
-- =====================================================================

-- v17.10: se recrea (DROP + CREATE: no se puede renombrar columnas con OR REPLACE).
drop view if exists public.gv_stock_negativos;
create view public.gv_stock_negativos
with (security_invoker = true) as
with base as (
  select regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') k,
         btrim(m.cod_art) cod, m.deposito, coalesce(m.empresa,'Mixto') empresa, m.delta, m.ts
  from public."Movimientos_Stock" m
),
-- v17.10: la particion por EMPRESA solo se mira en los depositos de SALDO ESTABLE
-- (gondola, excedente, racks, para_envasar, insumos). Los de TRANSITO -a_facturar,
-- separar_pedidos y a_guardar- entran por un evento y salen por otro, y desde el corte
-- pkc_empresa_desde del 11/09 los dos eventos no siempre traen la misma empresa: la
-- recepcion del 508 vino como LK y el guardado de hoy como Mixto, asi que la particion
-- Mixto quedo en -24 aunque las 24 cajas se guardaron y el total por codigo da 0.
-- Mirar la particion ahi son falsos positivos; el saldo que vale es el del codigo.
por_emp as (
  select k, min(cod) cod, deposito, empresa, round(sum(delta),2) saldo, max(ts) ultimo_mov
  from base where deposito not in ('a_facturar','separar_pedidos','a_guardar')
  group by 1,3,4 having round(sum(delta),2) < 0
),
-- por CODIGO entero, en cualquier deposito: si el total da negativo, falta algo de verdad
por_cod as (
  select k, min(cod) cod, deposito, 'TODAS'::text empresa, round(sum(delta),2) saldo, max(ts) ultimo_mov
  from base group by 1,3 having round(sum(delta),2) < 0
),
u as (select * from por_emp union all select * from por_cod)
select u.cod, u.k cod_norm, u.deposito, u.empresa, u.saldo, u.ultimo_mov,
       case when u.deposito in ('a_facturar','separar_pedidos','a_guardar') then 'transito' else 'fisico' end clase,
       case when u.deposito in ('a_facturar','separar_pedidos','a_guardar')
            then 'Deposito de transito: el saldo negativo es error de registro, no falta mercaderia. Lo corrige Sistemas.'
            else 'Falta mercaderia real: se descontaron cajas que el sistema no sabia que estaban. Hay que CONTAR y cargar el faltante.'
       end que_significa,
       (select o.descripcion from public."OC_Maximos" o
         where regexp_replace(upper(btrim(o.cod)),'^0+(?=.)','') = u.k limit 1) descripcion
from u
order by (case when u.deposito in ('a_facturar','separar_pedidos','a_guardar') then 'transito' else 'fisico' end), u.saldo;

grant select on public.gv_stock_negativos to anon, authenticated;

CREATE OR REPLACE FUNCTION public.gv_stock_negativos_tarea()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'planify', 'pg_temp'
AS $function$
declare
  v_emp   int := 52;                 -- Luis Rial Otero
  v_name  text := 'Stock en negativo: contar y cargar el faltante';
  v_hoy   text := to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD');
  v_id    int;
  v_n     int;
  v_det   text;
  v_nota  text;
begin
  select count(*), string_agg(
           '- ' || cod || coalesce(' ('||descripcion||')','') || ': ' || deposito
           || ' en ' || saldo::text || ' [' || clase || ']', E'\n' order by clase, saldo)
    into v_n, v_det
    from public.gv_stock_negativos;

  select t.id into v_id from planify.tasks t
   where t.name = v_name and t.employee_id = v_emp and not t.done
   order by t.id desc limit 1;

  if v_n = 0 then
    if v_id is not null then
      update planify.tasks
         set done = true,
             note = 'HECHO: ya no hay ningun saldo negativo en Movimientos_Stock (chequeado el '
                    || v_hoy || '). Generada automaticamente por el control de stock negativo.',
             updated_at = now()
       where id = v_id;
      return format('ok sin_negativos tarea_cerrada=%s', v_id);
    end if;
    return 'ok sin_negativos';
  end if;

  v_nota := 'Falta: hay ' || v_n || ' saldo(s) de stock en NEGATIVO. Los marcados [fisico] '
         || 'significan que se descontaron cajas que el sistema no sabia que estaban: hay que CONTAR '
         || 'el articulo en su deposito y cargar el faltante (no se puede corregir solo desde la base). '
         || 'Los marcados [contable] son error de registro y los corrige Sistemas.' || E'\n\n' || v_det
         || E'\n\n' || 'Lista siempre al dia: select * from public.gv_stock_negativos;'
         || E'\n' || 'Generada automaticamente por el cron gv-stock-negativos-tarea (control de stock '
         || 'negativo, pedido de Thomas). Actualizada el ' || v_hoy || '.';

  if v_id is not null then
    -- la nota se REESCRIBE con lo que falta hoy, no se le agrega texto encima
    update planify.tasks set note = v_nota, updated_at = now() where id = v_id;
    return format('ok negativos=%s tarea_actualizada=%s', v_n, v_id);
  end if;

  insert into planify.tasks (name, type, prio, time, date, note, rec, done, assignment_type,
    employee_id, department_id, system_generated, broadcast, created_at, updated_at)
  values (v_name, 'tarea', 'normal', '09:00', v_hoy, v_nota, 'none', false, 'employee',
    v_emp, null, true, false, now(), now())
  returning id into v_id;
  return format('ok negativos=%s tarea_creada=%s', v_n, v_id);
exception when others then
  return 'error: ' || sqlerrm;
end;
$function$;

revoke execute on function public.gv_stock_negativos_tarea() from public, anon, authenticated;

-- cron (jobid 86): lun-vie 08:00 ART = 11:00 UTC
-- select cron.schedule('gv-stock-negativos-tarea', '0 11 * * 1-5',
--   $$select public.gv_stock_negativos_tarea();$$);

-- ⚠⚠ v17.07 — LA VISTA TENÍA UN PUNTO CIEGO Y SE CORRIGIÓ.
-- Agrupaba sólo por CÓDIGO, así que el 14/09 devolvía 0 mientras la pantalla mostraba
-- 437E/438E/809E en rojo: el negativo estaba en la partición `empresa='Mixto'` (−1, −2,
-- −43) y LK+CH+Mixto sumados daban positivo. **El saldo de un depósito es por empresa.**
-- Criterio nuevo, que alerta sólo de lo real:
--   (a) saldo negativo por (código, empresa) SÓLO en depósitos FÍSICOS — ahí una
--       partición negativa significa que faltan cajas de verdad;
--   (b) saldo negativo por CÓDIGO entero en cualquier depósito.
-- En los depósitos CONTABLES no se mira por empresa a propósito: el corte
-- `pkc_empresa_desde` del 11/09 deja lo viejo en 'Mixto' y lo nuevo en LK/CH, así que las
-- particiones se compensan entre sí (95 casos medidos, todos contables, que suman 0 por
-- código). Alertarlos sería ruido puro y le llenaría la tarea de Planify a Luis.
-- Verificado: con el criterio nuevo la vista da 0 hoy, y sobre el backup de las 27 filas
-- duplicadas habría devuelto exactamente los 3 casos (−1, −2, −43).

