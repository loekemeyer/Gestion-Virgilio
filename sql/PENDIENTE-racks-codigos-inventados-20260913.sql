-- ============================================================================
-- PENDIENTE DE EJECUTAR — espera el "dale" de Luis (preferencia 18: nada de
-- INSERT/UPDATE/DELETE sin su sí en el momento). NADA de esto se corrió.
--
-- Problema 110 de github_repo_problemas: el depósito inventa códigos en los racks
-- porque no había dónde decir "esto es el mismo artículo en otro estado / de otra
-- importación". Luis identificó cada uno el 13/09.
--
-- ⚠ LOS CÓDIGOS MALOS ESTÁN EN **DOS** TABLAS, no en una: `Racks_Planimetria`
--    (la ocupación) y `GV_Lugar_Item` (la planimetría). El 1546903 está en las dos.
--
-- QUÉ LEE CADA TABLA (esto es lo que se mueve si se ejecuta):
--   Racks_Planimetria → vista `vista_insumos` + 6 lecturas del front (Bajar de racks,
--     movedor de palets, alta de insumos, Guardar orden, excedente). Ningún trigger.
--   GV_Lugar_Item     → vistas `gv_lugar_articulo`, `gv_ocupacion_lugar` y
--     `gv_gondola_divergente`. Los racks NO entran a `window.GONDOLA` (eso es
--     tipo='gondola'), así que el picking no se toca. Ningún trigger.
--
-- ============================================================================
-- (1) BASTIDOR DEL 546 → código único `546V`   ✅ decisión cerrada
--     Luis: "Tendría que llamarse solo 546V".
--     Hoy son 891 cajas (297 master) en 3 posiciones bajo DOS grafías:
--       Racks_Planimetria id 176 · AD12 · 1546903 ·  63 master / 189 cajas
--       Racks_Planimetria id 178 · AE09 · 1546903 · 117 master / 351 cajas
--       Racks_Planimetria id 275 · X13  · VASTIDOR · 117 master / 351 cajas
--       GV_Lugar_Item          · AD12 · 1546903 (cap 0)
--       GV_Lugar_Item          · AE09 · 1546903 (cap 0)   [AE09 además tiene 366E]
--     `546V` está LIBRE: 0 filas en Insumos, OC_Maximos, Movimientos_Stock y
--     Racks_Planimetria. Los dos códigos viejos tienen 0 movimientos de stock, así
--     que no hay saldo que migrar.

-- backup
create table zz_backups."GV_Backup_racks_codigos_20260913" as
  select 'Racks_Planimetria' tabla, id::text clave, cod_art, sector, emp, estado,
         master_cajas::text a, innercajas::text b
    from public."Racks_Planimetria"
   where upper(btrim(cod_art)) in ('1546903','VASTIDOR','1000900','522S')
  union all
  select 'GV_Lugar_Item', sector||'|'||cod||'|'||clase, cod, sector, null, null, cajas_max::text, unidad
    from public."GV_Lugar_Item"
   where upper(btrim(cod)) in ('1546903','VASTIDOR','1000900','522S');
alter table zz_backups."GV_Backup_racks_codigos_20260913" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_racks_codigos_20260913" from anon, authenticated;

-- alta del insumo
insert into public."Insumos" (cod, nombre, categoria, ubicacion, creado_por, creado)
values ('546V', 'Bastidor 546', 'importados', 'AD12', 'Luis (claude-remote)', now())
on conflict do nothing;

-- unificar las dos grafías
update public."Racks_Planimetria" set cod_art = '546V'
 where upper(btrim(cod_art)) in ('1546903','VASTIDOR');          -- espera 3 filas
update public."GV_Lugar_Item" set cod = '546V'
 where upper(btrim(cod)) in ('1546903','VASTIDOR');              -- espera 2 filas

-- verificación
select cod_art, sector, emp, master_cajas, innercajas from public."Racks_Planimetria"
 where upper(btrim(cod_art)) in ('546V','1546903','VASTIDOR') order by sector;
select sector, cod from public."GV_Lugar_Item" where upper(btrim(cod)) in ('546V','1546903','VASTIDOR') order by sector;

-- ============================================================================
-- (2) LA ESPIRAL `1000900` — ⛔ FALTA QUE LUIS ELIJA EL CÓDIGO
--     Luis: "es todo lo mismo, pero de diferentes importaciones".
--     Candidatos que ya existen en Insumos, todos categoría importados:
--       007        "Espiral (Chef) (500 u/MC)"  ubic Z2     saldo   3.500 Uni
--       H201PART   "Espiral TN"                 ubic AD04   saldo 102.000 MC/Uni
--     (NO se consideran `N°46B` "Alambre p/ espiral 520", que es fleje en Kg, ni
--      `TMP-0003` "Varillas 3 mm espiral doble aleta", partes_crudo en paquetes:
--      son materia prima, no el espiral terminado. Si Luis dice que también son lo
--      mismo, se agregan.)
--     Lo que hay hoy sin contar: Racks_Planimetria id 277 · Y4 · 40 master / 160 cajas.
--     ⚠ El sector Y4 no existe en GV_Lugar: es una de las 37 posiciones ocupadas
--       sin planimetría cargada.
-- update public."Racks_Planimetria" set cod_art = '<EL CODIGO QUE ELIJA>' where id = 277;

-- ============================================================================
-- (3) `522S` → `522E` — ⛔ FALTA DEFINIR CUÁNDO ENTRA AL STOCK
--     Luis: "es el artículo suelto sin cartón del importado 522E. Vamos a mandarlo
--     a envasar y pasa a ser 522E".
--     Hoy: Racks_Planimetria id 199 · W04 · 20 master / 80 cajas, sin contar.
--     El 522E ya existe como artículo y tiene: racks 190 · terminado 26 ·
--     separar_pedidos 1 · para_envasar **0**.
--     Dos caminos, y cambian el número que ve el sistema:
--       (a) renombrar la fila del rack a 522E ahora → el rack dice 522E pero el
--           stock sigue sin contar las 80 (Racks_Planimetria no es el stock).
--       (b) además cargar las 80 cajas como 522E en el depósito `para_envasar`, que
--           es justo el depósito que existe para esto → pasan a contarse, y al
--           envasarlas se mueven para_envasar → terminado.
--     (b) es lo correcto si esas 80 cajas EXISTEN y son vendibles tras envasar.
--     Es plata en el stock, así que lo decide Luis.
-- update public."Racks_Planimetria" set cod_art = '522E' where id = 199;
-- insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
-- values ('522E','para_envasar',80,'ajuste','522S sin carton, rack W04 (problema 110)','<legajo>','LK');
