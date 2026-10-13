-- v29.89 (Luis, 2026-10-13) · el marcador en la base dice v29.88-vista: es la llave, no cambiarlo: "si, pasala a vista"
-- GP2.virgilio_insumo_stock deja de ser una TABLA que el cron 112 rehacia cada 10 min y pasa a
-- ser una VISTA EN VIVO sobre public. La pantalla "Insumos de Virgilio" de GP2 lee el saldo del
-- momento, sin cron y sin desfase.
--
-- POR QUE: lo que esperaba en una cola de 10 minutos era ~20 ms de trabajo.
--   calcular el stock de insumos en vivo (el bloque 1 del sync) ...... 20 ms / 163 filas
--   leer la copia ya escrita ........................................... 0,5 ms
--   el cron 112 entero (4 bloques con sus md5) ....................... 123 ms, cada 10 min
-- El motivo nunca fue el costo: el espejo se armo como COPIA por la Regla 0 de GP2 (GP2 no lee
-- public). Luis aprobo la excepcion; el precedente aprobado por Thomas es GP2.v_produccion_todas,
-- que lee reg_prod_3_0.
--
-- MEDIDO ANTES DE APLICAR (transaccion abortada):
--   la vista devuelve las MISMAS 163 filas y el MISMO md5 que la tabla copiada
--   anon 163 · authenticated 163  -> nadie pierde filas (la trampa de la v20.45: una vista con
--   security_invoker sobre una tabla con RLS no da error, devuelve MENOS filas). Medido aparte:
--   anon ve las 163 filas de Movimientos_Stock (deposito insumos) y las 129 de vista_insumos.
--   GP2.virgilio_insumos_sin_match_bundle sigue dando los mismos 84 sin asignar.
--
-- QUIEN LA LEE (medido): GP2.virgilio_insumos_sin_match_bundle (el editor de equivalencias) y
-- public.gv_insumo_isis_sync (solo la nombra en un comentario). NINGUNA vista. Nadie le escribia
-- salvo el bloque 1 del sync, que se saca aca.
--
-- NO SE TOCAN: los bloques 2, 3 y 4 de gv_gp2_espejo_sync (ubicaciones, Mapa, categorias) ni el
-- cron 112, ni gv_gp2_espejo_insumos / cron 152 / el trigger de Movimientos_Stock / el trigger
-- zz_gv_insumo_equiv_espejo (v29.87), que escriben el inventario de GP2 y son otra cosa.

-- 1) respaldo de la copia, cerrado (RLS + sin escrituras para anon/authenticated)
create table zz_backups."GV_Backup_VirgilioInsumoStock_20261013" as
  select * from "GP2".virgilio_insumo_stock;
alter table zz_backups."GV_Backup_VirgilioInsumoStock_20261013" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_VirgilioInsumoStock_20261013"
  from anon, authenticated;

-- 2) la copia pasa a VISTA EN VIVO (mismas 8 columnas; actualizado_en = now())
drop table "GP2".virgilio_insumo_stock;
create view "GP2".virgilio_insumo_stock with (security_invoker = true) as
  select m.cod_art::text                    as cod,
         coalesce(m.unidad,'')::text        as unidad,
         max(vi.nombre)::text               as nombre,
         max(vi.categoria)::text            as categoria,
         round(sum(m.delta),4)              as saldo,
         max(nullif(vi.ubicacion,''))::text as ubicacion,
         now()                              as actualizado_en,
         max(vi.isis)::text                 as isis
    from public."Movimientos_Stock" m
    left join public.vista_insumos vi on vi.cod = m.cod_art
   where m.deposito = 'insumos'
   group by 1,2;
comment on view "GP2".virgilio_insumo_stock is 'v29.88-vista: el stock de insumos de Virgilio EN VIVO (20 ms). Era una copia que un cron rehacia cada 10 min. Luis, 13/10. Excepcion aprobada a la Regla 0 de GP2 (precedente: GP2.v_produccion_todas).';
grant select on "GP2".virgilio_insumo_stock to anon, authenticated;
-- (una vista no lleva RLS: con security_invoker manda el privilegio del que lee. La policy
--  p_gp2_select de la tabla vieja se fue con la tabla.)

-- 3) el bloque 1 sale de gv_gp2_espejo_sync: ya no hay nada que copiar.
--    Se aplica sobre pg_get_functiondef (varias sesiones tocan este objeto), es idempotente y
--    FALLA con un raise si el texto no matchea, en vez de escribir una version vieja encima.
do $aplica$
declare def text; p1 int; p2 int; nuevo text;
begin
  def := pg_get_functiondef('public.gv_gp2_espejo_sync'::regproc);
  if position('v_regla' in def) > 0 then raise notice 'ya aplicado'; return; end if;
  p1 := position('  -- 1) stock de insumos' in def);
  p2 := position('  -- 2) ubicaciones de insumos' in def);
  if p1 = 0 or p2 = 0 or p2 <= p1 then
    raise exception 'ABORTA: no encontre el bloque 1 en el cuerpo vivo de gv_gp2_espejo_sync (p1=% p2=%)', p1, p2;
  end if;
  nuevo := left(def, p1 - 1)
        || '  -- 1) stock de insumos: YA NO SE COPIA. "GP2".virgilio_insumo_stock es una VISTA en vivo (Luis, 13/10). La regla vive en v_regla.' || chr(10)
        || substr(def, p2);
  -- el marcador va en CODIGO, no en un comentario: gv_reglas_perdidas saca los comentarios
  -- antes de buscar (regla v21.82), asi que un marcador comentado vigila el rotulo, no la regla.
  nuevo := replace(nuevo,
    'declare h_new text; h_old text; out text := '''';',
    'declare h_new text; h_old text; out text := ''''; v_regla constant text := ''v29.88-vista'';');
  execute nuevo;
end $aplica$;

-- 4) centinela (id 421): si otra sesion repone el bloque 1 desde una copia vieja, avisa
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_gp2_espejo_sync', 'funcion', 'v29\.88-vista',
       'El stock de insumos de Virgilio es una VISTA en vivo (GP2.virgilio_insumo_stock): el sync NO lo copia mas. Si vuelve el bloque 1, la pantalla de GP2 lee una copia de 10 min atras.',
       'Luis', 'v29.88'
 where not exists (select 1 from public."GV_Reglas_Centinela"
                    where objeto='gv_gp2_espejo_sync' and patron='v29\.88-vista');

-- VERIFICACION (dio todo verde el 13/10):
--   clase v (vista) · security_invoker=true · 163 filas en 19,5 ms · md5 identico al respaldo
--   anon 163 · authenticated 163 · bundle sin asignar 84 · sync "sin cambios" · bloque 1 fuera
--   respaldo con RLS y sin INSERT para anon · los 2 triggers de insumo_equivalencia vivos
--   gv_reglas_perdidas 0 · gv_huellas_cambiadas 0 · gv_endpoints_rotos 0 · centinela 421 no flojo
--
-- ROLLBACK (vuelve a la copia cada 10 min):
--   drop view "GP2".virgilio_insumo_stock;
--   create table "GP2".virgilio_insumo_stock as
--     select * from zz_backups."GV_Backup_VirgilioInsumoStock_20261013";
--   alter table "GP2".virgilio_insumo_stock add primary key (cod, unidad);
--   alter table "GP2".virgilio_insumo_stock alter column actualizado_en set default now();
--   alter table "GP2".virgilio_insumo_stock enable row level security;
--   create policy p_gp2_select on "GP2".virgilio_insumo_stock for select to anon, authenticated using (true);
--   grant select on "GP2".virgilio_insumo_stock to anon, authenticated;
--   -- y reponer el bloque 1 del sync desde sql/gv_gp2_espejo_v2517.sql + el delete de la fila 421
