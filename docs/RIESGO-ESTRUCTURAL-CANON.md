# Riesgo estructural: REVOKE anon + trigger anon-writable

Contexto: incidente del 2026-08-28 al 31 en `Entregas_Virgilio` (ver v12.18
en `GUIA-PROYECTO.md`). Este documento propone controles para que el patrón
no vuelva a colarse.

## El patrón peligroso

Cualquier función `f()` que cumpla las tres:

1. Está en un schema que PostgREST expone (típicamente `public`).
2. Se le `REVOKE EXECUTE FROM public/anon/authenticated`.
3. Se la llama desde un trigger `BEFORE INSERT/UPDATE` sobre una tabla en la
   que `anon` (o `authenticated`) tiene policy INSERT/UPDATE.

...rompe silenciosamente todas las escrituras de ese rol con `42501 permission
denied`. El front puede tragarse el error si su `.catch` no distingue 4xx
transientes (permisos/RLS/JWT expirado) de 4xx de datos malformados.

## Cuatro capas de defensa

### 1. Test de smoke automático "anon puede escribir"

Nuevo test en `tests/`: por cada tabla con policy `INSERT` para `anon`,
intenta un INSERT dummy vía PostgREST usando la anon key, verifica 2xx y
borra la fila. Corre en cada `bash tests/run.sh` — si un deploy vuelve
a introducir el bug (fija `REVOKE` sobre una función de trigger),
el test falla antes de que el operario pierda armados.

Boceto (`tests/anon-writes.cjs`):

```js
const TABLES = [
  { t: 'Entregas_Virgilio', row: { fecha_salida: '2026-01-01', cod_cliente: 'T', np: 'T', cod_art: 'T', cajas_pedidas: 1, cajas_entregadas: 1, cajas_falto: 0, tanda: 'T' } },
  { t: 'Movimientos_Stock',  row: { /* ... */ } },
  { t: 'Faltantes_Notas',    row: { /* ... */ } },
  // ...
];
for (const { t, row } of TABLES) {
  const r = await fetch(SUPABASE_URL + '/rest/v1/' + t, { method: 'POST', headers: { apikey: ANON, Authorization: 'Bearer '+ANON, 'Content-Type': 'application/json', Prefer: 'return=representation' }, body: JSON.stringify(row) });
  assert(r.ok, `INSERT anon en ${t} falló: HTTP ${r.status}`);
  const [ins] = await r.json();
  await fetch(SUPABASE_URL + `/rest/v1/${t}?id=eq.${ins.id}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer '+SERVICE } });
}
```

Requiere un secret `SERVICE_ROLE_KEY` para la limpieza (solo en CI, no en
el bundle del cliente).

### 2. Runbook de migraciones que hacen REVOKE

Nuevo checklist en `docs/CHECKLIST-MIGRACIONES.md` (o al pie de
`PROTOCOLO-CAMBIOS-SUPABASE.md`) — obligatorio antes de aplicar cualquier
migración que contenga `REVOKE ... FROM anon` (o public/authenticated):

- [ ] ¿La función aparece en un trigger? `SELECT tgrelid::regclass, tgname
      FROM pg_trigger WHERE pg_get_triggerdef(oid) ILIKE '%<fn>%'`.
- [ ] ¿La tabla del trigger tiene policy INSERT/UPDATE para `anon`?
      `SELECT * FROM pg_policies WHERE tablename='<tabla>' AND 'anon'=ANY(roles) AND cmd IN ('INSERT','UPDATE')`.
- [ ] Si ambas dan sí: **la trigger fn TIENE que ser `SECURITY DEFINER`
      SET search_path = public** (correr como owner, no como invocador),
      y a la trigger fn se le hace REVOKE EXECUTE FROM public/anon/auth
      para cerrar la superficie RPC.

### 3. Monitor de escrituras estancadas (Telegram)

Cron cada 5 min que verifique que las tablas críticas tienen filas nuevas
recientes en horario laboral. Si `Entregas_Virgilio` no recibe INSERT
en 30 min entre 9-19 hs de lunes a viernes → alerta Telegram.

Tablas a cubrir: `Entregas_Virgilio`, `Movimientos_Stock`,
`Registros_Produccion_Virgilio` (esta última es el canario más rápido
porque recibe eventos cada minuto).

Ejemplo SQL para el cron:

```sql
DO $$
DECLARE
  ult_entregas timestamptz;
  ult_reg      timestamptz;
BEGIN
  IF EXTRACT(dow FROM now() AT TIME ZONE 'America/Argentina/Buenos_Aires') NOT BETWEEN 1 AND 5 THEN RETURN; END IF;
  IF EXTRACT(hour FROM now() AT TIME ZONE 'America/Argentina/Buenos_Aires') NOT BETWEEN 9 AND 19 THEN RETURN; END IF;

  SELECT max(creado) INTO ult_entregas FROM public."Entregas_Virgilio";
  SELECT max(created_at) INTO ult_reg   FROM public."Registros_Produccion_Virgilio";

  IF ult_reg > now() - interval '10 min' AND ult_entregas < now() - interval '30 min' THEN
    -- Registros vivo pero Entregas frizada → hay algo escribiendo eventos pero
    -- Entregas_Virgilio no recibe. Es la firma exacta del bug 42501 del 28/8.
    PERFORM telegram_enqueue('⚠ Entregas_Virgilio sin INSERT hace 30 min mientras Registros sigue vivo — chequear trigger canon');
  END IF;
END $$;
```

Registrar como job cron `watchdog-entregas-frizadas`, `*/5 9-19 * * 1-5`.

### 4. Regla de código en `_compSaveEntregas` y afines

Ya aplicada en v12.18 (`_compSaveEntregas` encola CUALQUIER no-2xx) y
v12.19 (`stockMove` distingue transient vs datos malformados).

Complemento pendiente: **grep de pre-commit** que caza patrones peligrosos:

```sh
# Falla si algún .catch sobre un fetch a SUPABASE_ traga silencioso
git diff --cached | grep -E '\.catch\(function \(\) \{\}\)' | \
  grep -B2 'SUPABASE' && \
  { echo 'ERROR: catch silencioso sobre write a Supabase'; exit 1; }
```

Se agrega como hook `.git/hooks/pre-commit` o se llama desde `tests/run.sh`.

## Prioridad

1. **Runbook** (5 min, doc pura) — hacé YA, evita el próximo incidente.
2. **Monitor Telegram** (30 min de SQL + registrar cron) — detecta el bug
   al toque, no en 3 días.
3. **Test de smoke anon-writes** (2 horas, requiere secret en CI y elegir
   qué tablas cubrir) — el más completo, el más caro.
4. **Grep pre-commit** (10 min) — barato, útil sobre todo si se vuelve a
   escribir un catch silencioso.
