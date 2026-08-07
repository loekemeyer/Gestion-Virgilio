# ⚠️ PROTOCOLO CRÍTICO: Cambios en Supabase

**REGLA DE ORO: NUNCA modificar datos en Supabase sin backup previo**

## Antes de CUALQUIER cambio en datos (INSERT, UPDATE, DELETE, TRUNCATE):

1. **CREAR BACKUP INMEDIATO**
   ```sql
   -- Guardar en /tmp/backup_TABLA_YYYYMMDD_HHMMSS.sql
   SELECT * FROM "TABLA" ORDER BY id;
   ```

2. **GUARDAR EL BACKUP** en archivo SQL listo para restaurar:
   ```sql
   BEGIN;
   INSERT INTO "TABLA" (...) VALUES (...);
   COMMIT;
   ```

3. **SOLO DESPUÉS** ejecutar los cambios

4. **SI ALGO FALLA**: restaurar desde el backup inmediatamente

## Cambios críticos recientes (APRENDIZAJES):

- **Capacidad_Sector**: Fue truncada sin backup el 2026-08-07. Los datos originales se perdieron.
  - Lección: **NUNCA TRUNCATE sin backup**

## Próximas sesiones:

- Implementar backup automático antes de cambios en tablas críticas
- Mantener registro de backups en `/tmp/BACKUPS/`
- Verificar que el backup se restaure correctamente ANTES de hacer cambios
