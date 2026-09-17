-- ════════════════════════════════════════════════════════════════════════════════════
-- v19.33 (2026-09-17) — CONTEO FISICO DEL 809E EN EL DEPOSITO
-- ════════════════════════════════════════════════════════════════════════════════════
-- Luis contó el 809E el 17/09 y pasó los números. Esto es lo que se ajustó con ellos.
-- Cierra el pendiente que venía anotado como "conteo físico del 809E" y la contradicción
-- de AD06 (§ CLAUDE.md, "LAS TABLAS QUE VALEN").
--
-- ── Lo contado ──────────────────────────────────────────────────────────────────────
--   809E LK : J14 = 14 cajas (J13 vacía) · AD05 = 28 MC · en ningún otro rack
--   809E CH : M14 = 104 cajas (M13 y M15 vacías) · sin rack
--   M16     : 9 cajas de **809**, otro código, también de Chef (el secundario del 809E)
--   AD06    : 368E, 14 MC  (o sea: AD06 NO tiene 809E)
--
-- El 809E va a 12 cajas por master (28 MC = 336 cajas, 30 MC = 360; sale de las propias
-- filas de `Racks_Planimetria`, que guarda `master_cajas` e `innercajas`).
--
-- ── 1. Movimientos_Stock: 4 ajustes ─────────────────────────────────────────────────
-- Tipo `ajuste`, ref "ajuste de admin en base a conteo del 17.09" (como pidió Luis), con
-- la ubicación en su columna. Empresa EXPLÍCITA: es un código dual, y el trigger respeta
-- LK/CH explícito (`v_explicita`) sin intentar resolverlo por la NP.
--
-- | cod  | emp | depósito  | antes | conteo | ajuste |
-- |------|-----|-----------|-------|--------|--------|
-- | 809E | LK  | terminado |    21 |     14 |     -7 |
-- | 809E | CH  | terminado |   110 |    104 |     -6 |
-- | 809E | LK  | racks     |     0 |    336 |   +336 |
-- | 809E | CH  | racks     |   336 |      0 |   -336 |
--
-- ⚠ Las 9 cajas de M16 NO son 809E: son **809**, el código secundario, también de Chef
-- (corrección de Luis en el momento). Y no hacía falta tocarlo: `809` ya estaba en 9 en el
-- libro, y M16 ya estaba asignado a `809` en `GV_Lugar_Item`. O sea que esa góndola estaba
-- bien cargada — el error habría sido mío si contaba esas 9 como 809E.
--
-- ⚠ `separar_pedidos` CH = 6 NO se tocó, y está bien: es la tanda **E03G**, pickeada el
-- 16/09 y todavía sin separar. Esas 6 cajas están en la mesa de armado, no en la góndola,
-- así que el conteo del depósito no las ve. Ajustarlas habría borrado un pedido en curso.
--
-- ── 2. El rack AD05 es de LOEKEMEYER, no de Chef ────────────────────────────────────
-- El conteo lo deja claro: las 28 MC de AD05 son 809E de Loekemeyer, y `GV_Lugar` decía
-- que AD05 era un rack CH. Es el mismo caso que el de la góndola P39 con el 396 (Luis,
-- 16/09: *"no es un dual mal asignado, es LK. la góndola está mal asignada, ajustala"*),
-- así que se aplicó el mismo criterio: **el lugar se corrige, el artículo no se mueve.**
--   · `GV_Lugar.AD05.empresa`            CH → LK (con nota)
--   · `Racks_Planimetria` AD05 / 809E    emp CH → LK (28 MC / 336 cajas, sin cambio)
--
-- ── 3. Filas de rack que el conteo no encontró ──────────────────────────────────────
-- Se borraron de `Racks_Planimetria` (respaldo abajo):
--   · AD06 / 809E / CH / 30 MC / 360 cajas  → AD06 hoy tiene 368E
--   · AE11 / 809E / LK /  8 MC /  64 cajas  → "no está en ningún otro rack"
-- Ninguna de las dos estaba en el libro de stock (el saldo de racks eran las 336 de AD05),
-- así que borrarlas no movió ningún número: eran layout desactualizado. **Con esto se
-- resuelve la contradicción de AD06** que quedaba anotada en el CLAUDE.md.
-- `368E` no se tocó: sus 4 racks (AD06, X05, X30, Y12) suman 236 cajas y coinciden con el
-- libro.
--
-- ── 4. Lugares que el conteo encontró y no estaban asignados ────────────────────────
-- Alta en `GV_Lugar_Item`: **AD05 / 809E** (rack). Los racks del 809E no figuraban como
-- ítem (los del 368E sí). J13, M13 y M15 quedan asignados aunque estén vacíos: el lugar
-- sigue siendo del artículo. **M16 no se toca**: ya era del `809`.
--
-- ── Resultado ───────────────────────────────────────────────────────────────────────
--   809E LK terminado  14  · racks 336
--   809E CH terminado 104  · separar_pedidos 6 (E03G, en curso)
--   809  CH terminado   9  (ya estaba bien, no se tocó)
--   368E LK terminado   8  · racks 236   (sin cambios)
--
-- ── Respaldos ───────────────────────────────────────────────────────────────────────
--   zz_backups."GV_Backup_Conteo809E_Racks_20260917"      (7 filas de Racks_Planimetria)
--   zz_backups."GV_Backup_Conteo809E_Lugar_20260917"      (4 filas de GV_Lugar)
--   zz_backups."GV_Backup_Conteo809E_LugarItem_20260917"  (9 filas de GV_Lugar_Item)
--   zz_backups."GV_Backup_Conteo809E_Saldos_20260917"     (19 saldos previos)
-- ════════════════════════════════════════════════════════════════════════════════════

insert into public."Movimientos_Stock" (ts, cod_art, deposito, delta, tipo, ref, legajo, ubicacion, empresa)
values
 (now(),'809E','terminado',   -7,'ajuste','ajuste de admin en base a conteo del 17.09 (gondola J14 = 14 cajas; J13 vacia)','admin','J14','LK'),
 (now(),'809E','terminado',   -6,'ajuste','ajuste de admin en base a conteo del 17.09 (gondola M14 = 104 cajas; M13 y M15 vacias. M16 tiene 809, otro codigo)','admin','M14','CH'),
 (now(),'809E','racks',      336,'ajuste','ajuste de admin en base a conteo del 17.09 (AD05 = 28 MC = 336 cajas, y son de Loekemeyer)','admin','AD05','LK'),
 (now(),'809E','racks',     -336,'ajuste','ajuste de admin en base a conteo del 17.09 (no queda 809E de Chef en racks: AD06 tiene 368E)','admin','AD05-AD06','CH');

update public."GV_Lugar"
   set empresa = 'LK', updated_at = now(),
       notas = coalesce(notas||' · ','')||'empresa corregida a LK por conteo del 17.09 (AD05 tiene 809E de Loekemeyer)'
 where sector = 'AD05';

update public."Racks_Planimetria" set emp = 'LK'
 where sector = 'AD05' and upper(btrim(cod_art)) = '809E';

delete from public."Racks_Planimetria"
 where upper(btrim(cod_art)) = '809E' and sector in ('AD06','AE11');

insert into public."GV_Lugar_Item" (sector, cod, clase, activo, notas)
values ('AD05','809E','articulo', true,'alta por conteo del 17.09 (28 MC)')
on conflict do nothing;

select public.refresh_stocks_carga_rapida();

-- ── Chequeo ─────────────────────────────────────────────────────────────────────────
-- select cod_art, empresa, deposito, sum(delta) from public."Movimientos_Stock"
--  where upper(btrim(cod_art)) in ('809E','368E') group by 1,2,3 having sum(delta) <> 0;

-- ── Rollback ────────────────────────────────────────────────────────────────────────
-- delete from public."Movimientos_Stock"
--  where ref like 'ajuste de admin en base a conteo del 17.09%' and upper(btrim(cod_art))='809E';
-- update public."GV_Lugar" l set empresa = b.empresa, notas = b.notas
--   from zz_backups."GV_Backup_Conteo809E_Lugar_20260917" b where b.sector = l.sector;
-- delete from public."Racks_Planimetria" where upper(btrim(cod_art)) in ('809E','368E');
-- insert into public."Racks_Planimetria"
--   select * from zz_backups."GV_Backup_Conteo809E_Racks_20260917";
-- delete from public."GV_Lugar_Item" where (sector,cod) = ('AD05','809E');
-- select public.refresh_stocks_carga_rapida();
