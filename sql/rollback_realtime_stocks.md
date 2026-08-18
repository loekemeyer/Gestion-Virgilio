# Rollback: Realtime en stocks_carga_rapida (v11.08)

## Qué se hizo

1. **Supabase**: `ALTER PUBLICATION supabase_realtime ADD TABLE public.stocks_carga_rapida;`
2. **Supabase**: `ALTER TABLE public.stocks_carga_rapida REPLICA IDENTITY FULL;`
3. **index.html**: Reescritura de `stkSubscribeRealtime()` — de API v1 muerta (`SUPABASE_CLIENT`, nunca definido) a API v2 funcional (`sb.channel("stk-rt")` escuchando `postgres_changes` UPDATE en `stocks_carga_rapida`).
4. **index.html**: `closeStockAdmin()` usa `stkUnsubscribeRealtime()` (llama `sb.removeChannel()`).

## Rollback Supabase

```sql
-- Quitar de realtime
ALTER PUBLICATION supabase_realtime DROP TABLE public.stocks_carga_rapida;

-- Volver replica identity a default
ALTER TABLE public.stocks_carga_rapida REPLICA IDENTITY DEFAULT;
```

## Rollback front-end

Revertir el commit que contiene este cambio en `index.html` (buscar `sb.channel("stk-rt")`).
La función anterior era código muerto (usaba `SUPABASE_CLIENT` que no existía), así que
revertirla solo vuelve a deshabilitar el realtime — no rompe nada.

## Correcciones de datos hechas en la misma sesión

| código | depósito | acción | motivo |
|--------|----------|--------|--------|
| 234 | terminado | INSERT delta +1 | Llevar saldo a 0 (ajuste manual) |
| 360 | terminado | UPDATE directo en stocks_carga_rapida | Trigger no actualizó (glitch transitorio) |
| 809E | terminado | INSERT delta +1, +1 | Revertir 2 ajustes fantasma (sin empresa) |
| 809E LK | terminado | INSERT delta -1 | Redirigir ajuste correcto |
| 809E CH | terminado | INSERT delta -1 | Redirigir ajuste correcto |
