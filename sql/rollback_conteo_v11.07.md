# Rollback v11.07 — Conteo con autocompletado + formato dinámico

## Qué cambió (index.html)
- `stkBodyConteo()`: tabla con datalist autocompletado, formato dinámico merc/insumo
- `cntSelectCod()`, `_cntIsInsumo()`, `_cntBuildDatalist()`: funciones nuevas
- `cntAddRow()`, `cntDelRow()`: rows con campos isInsumo/cantidad/unidad
- `cntGuardar()`: envía deposito=insumos + cantidad/unidad para insumos
- `cntExportCsv()`: CSV con columnas tipo/cantidad/unidad
- Comparación (`showComp`): usa cantidad correcta según tipo
- `stkBodyConteosRealizados()`: fix escaping data-attributes (de safeId)
- APP_VERSION: v11.06 → v11.07
- SW_VERSION: v11.06-vir → v11.07-vir

## Cómo rollbackear
```bash
git log --oneline -5   # buscar el commit anterior a v11.07
git revert <commit-hash-v11.07>
git push origin main
```

O restaurar manual: el commit previo en main es el último con v11.06.

## Datos de Supabase (no se tocan con rollback de código)
- `E. Madre LK`: INSERT 599E / Pelador Madera Multifuncion
- `Capacidad_Sector`: INSERT J44 / 599E / 40 cajas / lk

Para revertir datos:
```sql
DELETE FROM "E. Madre LK" WHERE "Cod" = '599E';
DELETE FROM "Capacidad_Sector" WHERE cod = '599E' AND sector = 'J44';
```

## Tabla Conteo_Stock — sin cambios de schema
Los campos `deposito`, `cantidad`, `unidad` ya existían. No se agregaron columnas.
Conteos guardados con deposito='insumos' seguirán en la tabla (no hacen daño al rollbackear).
