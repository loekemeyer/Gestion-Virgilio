# Runbook — mandar la planimetría + la empresa a `main`

> **Estado: NO EJECUTAR.** Este documento es el detalle de qué se va a hacer cuando Luis
> diga que mandemos esto a `main`. Nada de acá se corre antes de esa señal.
>
> **Reglas que fijó Luis (2026-09-11):**
> 1. **Nada se borra.** Toda tabla, vista, función o fila que quede obsoleta **se conserva**,
>    lista para rollback. Se retiran en otro momento, no acá.
> 2. **Tiene que ser quirúrgico:** entran todos los cambios juntos y tiene que funcionar.
> 3. **El editor se rehace** y entra en este paquete.

---

## 0. Qué es esto en una línea

Que la empresa (LK / CH) acompañe al código **desde que la mercadería entra hasta que sale
facturada**, con el código **pelado** (`438E`) y la empresa **en su columna** — en vez de
metida en el nombre (`"438E LK"`), que es de donde salían los errores tipo mandar al
pickeador de Loeke a la góndola de Chef.

## 1. Lo que ya está aplicado en la base (no se toca en el merge)

Esto se hizo durante la sesión del 11/09 y **ya está en producción**, sin estar conectado a
nada:

| objeto | qué es | filas |
|:--|:--|--:|
| `GV_Lugar` | un lugar físico del depósito | 872 |
| `GV_Lugar_Item` | qué hay en cada lugar, PK `(sector, cod, clase)` | 782 |
| `GV_Lugar_Pendiente` | los insumos, estacionados | 148 |
| `gv_ocupacion_lugar` | vista derivada de `Movimientos_Stock` | — |
| `gv_norm_sector(text)` | `J1` → `J01` | — |
| backfill de `a_guardar` | 1.118 LK + 283 CH, **0 en Mixto** | 1.389 |

Backups vivos: `GV_Backup_aguardar_empresa_20260911`, `GV_Backup_lugar_empresa_20260911`,
`GV_Backup_lugar_item_20260911`.

## 2. Lo que entra con el merge

### 2.a Front (`index.html` + `sw.js`, v15.43 → v15.75)

| versión | qué |
|:--|:--|
| v15.41 | el PKC dice de qué **depósito** salió cada caja · el picking va **primero al excedente** |
| v15.43 | la empresa viaja de la **recepción** al **guardado** (MG) · el lugar del excedente se valida contra `GV_Lugar` (no se puede tipear cualquier cosa) |
| v15.71 | 4 lugares del front dejan de **pisar** el saldo de `vista_saldos_stock` *(ya está en `main`)* |
| v15.73 | el **picking** deja de tirar la empresa · el sector sale de `gv_lugar_articulo` |
| v15.74 | aviso `MIX` cuando una tanda mezcla empresas para el mismo código |
| v15.75 | (sólo doc y SQL) |

### 2.b SQL — **en este orden, y recién DESPUÉS del merge del front**

| # | archivo | qué hace | ¿toca algo compartido? |
|--:|:--|:--|:--|
| 1 | `sql/gv_empresa_recepcion_mg.sql` | el trigger de recepción deja de pisar la empresa del remito · vista `gv_saldos_stock_emp` | **sí** — trigger de `Movimientos_Stock` |
| 2 | `sql/gv_empresa_picking.sql` §1 | vista `gv_lugar_articulo` (sector por código+empresa) | no, es nueva |
| 3 | `sql/gv_empresa_picking.sql` §2 | las 2 funciones de reconciliación leen el 6.º campo del PKC | **sí** — `reconciliar_pipeline_stock_etapa1` y `..._articulo_rt` |
| 4 | `sql/gv_empresa_picking.sql` §3 | **backfill**: reclasifica el saldo que hoy vive en `Mixto` | **sí** — escribe en `Movimientos_Stock` |
| 5 | `sql/gv_lugar_editor.sql` | permisos de escritura del editor nuevo (policy `ALL` para `authenticated`) | no, son tablas nuevas |
| 6 | *(un SQL)* | **prender el corte** `pkc_empresa_desde` | switch |

⚠ **El orden 4 → 5 no es negociable.** Sin el backfill, el picking descuenta de un balde `LK`
casi vacío (la góndola tiene **26.484 cajas en `Mixto` contra 326 con empresa**) y lo deja en
negativo al primer pedido, con el cron 13 mandando Telegram por cada uno.

⚠ **El corte es por FECHA, no un booleano.** Las filas viejas dicen `Mixto` y el índice único
lleva `coalesce(empresa,'')`: una fila nueva con `LK` **no choca** con la vieja, quedarían las
dos y el stock se descontaría **dos veces**. Con el corte, cada tanda vive entera de un lado.

### 2.c El editor — **se rehace y entra acá**

Hoy hay **dos** editores separados que escriben a **dos** tablas que ahora son una:

| hoy | escribe a | se funde en |
|:--|:--|:--|
| Editor de Planimetría (`planimUpsert`, `planimDeleteRow`) | `Planimetria` (clave `cod`) | **un solo editor** sobre `GV_Lugar_Item` |
| Capacidad por sector (`dpSaveCap`, `stkCapImport`) | `Capacidad_Sector` | ídem |

Cambia el modelo, no sólo el endpoint:

| `Planimetria` | `GV_Lugar_Item` |
|:--|:--|
| clave `cod` → **un código, un lugar** | clave `(sector, cod, clase)` → **un código en varios lugares** (el 437E está en F09–F12) |
| `orden` por código | `orden` del **lugar** (`GV_Lugar.orden`) |
| no distingue artículo de insumo | `clase` obliga a elegir |
| no tiene empresa | la da el lugar, no se tipea |
| capacidad en otra tabla | `cajas_max` acá |

**Pantalla nueva:** elegir lugar → ver qué tiene → agregar/sacar códigos con su `cajas_max`.
Y al revés: buscar un código → ver todos sus lugares.

⚠ `stkCapImport` hace `DELETE ?id=gt.0` y recarga de un Excel. **Ese patrón no se replica**:
sobre `GV_Lugar_Item` sería borrar la planimetría entera. El importador nuevo va por `upsert`
por `(sector, cod, clase)`.

**Los editores viejos quedan andando** (regla 1). Escriben a tablas que ya nadie lee, pero un
supervisor sin editor un lunes a la mañana es peor.

### 2.d Enrutamiento de lecturas

`window.GONDOLA` (`{cod: [sector, orden]}`, **25 usos**) mantiene la forma y cambia de dónde
se llena: `gv_lugar_articulo` en vez de `Planimetria`. **Los 25 consumidores no se tocan.**
Se regenera además `planimetria.js` (el baseline offline, hoy de un Excel del 28/08).

---

## 3. Secuencia de ejecución

| paso | qué | quién | verificación |
|--:|:--|:--|:--|
| 1 | `git fetch` + traer `main` a la rama | Claude | 5 conflictos triviales esperados (versión + secciones al final) |
| 2 | Re-bumpear versión por encima de la de `main` | Claude | `APP_VERSION` == `SW_VERSION` |
| 3 | Asignar las letras a `§3.«LUGAR-EMP»`, `§3.«PKC-DEP»`, `§3.«PICK-EMP»` | Claude | `grep -c '«'` → 0 |
| 4 | **Suite completa** | Claude | 119+ bloques, 0 fallos |
| 5 | ⚠ **`index.html` y `sw.js` NO vacíos** | Claude | `wc -c` > 3.000.000 y > 8.000 |
| 6 | Merge a `main` + push | Claude | Pages publica en 30 s–2 min |
| 7 | Confirmar en el celular que la app abre y el badge dice la versión nueva | **Luis** | — |
| 8 | SQL 1 (trigger + `gv_saldos_stock_emp`) | Claude | ver abajo |
| 9 | SQL 2 y 3 (vista + reconciliación) | Claude | ver abajo |
| 10 | SQL 4 (**backfill**) | Claude | ver abajo |
| 11 | SQL 5 (**prender el corte**) | Claude | ver abajo |
| 12 | Mirar un picking real de punta a punta | **Luis** | — |

### Verificaciones, una por paso

```sql
-- (8) la recepción ya no pisa la empresa
select empresa, count(*) from "Movimientos_Stock"
 where deposito='a_guardar' and ts >= now() - interval '1 hour' group by 1;
select * from gv_saldos_stock_emp limit 5;

-- (9) el sector sale por código+empresa
select * from gv_lugar_articulo where cod='809E';   -- → J13/J14 LK · M13/M14/M15 CH

-- (10) el backfill: 0 en Mixto en los cuatro depósitos, y el total NO se movió
select deposito, round(sum(delta)) from "Movimientos_Stock"
 where coalesce(empresa,'')='Mixto'
   and deposito in ('terminado','excedente','separar_pedidos','a_facturar')
 group by 1;                                        -- → 0 en las cuatro
select count(*) from vista_saldos_stock
 where terminado<0 or excedente<0 or a_guardar<0 or racks<0
    or separar_pedidos<0 or a_facturar<0;           -- → 0

-- (11) el picking empieza a escribir la empresa
select empresa, count(*) from "Movimientos_Stock"
 where tipo='picking' and ts >= now() - interval '1 day' group by 1;
```

---

## 4. Rollback — cada paso se deshace solo

| paso | cómo se deshace | ¿pierde algo? |
|--:|:--|:--|
| 11 | `delete from "Stock_Config" where clave='pkc_empresa_desde';` | no — vuelve todo a `Mixto` |
| 10 | `delete from "Movimientos_Stock" where ref='gv_empresa_backfill';` | no — es una transferencia que neta cero |
| 9 | correr `sql/backups/reconciliar_pkc_pre_v1541_20260911.sql` | no |
| 8 | volver el trigger a la definición de la v14.75 (está comentada arriba del archivo) | no |
| 6 | `git revert` del merge y push | no |

**El paso 11 es el kill-switch.** Con una línea vuelve todo al comportamiento de hoy sin tocar
código ni datos. Si algo se ve raro el primer día, se apaga eso y se mira con calma.

## 5. Lo que NO entra en este paquete

- **Sacar los códigos `"438E LK"`** → `docs/PLAN-SACAR-SUFIJO-EMPRESA.md`, Parte 1. Va después,
  con la empresa ya rodando unos días.
- **Retirar las tablas viejas** (`Planimetria`, `Capacidad_Sector`, `Racks_Planimetria`,
  `Ubicaciones_Articulos`, `Stock_Ubicaciones`) → quedan, por la regla 1.
- **Las 6 filas de sufijo de `Equivalencias_Codigos`** → quedan. Las 2 que son equivalencias
  reales (`727`→`727E`, `727EN`→`727E`) se quedan para siempre.
- **Insumos** → 148 filas en `GV_Lugar_Pendiente` + 51 racks `IN`. Módulo aparte.
- **El cron 13** → no se toca. Con la empresa viajando pasa a ser más útil, no menos.

## 6. Lo que falta construir antes de poder ejecutar esto

- [x] **El editor fundido** — hecho en la **v15.76**. Ver abajo.
- [ ] **Enrutar `window.GONDOLA`** a `gv_lugar_articulo` (§2.d).
- [ ] **Regenerar `planimetria.js`** desde las tablas nuevas.
- [x] Test del editor (`tests/lugar-editor.cjs`, 18 chequeos, ya en `tests/run.sh`).

### El editor nuevo (v15.76) — qué quedó

Pantalla **📍 Lugares del depósito** en el panel supervisor, al lado de la vieja (que
**queda**, regla 1). Dos pestañas:

| pestaña | pregunta que contesta |
|:--|:--|
| **Por lugar** | *"¿qué hay en F13?"* — lista los lugares con sus códigos como chips, la empresa y el orden de recorrido. Buscar por **código** filtra lugares: tipear `438E` trae los 4 donde está |
| **Por código** | *"¿dónde está el 438E?"* — todos sus lugares, ordenados por el recorrido. **Esto la tabla vieja no lo podía contestar**: su clave era `cod`, un código vivía en un solo lugar |

Lo que cambia respecto del viejo, y que el test protege:

- **La empresa NO se tipea.** El POST manda `sector` + `cod` + `clase` y nada más: la
  empresa la da el lugar. (`out.NOmandaEmpresa`)
- **`clase` separa artículo de insumo** en el mismo lugar y con el mismo código — son
  cosas distintas y por eso está en la PK. Los chips de insumo van en ámbar.
- **Borrar saca el código DE ESE LUGAR**, no del depósito. El confirm dice si le quedan
  otros lugares o si es el único, porque en el editor viejo borrar lo sacaba de todos
  lados (sólo podía estar en uno).
- **`cajas_max` vive acá** — es lo que hace innecesaria a `Capacidad_Sector`.
- Sin los permisos de escritura el editor **lo dice y nombra el SQL que falta**
  (`sql/gv_lugar_editor.sql`) en vez de fallar mudo.

⚠ **Falta un SQL más en la secuencia:** `sql/gv_lugar_editor.sql` (policy `ALL` para
`authenticated` sobre `GV_Lugar` y `GV_Lugar_Item`). Las tablas nacieron con RLS y **sólo
policy de SELECT**, así que sin eso el editor lee pero no guarda. Va con los otros, mismo
patrón que `planim_write` / `cap_write`.

⚠ **`stkCapImport` no se replicó** a propósito: hace `DELETE ?id=gt.0` y recarga de un
Excel. Sobre `GV_Lugar_Item` eso borra la planimetría entera. Si se quiere importador, va
por `upsert` por `(sector, cod, clase)`.
