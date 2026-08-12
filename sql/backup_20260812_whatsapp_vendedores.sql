-- BACKUP 2026-08-12 — antes de cargar los 16 vendedores en whatsapp_vendedores (había solo vend 6, nombre null)
UPDATE whatsapp_vendedores SET nombre=NULL WHERE vend='6';
DELETE FROM whatsapp_vendedores WHERE vend IN ('1','2','3','4','5','7','8','9','10','11','12','13','14','15','16');
