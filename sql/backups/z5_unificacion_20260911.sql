-- 2026-09-11 (v15.60) — Unificación GBA Oeste del 15/09 con el Norte del 16/09 + Veronesi fuera de D68G.
-- Decisión de Thomas ("1 sí, 2 sí"). Las filas ORIGINALES están en public."GV_Backup_Z5_20260911"
-- (jsonb, origen = 'override' | 'web_prog'). Este archivo es el ROLLBACK exacto.
--
-- Lo que se cambió:
--   PPP_Web_Programacion  lk/1349/1 (LK 0018), lk/1358/1 (LK 0028), lk/1362/1 (LK 0032):
--                         tanda D68G → D69F, fecha_entrega 2026-09-15 → 2026-09-16
--   GV_PPP_Prog_Override  98608/98609/98610 (G-Seller, Morón): tanda null(D68E) → D69G, fecha 15 → 16
--                         98651 (Extralimp, Luján): tanda E11A (igual), fecha 15 → 16
--                         98694 (Veronesi, La Boca): tanda null(D68G) → D68J, fecha 15 (igual)
--
-- Rollback (restaura fila por fila desde el backup):
update public."PPP_Web_Programacion" w
   set tanda = b.fila->>'tanda', fecha_entrega = (b.fila->>'fecha_entrega')::date, actualizado_at = now()
  from public."GV_Backup_Z5_20260911" b
 where b.origen = 'web_prog' and w.empresa = b.fila->>'empresa'
   and w.order_id = (b.fila->>'order_id')::bigint and w.np_idx = (b.fila->>'np_idx')::int;
update public."GV_PPP_Prog_Override" o
   set tanda = b.fila->>'tanda', fecha_entrega = (b.fila->>'fecha_entrega')::date, nota = b.fila->>'nota'
  from public."GV_Backup_Z5_20260911" b
 where b.origen = 'override' and o.np = b.fila->>'np';
-- Geocodificación (misma sesión): 10 filas falsas de GV_Geo_Cliente borradas, backup en
-- public."GV_Backup_Geo_20260911" (jsonb). Para restaurarlas (no recomendado: son puntos en CABA):
-- insert into public."GV_Geo_Cliente" select (jsonb_populate_record(null::public."GV_Geo_Cliente", fila)).* from public."GV_Backup_Geo_20260911";
-- Las 11 correcciones nuevas en GV_Geo_Correccion llevan nota 'v15.58 11/09 Thomas…' (delete where nota like 'v15.58%').
