-- =============================================================================
-- v15.92 (2026-09-11) — candado anti doble-armado: la clave de dedup deja de mirar la TANDA
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv)
-- =============================================================================
-- QUE SE ROMPIO
--   Un pedido REPROGRAMADO a otra tanda y vuelto a armar se grababa ENTERO de nuevo en
--   Entregas_Virgilio y movia el stock una segunda vez (separar_pedidos -> a_facturar).
--   Ni el guard del front (_compTandaYaArmada, mira la TANDA) ni el trigger de la base
--   (clave np|tanda|cod_art) lo veian, porque la tanda era otra.
--
--   Casos encontrados el 2026-09-11 (4 NP, 57 cajas contadas por dos):
--     98532  D60E 09/09  ->  E10A 11/09   18 filas / 21 cajas
--     98533  D60E 09/09  ->  E10A 11/09   12 filas / 15 cajas
--     98490  D47C 27/08  ->  D54C 02/09   11 filas / 13 cajas
--     98583  D50C 31/08  ->  D50D 01/09    2 filas /  8 cajas
--
-- QUE CAMBIA
--   La clave pasa de  np|tanda|cod_art  a  np|cod_art  (las tres cantidades siguen en el
--   EXISTS). Un rearmado identico en otra tanda se descarta; un agregado real con otra
--   cantidad (ej. una caja por gondola) sigue entrando.
--
-- LIMPIEZA DE DATOS QUE ACOMPANO ESTE FIX (ya aplicada el 2026-09-11)
--   · Backup de las 43 filas duplicadas: tabla public."GV_Backup_Entregas_Dup_20260911".
--   · Se borraron esas 43 filas (el armado VIEJO; queda el de la tanda vigente).
--   · Compensacion en Movimientos_Stock (el libro no se borra, se compensa):
--     80 filas tipo 'ajuste', ref 'reversa armado duplicado NP <np> tanda <tanda> ...',
--     +57 cajas a separar_pedidos y -57 a a_facturar.
--
-- ROLLBACK
--   Volver a la clave vieja:  v_key := coalesce(new.np,'')||'|'||coalesce(new.tanda,'')||'|'||coalesce(new.cod_art,'');
--   y agregar de nuevo  and coalesce(e.tanda,'') = coalesce(new.tanda,'')  al EXISTS.
--   Datos: insert into public."Entregas_Virgilio" select * from public."GV_Backup_Entregas_Dup_20260911";
--   y borrar las filas de ajuste:  delete from public."Movimientos_Stock"
--     where tipo='ajuste' and ref like 'reversa armado duplicado%';
-- =============================================================================

create or replace function public.entregas_virgilio_dedup()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_key text;
begin
  v_key := coalesce(new.np,'') || '|' || coalesce(new.cod_art,'');
  perform pg_advisory_xact_lock(hashtextextended('entregas_virgilio:' || v_key, 0));
  if exists (
    select 1 from public."Entregas_Virgilio" e
     where coalesce(e.np,'')      = coalesce(new.np,'')
       and coalesce(e.cod_art,'') = coalesce(new.cod_art,'')
       and coalesce(e.cajas_entregadas, 0) = coalesce(new.cajas_entregadas, 0)
       and coalesce(e.cajas_falto, 0)      = coalesce(new.cajas_falto, 0)
       and coalesce(e.cajas_pedidas, 0)    = coalesce(new.cajas_pedidas, 0)
  ) then
    return null;
  end if;
  return new;
end;
$function$;

-- Chequeo: ninguna NP con Entregas en dos tandas distintas (las "(SIN TANDA)" son otro tema).
-- select np from (
--   select btrim(np::text) np, upper(btrim(tanda)) t from public."Entregas_Virgilio"
--    where nullif(btrim(tanda),'') is not null group by 1,2
-- ) z group by np having count(*) > 1;
