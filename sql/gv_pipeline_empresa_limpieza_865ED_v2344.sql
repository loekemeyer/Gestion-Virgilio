-- v23.44 (Luis 28/09, "sí"): filas de picking de más del 865ED puestas en 0 (update, no delete: el saldo
-- se recalcula en update). Backup: zz_backups."GV_Backup_865ED_pipeline_20260928".
update public."Movimientos_Stock" set delta=0 where cod_art='865ED' and tipo='picking'
   and ((upper(btrim(ref))='D58A' and empresa='CH') or (upper(btrim(ref))='E41A' and empresa='LK' and creado>='2026-09-25'));
