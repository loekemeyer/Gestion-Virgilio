-- v29.87 (Luis, 13/10/2026): "por que tarda 10 min? deberia ser lectura de una tabla en
-- conjunto, instantaneo, no?"
--
-- MEDIDO ese dia, y tenia razon:
--   calcular el stock de insumos EN VIVO (el bloque 1 de gv_gp2_espejo_sync)  ->  20 ms (163 filas)
--   el cron 112 gv-gp2-espejo-sync entero (4 bloques con sus md5)             -> 123 ms, cada 10 min
--   gv_gp2_espejo_insumos(null, true) (los 5 rubros)                          ->  28 ms, cada 30 min (:19/:49)
--   leer el espejo ya copiado                                                 -> 0,5 ms
-- O sea: ~40 ms de trabajo esperando en una cola de 10 y 30 minutos. El motivo no es el costo:
-- es que el espejo se armo como COPIA (Regla 0 de GP2: GP2 no lee public).
--
-- EL HUECO CONCRETO que cierra este parche: el stock de insumos ya se adelanta solo en cada
-- movimiento (trigger zz_gv_gp2_espejo_insumos de Movimientos_Stock), pero VINCULAR una
-- equivalencia NO es un movimiento, asi que un codigo recien vinculado no mostraba su stock en
-- GP2 hasta el cron de los :19/:49. Ahora lo dispara el vinculo.
--
-- Medido en transaccion abortada: vincular N°56 tardo 57 ms y sus 873 kg aparecieron en el acto
-- en "Sector Fleje en Virgilio" (ubicacion 75). Un vinculo que cambia SOLO el ISIS no dispara
-- el espejo (4,8 ms, 0 filas de log): no se paga lo que no hace falta.

create or replace function public.gv_insumo_equiv_espejo() returns trigger
language plpgsql security definer set search_path to 'public' as $f$
begin
  -- v29.87-equiv-espejo
  if new.componente_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.componente_id is not distinct from new.componente_id then return new; end if;
  begin
    perform public.gv_gp2_espejo_insumos(new.cod_virgilio, false);
  exception when others then
    -- NUNCA frena el vinculo: lo rehace el cron de los :19/:49
    insert into public."GV_GP2_Espejo_Log"(ts, componente_id, cods, resultado, motivo)
    values (now(), new.componente_id, new.cod_virgilio, 'error', 'al vincular: ' || substr(SQLERRM,1,180));
  end;
  return new;
end $f$;

create or replace trigger zz_gv_insumo_equiv_espejo
  after insert or update of componente_id on "GP2".insumo_equivalencia
  for each row execute function public.gv_insumo_equiv_espejo();

-- el centinela (id 420)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_insumo_equiv_espejo', 'funcion', 'gv_gp2_espejo_insumos',
       'Vincular una equivalencia de insumos dispara el espejo de ESE codigo en el acto (28 ms): el cron de los :19/:49 es la red, no el camino.',
       'Luis', 'v29.87'
 where not exists (select 1 from public."GV_Reglas_Centinela" where objeto = 'gv_insumo_equiv_espejo');

-- ROLLBACK (una linea; el cron de los :19/:49 sigue cubriendo igual, con su demora):
--   alter table "GP2".insumo_equivalencia disable trigger zz_gv_insumo_equiv_espejo;
--
-- LO QUE NO SE HIZO, y es decision de Luis (medido: 20 ms):
--   GP2.virgilio_insumo_stock es una TABLA copiada por el cron 112 cada 10 min. El bloque 1 de
--   gv_gp2_espejo_sync es textualmente un select: podria ser una VISTA en el schema GP2 y la
--   pantalla leeria el saldo de Virgilio EN VIVO, sin cron y sin desfase. Lo unico que lo frena es
--   la Regla 0 (ninguna vista de GP2 lee tablas de negocio de public), que ya tiene precedente
--   aprobado por el dueno: GP2.v_produccion_todas lee reg_prod_3_0. No se cambia sin su si.
