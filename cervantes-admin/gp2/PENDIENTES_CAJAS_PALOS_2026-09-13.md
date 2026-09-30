# GP2 — Palos de amasar, PEST1, 941E–948E, faltantes 08-09, preguntas al dueño (2026-09-13)

Agente de SOLO LECTURA. Nada de lo de abajo está aplicado. Todo verificado con SELECT contra
`hrxfctzncixxqmpfhskv` schema `GP2` el 2026-09-13 (191 artículos, 798 componentes, 862 rutas,
3.286 pasos, 774 líneas de receta al momento del chequeo; los máximos de id de abajo pueden correrse
si el otro agente inserta antes: el SQL los calcula en runtime y **verifica los ids existentes por
código+sector**).

---

## 1. Palos de amasar 231 / 232 / 233 — ✅✅ EJECUTADO el 2026-09-13 ("dale" de Thomas)

> **Aplicado y verificado.** El bloque `DO` de §1.3 corrió entero, sin excepción, y dio
> **exactamente** los ids que predecía: `BANDITA` = **916**, recetas **917–922**, rutas
> **972–977**, pasos **3726–3743**.
>
> Backup previo: `zz_backups."GV_Backup_GP2_articulo_palos_20260913"` (3 filas de
> `GP2.articulo`, por la PK `id`; guardaba `componente_caja_id=NULL`, `articulos_por_caja=24`).
>
> Verificación de §1.4, toda en verde:
> - 231/232/233/234 → los **cuatro** con caja `604` (A9B, Caja N°15) y **12** uni x caja.
> - `BANDITA` 916, sector 10, ubicación 10, cantidad 0, **máximo NULL** (los tres palos no
>   están en `est_madre`, así que el máximo queda vacío hasta que se cargue la demanda).
> - Recetas: 3 líneas por palo (GRJ2x ×1 · A9B ×0,08333 · BANDITA ×1). El 234 sigue con 2.
> - Rutas: 3 por palo, 9 pasos cada uno, **todas Fábrica**.
> - Invariantes de `db/verificar.sql`: **35 reglas, las 35 en 0**, igual que antes del cambio.
>
> ⛔ **Lo OPCIONAL del final de §1.3 NO se aplicó**: desactivar 231/232/233 en
> `articulo_prov_at` (ids 92/94/95) sigue siendo una **pregunta al dueño**, no entraba en el
> "dale". Mientras siga activo, una entrega de Prov AT de un 231 descontaría desde la
> ubicación 54 (vacía) y quedaría en negativo.

### 1.0 El SQL que se ejecutó (queda como registro)

### 1.1 Estado verificado hoy

| Art | id art | comp. terminado (sector 12) | insumo garage | id | proveedor | ruta hoy | caja hoy | uni x caja hoy |
|---|--:|--:|---|--:|---|---|---|--:|
| 231 Palo de Amasar 30cm | 154 | 739 | GRJ22 | 736 | Tierra Nativa SA | 801: insumo→Fábrica(3)→virgilio | NULL | 24 |
| 232 Palo de Amasar 40cm | 155 | 740 | GRJ23 | 737 | Tierra Nativa SA | 802: ídem | NULL | 24 |
| 233 Palo de Amasar 50cm | 156 | 741 | GRJ24 | 738 | Tierra Nativa SA | 803: ídem | NULL | 24 |
| 234 Palo Frances 40cm (testigo) | 144 | 709 | GRJ17 | 708 | Tierra Nativa SA | 763 (GRJ17) + 773 (A9B, 1/12) | A9B id 604 (Caja N°15) | 12 |

- Recetas hoy: 231/232/233 = sólo su GRJ ×1 (ids 755/756/757). 234 = GRJ17 ×1 + A9B ×0,08333 (ids 718/728).
- `A9B` = Caja N°15, id **604**, Sector Caja (11), Corrugadora del Plata, precio $344,26 (lista 20-07-2026), inventario en Sector Caja (ubic 11) stock 0, máximo 1.056 (est_madre).
- **NO existe** ningún componente `BANDITA` (ni por código `%BAND%` ni por descripción "bandita"/"elast").
- Sector Cartón = sector **10**; su ubicación de stock = ubicación **10** ("Sector Cartón", tipo sector). Fábrica = tallerista **3** (ubicación 23).
- Planilla: hoja **Cajas** no tiene fila para 231/232/233 (sí para 234: fila 86, D=15, F=12). Hoja **Cartones** tampoco (sólo 234, fila 389). O sea la caja de los tres la decidió el dueño ("1 ponele la 15", "2 ponele 12 a los 4 items"), no la planilla.
- Códigos repetidos entre sectores: `A9B`, `GRJ22/23/24`, `BOLSA550` son únicos; igual todo el SQL filtra por `sector_id`.
- **Cómo se hizo el inventario del pincel el 13-09** (`PINCEL590` 910 / `CART590` 911 / `CART890` 912): filas `inventario` **124119–124121, insertadas a mano** (id por `inventario_id_seq`). No hay trigger en `componente` que cree inventario (el único es `trg_maximos_cajones_componente` → recalcula máximos, no crea filas). `inv_delta()` hace `insert … on conflict` pero recién con un movimiento. **Conclusión: hay que insertar la fila de inventario explícitamente.**
- Triggers que van a disparar: `trg_maximos_receta` (articulo_componente) y `trg_maximos_rutas` (ruta_paso) → `recalcular_maximos_insumos()` → `v_nivel_stock` (consumo = est_madre × receta). **231/232/233 NO están en `est_madre`** (sí 234 = 396 uni/mes) → el máximo de BANDITA quedará NULL y el de A9B no cambia hasta que el dueño cargue la demanda de los tres palos.

### 1.2 Convención de la casa para el componente nuevo (mirado en BOLSA550 / BOLSA760 / CART590)

| col | BOLSA550 (629) | BOLSA760 (721) | CART590 (911) | BANDITA propuesto |
|---|---|---|---|---|
| sector_id | 10 | 10 | 10 | **10** |
| unidad_medida (NOT NULL) | unidad | unidad | unidad | **unidad** |
| proveedor (FK proveedor_insumo.nombre) | Papelera Nueve de Julio | Papelera Nueve de Julio | Talleres Gráficos Pol | **NULL — no se sabe** (ver abajo) |
| estado_compra | NULL (= se compra) | NULL | NULL | **NULL** |
| marca | LOEKE | CHEF | LOEKE | **LOEKE** (los 3 palos son LOEKE) |
| carton_formato | Bolsa | Bolsa | Huevo | **NULL** (no es cartón; 'Bolsa' le aplicaría pedido mínimo 20.000 en la OC) |
| es_pliego / recibe_en_cajas / relev_solo_sueltas | false | false | false | false (default) |

Columnas NOT NULL de `componente`: `id` (**sin default, sin secuencia** → max+1), `codigo`, `sector_id`, `unidad_medida`, `es_pliego`, `recibe_en_cajas`, `relev_solo_sueltas`, `discontinuado` (defaults false). CHECKs: `estado_compra in (fabricacion, discontinuo, importado, compra) or null`; `marca in (LOEKE, CHEF) or null`.

**Proveedor de la bandita — no está en la base, y en la planilla hay tres candidatos, ninguno nombrado para palos** (`v_planilla_precio`):

| fila LP | proveedor | producto | precio | rubro |
|--:|---|---|--:|---|
| 389 | 2147 Grafica Pol | Bandita Ralladores | $8.250 (col C = "Falta Prov") | Envasado |
| 390 | 2147 Grafica Pol | Banditas 35 x 194 mm | $8.250 (col C = "Falta Prov") | Envasado |
| 514 | 4399 Lopez Jose Daniel | Super Bands Bolsa N°15 (Bandita Negra) | $1,08 la unidad, última compra 09-12-2025 | — |

Además la LP fila 408 (Pol) lista **"Etiqueta Palo de Amasar 40cm" $9.500** (col N = "NO") — no está en GP2 y el dueño no la nombró; sólo lo anoto.
→ `proveedor = NULL` en el SQL; **pregunta al dueño** en §5.

### 1.3 SQL (una transacción; aborta sola si algún id verificado no coincide)

```sql
begin;

do $$
declare
  v_art231 bigint := 154;  v_art232 bigint := 155;  v_art233 bigint := 156;
  v_t231   bigint := 739;  v_t232   bigint := 740;  v_t233   bigint := 741;   -- terminados (sector 12)
  v_a9b    bigint := 604;                                                     -- Caja N°15, sector 11
  v_fab    bigint := 3;                                                       -- tallerista Fábrica
  v_ubic_carton bigint := 10;                                                 -- ubicación "Sector Cartón"
  v_band   bigint;  v_ac bigint;  v_ruta bigint;  v_paso bigint;
  r record;
begin
  -- ids existentes: se verifican por código + sector, no se confía en la memoria
  if (select codigo from "GP2".componente where id=v_a9b and sector_id=11) <> 'A9B' then raise exception 'A9B no es 604'; end if;
  if (select codigo from "GP2".articulo where id=v_art231) <> '231' or (select codigo from "GP2".articulo where id=v_art232) <> '232'
     or (select codigo from "GP2".articulo where id=v_art233) <> '233' then raise exception 'ids de articulo cambiaron'; end if;
  if (select codigo from "GP2".componente where id=v_t231 and sector_id=12) <> '231' or (select codigo from "GP2".componente where id=v_t232 and sector_id=12) <> '232'
     or (select codigo from "GP2".componente where id=v_t233 and sector_id=12) <> '233' then raise exception 'ids de terminado cambiaron'; end if;
  if (select nombre from "GP2".tallerista where id=v_fab) <> 'Fábrica' then raise exception 'tallerista 3 no es Fábrica'; end if;
  if (select nombre from "GP2".ubicacion where id=v_ubic_carton and tipo='sector' and ref_id=10) <> 'Sector Cartón' then raise exception 'ubicación 10 no es Sector Cartón'; end if;
  if exists (select 1 from "GP2".componente where codigo='BANDITA') then raise exception 'BANDITA ya existe'; end if;

  -- (a) caja y uni x caja de los tres palos = como el 234
  update "GP2".articulo set componente_caja_id = v_a9b, articulos_por_caja = 12
   where id in (v_art231, v_art232, v_art233);

  -- (b) componente BANDITA (Sector Cartón). id sin secuencia → max+1
  select coalesce(max(id),0)+1 into v_band from "GP2".componente;
  insert into "GP2".componente (id, codigo, descripcion, sector_id, unidad_medida, proveedor, estado_compra, marca, carton_formato)
  values (v_band, 'BANDITA', 'Bandita Palo de Amasar (231/232/233)', 10, 'unidad', null, null, 'LOEKE', null);

  -- (c) inventario en Sector Cartón, stock 0 (igual que PINCEL/CART el 13-09: fila explícita)
  insert into "GP2".inventario (componente_id, ubicacion_id, cantidad, minimo) values (v_band, v_ubic_carton, 0, 0);

  -- (d) recetas: A9B x 1/12 y BANDITA x 1 para 231/232/233 (el 234 NO lleva bandita)
  select coalesce(max(id),0) into v_ac from "GP2".articulo_componente;
  insert into "GP2".articulo_componente (id, articulo_id, componente_id, cantidad) values
    (v_ac+1, v_art231, v_a9b,  1.0/12), (v_ac+2, v_art231, v_band, 1),
    (v_ac+3, v_art232, v_a9b,  1.0/12), (v_ac+4, v_art232, v_band, 1),
    (v_ac+5, v_art233, v_a9b,  1.0/12), (v_ac+6, v_art233, v_band, 1);

  -- (e) 6 rutas nuevas, calcadas de 773 (caja del 234) y 964-971 (pincel):
  --     paso 1 insumo comp→comp cantidad=receta · paso 2 tallerista Fábrica comp→terminado 1 · paso 3 virgilio terminado→null 1
  select coalesce(max(id),0) into v_ruta from "GP2".ruta;
  select coalesce(max(id),0) into v_paso from "GP2".ruta_paso;
  for r in
    select * from (values
      (v_art231, v_t231, v_a9b,  1.0/12), (v_art231, v_t231, v_band, 1.0),
      (v_art232, v_t232, v_a9b,  1.0/12), (v_art232, v_t232, v_band, 1.0),
      (v_art233, v_t233, v_a9b,  1.0/12), (v_art233, v_t233, v_band, 1.0)
    ) v(art, term, comp, cant)
  loop
    v_ruta := v_ruta + 1;
    insert into "GP2".ruta (id, nombre, articulo_id) values (v_ruta, null, r.art);
    insert into "GP2".ruta_paso (id, ruta_id, orden, tipo_paso, tallerista_id, comp_entrada_id, comp_salida_id, cantidad) values
      (v_paso+1, v_ruta, 1, 'insumo',     null,  r.comp, r.comp, r.cant),
      (v_paso+2, v_ruta, 2, 'tallerista', v_fab, r.comp, r.term, 1),
      (v_paso+3, v_ruta, 3, 'virgilio',   null,  r.term, null,   1);
    v_paso := v_paso + 3;
  end loop;

  perform "GP2".recalcular_maximos_insumos();
  raise notice 'BANDITA id % · recetas %..% · rutas hasta % · pasos hasta %', v_band, v_ac+1, v_ac+6, v_ruta, v_paso;
end $$;

-- mirar el NOTICE y las verificaciones de 1.4 ANTES del commit
-- commit;   -- o rollback;
```

Con la base de hoy eso da: BANDITA = **916**, recetas **917–922**, rutas **972–977**, pasos **3726–3743**.

**Opcional (no incluido, a confirmar):** `articulo_prov_at` tiene a **231/232/233 como artículos que Tierra Nativa entrega TERMINADOS** (ids 92/95/94, prov_at 13, activos, 0 entregas). Eso contradice lo que dijo el dueño (Tierra Nativa vende el palo, se guarda en garage, Log/Fabr pone la bandita y entrega en Virgilio). Si se deja activo, una entrega de Prov AT de un 231 consumiría GRJ22 + A9B + BANDITA desde la ubicación 54 (Prov. Art. Term. Tierra Nativa, hoy vacía) y quedaría en negativo. Para cerrar esa puerta:
`update "GP2".articulo_prov_at set activo=false where id in (92,94,95) and cod_art in ('231','232','233');` — **pregunta al dueño, no lo apliqué al SQL.**

### 1.4 Verificación (después del DO, antes del commit)

```sql
-- artículos: caja y uni x caja
select codigo, componente_caja_id, articulos_por_caja from "GP2".articulo where codigo in ('231','232','233','234') order by 1;
-- esperado: los 4 con 604 / 12

-- componente + inventario
select c.id, c.codigo, c.sector_id, c.proveedor, c.estado_compra, c.marca, i.ubicacion_id, i.cantidad, i.maximo
  from "GP2".componente c left join "GP2".inventario i on i.componente_id=c.id where c.codigo='BANDITA';
-- esperado: 1 fila, sector 10, ubic 10, cantidad 0, maximo NULL (231-233 sin est_madre)

-- recetas: 3 líneas por palo
select a.codigo, c.codigo comp, ac.cantidad from "GP2".articulo_componente ac
  join "GP2".articulo a on a.id=ac.articulo_id join "GP2".componente c on c.id=ac.componente_id
 where a.codigo in ('231','232','233') order by 1,2;
-- esperado: GRJ2x 1 · A9B 0.0833 · BANDITA 1 (9 filas). El 234 sigue con 2.

-- rutas: 3 por palo, 3 pasos cada una, todas Fábrica
select a.codigo, count(distinct r.id) rutas, count(p.id) pasos, bool_and(coalesce(p.tallerista_id,3)=3) solo_fabrica
  from "GP2".ruta r join "GP2".articulo a on a.id=r.articulo_id join "GP2".ruta_paso p on p.ruta_id=r.id
 where a.codigo in ('231','232','233') group by 1;
-- esperado: 3 / 9 / true por artículo

-- invariantes (db/verificar.sql): correr ENTERO; los que este cambio puede mover son:
--  AA (cantidad del paso insumo = receta)      → 0   (el paso 1 copia la cantidad de la receta)
--  AB (ruta que arranca en el aire)             → 0   (BANDITA: sector 10 es_insumo=true, estado_compra NULL ⇒ _es_comprable)
--  I  (código repetido en el mismo sector)      → 0
--  L  (rutas sin pasos), U (orden repetido)     → 0
--  W  (paso sin actor)                          → 0   (paso 2 lleva tallerista 3)
--  S  (receta con terminado), X (cantidad<=0)   → 0
--  AD/AE (terminado por la única puerta)        → 0   (no se tocan terminados)
--  B  (inventario = ledger)                     → 0   (fila nueva en 0, sin movimientos)
```

Hoy, antes del cambio: AA=0, AB=0, I=0, "receta sin inventario"=0 (medido).

**Efecto sobre costos** (⚠ ACTUALIZADO el 2026-09-13 a la noche): esta línea decía que el 234
costaba **$944,26** con caja. **Ese número era CORRECTO cuando se escribió** — la vista
`v_costo_componente` cobraba la caja **entera** por unidad en vez de su parte, y el 234 era
justamente el testigo que lo probaba. **Otra sesión lo arregló el mismo día** (migración
`la_caja_se_cobra_por_su_parte_no_entera`: `mat` pasa a cobrar `least(cantidad,1) * precio`),
así que **hoy el 234 da $628,69** = $600 del palo + **$28,69** de su parte de caja.

⚠ Y ojo con la trampa, que ya mordió: al medir DESPUÉS del arreglo, el 944,26 parece un error
de suma y da ganas de "corregirlo" diciendo que uno se equivocó. No fue un error de cuenta: era
el bug. Si se reescribe como error propio se borra la evidencia del problema. Lo que corresponde
es fechar el número, no negarlo.

Estado de hoy, verificado en la base: 231/232/233 quedan con `faltan_precios = 2` (GRJ sin
precio + BANDITA sin precio) y su total refleja sólo la caja, **$28,69** cada uno — que es
exactamente lo que este archivo predecía. Los 189 artículos con caja tienen su línea de receta
con `cantidad = 1/uni_x_caja`: ninguno cobra la caja entera. El precio de los palos 30/40/50 no está en la LP (sólo "Palo de Amasar Frances 40cm" $600 f888 y "Torneado Palo de Amasar 40cm" $1.245 f901, ambos Tierra Nativa).

---

## 2. PEST1

Verificado (`componente` id **768**, sector 6 Plástico, único con ese código):

| dato | valor |
|---|---|
| descripción | Insertos Mango de Madera |
| discontinuado / estado_compra | false / NULL (= se compra) → `_es_comprable` = true |
| proveedor | **NULL** |
| material_id | 742 = `2405` PP 2630 (Polipropileno) · mb_color N · kg_x_uni 0,0066 · pedido_minimo_uni 2.000 |
| inventario | Sector Plástico (ubic 6): **−372** uni (stock inicial no cargado), máximo 2.736 (est_madre) |
| en recetas | 941E, 942E, 943E, 944E, 945E, 946E, 948E (×1 cada uno) — **7 artículos, no sólo 941E y 946E** |
| rutas 941E / 946E | 834 / 839: insumo PEST1 → Fábrica (3) → virgilio ✔ |
| costo | `faltan_precios = 1` (sin `precio_proveedor`) |

**"Los otros 18 sin proveedor"** (componentes de sectores `es_insumo` con `proveedor IS NULL`, sin contar PEST1): son 18, **17 con `estado_compra='fabricacion'`** (C9, D14, D9, GRJ10, GRJ10A, GRJ7, I2, I3, PA13, PA18, PA4, PA5, PC15A, PC1A, PC1B, V18D, V4) **y 1 `discontinuo`** (`IF12` Fleje N°49, Sector Fleje, en ninguna receta). O sea PEST1 es el **único comprable sin proveedor**.

Cómo se escribe el proveedor: `proveedor_insumo` id 11, nombre exacto **`Pat Bet Plast`** (cod_prov 797, rubro Sector Plástico); 34 componentes ya lo tienen escrito así. La FK `componente_proveedor_fkey` exige ese texto exacto.

```sql
-- ESPERA CONFIRMACIÓN DEL DUEÑO (¿PEST1 lo inyecta Pat Bet Plast?)
update "GP2".componente set proveedor = 'Pat Bet Plast'
 where id = 768 and codigo = 'PEST1' and sector_id = 6 and proveedor is null;
-- verificación: select id, codigo, proveedor from "GP2".componente where id=768;
```

Dato al lado para la pregunta: en la LP, bloque **797 Pat Bet Plast**, hay **"Insertos Importados" $90,26** (f345, cod ISIS 4776, col C "Falta Prov") y "Inserto CH Cortos+ojal" $190,99 (f325). Ninguno dice "mango de madera". Si el dueño confirma proveedor, el precio es otra pregunta.

---

## 3. 941E–948E: qué dice la planilla sobre la caja (dato, sin decidir) — ⛔ RETIRADA el 2026-09-14

> **Se retira entera: la planilla estaba equivocada.** `[usuario 2026-09-14: "Todos los articulos
> que terminan con E: 941E … 948E. Llevan caja N°15, no 12" / "Si, caja 15 solo para los que te
> liste"]`. Los **siete** van en `A9B` **Caja N°15**, incluidos `941E` y `946E`, que esta sección
> daba por "importados sin caja" siguiendo a la planilla. Aplicado y verificado el 14-09: FK, receta
> y ruta de los siete, con ruta de caja nueva para 941E y 946E. Ver CONOCIMIENTO §4do.
> Lo único de esta sección que **sigue en pie**: los 12 uni x caja (contra los 24 de la hoja Cajas
> para 942E/945E) y que **947E no existe en ningún lado**. `590E` y `890E` quedan en Caja N°29.

| Art | GP2 caja (FK) | GP2 uni x caja | GP2 receta | Cajas hoja: fila / D (caja) / F (uni x caja) | Costos hoja: fabricante / cartón L / caja M | est_madre uni/mes (uxb) |
|---|---|--:|---|---|---|--:|
| 941E Espátula Lisa Inox | **NULL** | 12 | PEST1 | **sin fila** | Imp (Importados f104, USD 0,66) / — / — | 86 (12) |
| 942E Cuchara Inox | A2 N°12 | 12 | PEST1 | 459 / **12** / **24** | Imp (0,58×1,45×1500) / 48 / 15 (=360/24) | 132 (12) |
| 943E Cucharón Inox | A2 N°12 | 12 | PEST1 | 460 / 12 / 12 | Imp / 48 / 30 | 144 (12) |
| 944E Cuchara Fideos Inox | A2 N°12 | 12 | PEST1 | 461 / 12 / 12 | Imp / 48 / 30 | 74 (12) |
| 945E Espátula Calada Inox | A2 N°12 | 12 | PEST1 | 462 / **12** / **24** | Imp / 48 / 15 | 82 (12) |
| 946E Cuchara Calada Inox | **NULL** | 12 | PEST1 | **sin fila** | Imp (Importados f113, USD 0,66) / — / — | 58 (12) |
| 947E | **no existe en GP2** | — | — | **no existe en ninguna hoja de la planilla** | — | no está |
| 948E Espumadera Inox | A2 N°12 | 12 | PEST1 | 463 / 12 / 12 | Imp / 48 / 30 | 108 (12) |

Lectura del dato:
- **941E y 946E: la planilla los trata como importado terminado, sin cartón y sin caja del sistema** (Costos fila 124/129 sólo tiene E = Importados; no hay L ni M). GP2 coincide en que no tienen caja. También aparecen en la LP como compra a **Tierra Nativa (3917)** a USD 1,36 (f904/f905) — o sea vienen hechos, cosa que no cierra con la ruta GP2 "PEST1 → Fábrica" (todos los 94xE llevan sólo PEST1 en la receta, ningún cuerpo inox).
- **942E–945E y 948E: la planilla dice Caja N°12** (D=12, $360) ✔ igual que GP2 (A2 id 461), **y cartón** (L=48 via VLOOKUP a Cartones). En GP2 **la caja está sólo en el FK**: la receta no la lleva (1 línea, PEST1) y no hay ruta de caja ni de cartón — al revés de la regla "la caja va también al BOM a 1/uni_x_caja" (§1-undecies) y de lo hecho para 590E.
- **Uni x caja**: la hoja Cajas dice **24** para 942E y 945E (12 el resto); GP2 y est_madre dicen 12 para todos; los listados mayoristas en base (`uni_x_articulo_x_caja`) **no tienen ningún 94xE**. Regla del dueño: la uni x caja sale de los listados → falta ese dato.
- **947E no existe en ningún lado** (ni GP2, ni Cajas, ni Costos, ni Importados, ni LP). Reportado por si la lista que se tenía lo daba por vivo.

---

## 4. Informe de faltantes `GP2_FALTANTES_20260908.xlsx` — re-verificado contra la base

⚠ **El archivo NO está en el repo** (ni en `/home/user/Gestion-Productiva-2.0`, ni en la copia `Gestion-Virgilio/cervantes-admin/gp2`, ni en el scratchpad; `find` en todo `/home/user`). Lo único que queda es el resumen de §4bz (31/26 · 3/22 · 1/5 · 0/11) y las menciones sueltas de CONOCIMIENTO (§1-nonies, §1-decies, §1-octies, §4ba, §4bz). Lo de abajo es **la reconstrucción de esas menciones, cada ítem re-consultado hoy**. Donde no tengo la fila del archivo lo digo. Para ser exhaustivo fila por fila hace falta que el dueño vuelva a subir el xlsx (y esta vez guardarlo en el repo, trampa §4v).

### 4.1 Prov Servicio (11 filas · 0 resueltas el 12-09 · hoy sigue 0)

| ítem | hoy en base | ¿se resuelve con datos que hay? | pregunta al dueño (contexto) |
|---|---|---|---|
| **New Metal** (pavonado X5→Y1; LP: también temple $5.500) | no existe en `proveedor_servicio` (16 PS) | no | ¿New Metal sigue haciendo pavonado/temple para nosotros, o es histórico? Hoy el pavonado lo hace **Mabra** (X4→Y1 en 505/513/713) y el temple **FAAT**. |
| **Chormium** (pavonado X5→Y1) | no existe | no | ¿Se usa? Misma pregunta; si es alternativa a Mabra, ¿para qué piezas? |
| **Gaston Almafuerte** (pavonado X5→Y1) | no existe | no | Ídem. |
| **Valeria** (horqueta corta queso: `V15C` tornillo + `VCCQ` varilla) | no existe; `V15C` y `VCCQ` **no existen** como componente (`CV15` es el rem. tapón, otra cosa) | no | El cilindro `PB1` está discontinuo y el tornillo del corta queso se importa (§, línea 559). ¿Valeria sigue haciendo la horqueta o el corta queso ya viene entero? |
| `X5` (entrada del pavonado en el Excel) | **no existe**; GP2 usa `X4` → Y1 | — | ¿X5 del Excel es el X4 de GP2 (mismo crudo) o es otra pieza? |
| (las otras ~6 filas: partes por PS) | sin el xlsx no las puedo nombrar | — | — |

### 4.2 Talleristas (25 filas · 3 resueltas · 22 faltan)

| ítem | hoy en base | ¿con datos que hay? | pregunta al dueño |
|---|---|---|---|
| Tallerista **Ruben** (hoja de 48 códigos) | no existe (13 talleristas) | no | ¿Quién es Ruben, sigue trabajando, qué arma? Es la hoja más grande del Excel. |
| Tallerista **Edwin** | no existe | no | ¿Vigente? ¿Qué hace? |
| Tallerista **Nacho** | no existe | no | Ídem. |
| Tallerista **Ezequiel** (su hoja arranca titulada "German") | no existe | no | ¿Es una copia de la hoja de German o es otra persona? |
| Cajones `CAJ1` (plástico s/calado) / `CAJ2` (calado) / `CAJ3` (metálico) — en 9 de 14 hojas | no existen | sí, si se decide modelarlos como componente que viaja con el trabajo | ¿Querés que los cajones se cuenten/envíen como parte (stock por tallerista) o los dejamos fuera? |
| GRJ13 / GRJ14 cepillos Gilardi | ✔ existen (Gilardi Esther como proveedor de insumo, id 30) | — | — (resueltas) |
| `GRJ15` Pintura Azul Mate (Ortiz Yanina) | no existe; Ortiz Yanina (4288) no existe como proveedor | no | ¿A qué pieza/artículo va la pintura? ¿Ortiz Yanina es proveedor de insumo o tallerista? |
| `GRJ16` Despolvillador de Yerba | no existe como parte, **pero el art 591 ya está** (Prov AT Tierra Nativa + caja A4) | ya resuelto por otro camino | ¿Confirmás que 591 entra terminado (no necesita GRJ16)? |
| `GRJ20` Set Tapers | no existe, **pero el art 070 ya está** (Prov AT Pettofrezza + caja A4) | ya resuelto por otro camino | Ídem 070. |
| Alias `CARLOS` → tallerista 9 (Carlos Aguirre) | sigue apuntando a 9 | sí (§4bb: "Carlos" = Alex Escalante, tallerista 2) | ¿Cambio el alias CARLOS a Alex Escalante (2)? Hoy una importación "Carlos" le carga a Aguirre. |

### 4.3 Insumos-Partes (57 filas · 31 resueltas · 26 faltan)

| ítem | hoy en base | ¿con datos que hay? | pregunta / nota |
|---|---|---|---|
| `PEST1` | ✔ existe (sin proveedor) | ver §2 | ¿Pat Bet Plast? |
| `PA15`, `PA16`, `PB1`, `PEP6` | no existen — **decididos discontinuos** (§4ba) | no crear | — |
| `BOM14` = Caño Inox 170 mm (en GP2 BOM14 es el Precinto) | existe el precinto; el caño 170 **no existe** (BOM12 es el de 140 mm) | no | ¿Qué bombilla usa el caño de 170? ¿Se carga con otro código? |
| `CP7` Mangos Corta Queso, `HP2` Inser. Neg. Cuch y Pala | no existen (consumo `#REF!` en el Excel; Planify 3092 Nazareno) | no | ¿Vivos o discontinuos? |
| `X5`, `V15C`, `VCCQ` | no existen (ver 4.1) | no | ver 4.1 |
| Cartones "faltantes duros" `A1D` (120, Vihal), `D5A` (546), `E2B` (581), `G6A` (550), `H2A` (104), `P1A` (760) | **ninguno existe**; los 6 artículos sí, con receta y ruta | parcial: hay gemelo/formato para calcar | ¿Se dan de alta con formato del gemelo (regla "creá según gemelos")? ¿Cuál es la posición de estantería de cada uno? |
| 5 precintos negros N°8–16 (Precinter, x20.000) | ninguno existe (no hay componente con "precinto" salvo BOM14) | no | ¿Entran a la OC? ¿Van a Sector Cartón como insumo de uso general? |
| 5 etiquetas + ribbon (Sumatik, x8.000) | ninguno existe | no | Ídem. |
| Film stretch y fleje PP (Packaging y Servicios) | no existen (el proveedor sí, id 21) | no | Ídem. |
| 4 bolsas de filtro de café (arts 031, 034, 836, 867; Vihal / Papelera 9 de Julio) | no existen; los 4 arts sí (IJUPA), sin bolsa en receta | sí para el proveedor (existen), no para código/posición | ¿Código y posición de cada bolsa? |
| `A1C` pliego "Bombilla Chef" de AJ Adhesivos | no existe (`A2A`/`V3A` = Pliego Ad 500/506, ya están) | no | ¿A1C es un pliego nuevo o un renombre? |
| `456` Espátula Lisa Nylon c/mango, `389` Espumadera Nylon c/mango | artículos **no existen** (no se sabe qué mango llevan) | no | ¿Qué mango llevan? (los otros 9 nylon ya están) |
| (resto hasta 26) | sin el xlsx no las puedo nombrar | — | — |

### 4.4 Insumos-Proveedores (6 filas · 1 resuelta · 5 faltan)

| proveedor | hoy en `proveedor_insumo` | ¿con datos que hay? | pregunta |
|---|---|---|---|
| Gilardi Esther (3847) | ✔ id 30 | — | (probable "1 ya está") |
| AJ Adhesivos como proveedor de INSUMO (vende el pliego) | ✔ id 40 "AJ- Adhesivos", rubro Sector Cartón (además PS 12) | — | resuelto |
| **Precinter** (precintos) | no existe | no (falta cod_prov) | ¿cod_prov ISIS? |
| **Sumatik** (etiquetas/ribbon) | no existe | no | ¿cod_prov? |
| **Cia Integral Etiquetas** (etiquetas C3A/H4C/T4A de los afiladores) | no existe; las 3 piezas existen sin proveedor... **ojo: H4C hoy tiene proveedor Pol** | no | ¿Las etiquetas de los afiladores las hace Cia Integral o Pol? |
| **Ortiz Yanina** (4288, pintura) | no existe | sí (cod_prov conocido) | ¿Es proveedor de insumo? (ver GRJ15) |
| Simko / Telleria (Excel plásticos) | no existen — Simko descartado por el dueño ("no sé quién es") | — | ¿Telleria es un inyector vigente? |

### 4.5 Lo que el 12-09 estaba mal en el archivo y sigue igual
- El amarillo de Insumos-Partes no significa "está en GP2" (PA15/PA16/PB1 amarillos y no existen; PEST1 sin marcar y existe). Sigue así.
- `BOM10` ya no existe (confirmado: no hay componente BOM10).
- 591 y 070: existen como artículo por Prov AT, no como parte de garage (confirmado, rutas 1 c/u con Tierra Nativa / Pettofrezza).

---

## 5. Las 3 preguntas que quedan para el dueño (la de los palos ya está contestada)

1. **PEST1 (Insertos Mango de Madera, sector Plástico): ¿lo inyecta Pat Bet Plast?** Hoy es el único insumo comprable sin proveedor; va en 7 artículos (941E–948E). En tu lista de precios el bloque Pat Bet Plast tiene "Insertos Importados" $90,26 — ¿es ése? (Si sí, cargo proveedor y precio.)

2. **"2 limpia"** — dos cosas, con el dato al lado:
   - `GRJ28` y `GRJ29` se llaman igual, "Cepillo Limpia Bombilla" (los dos Cimarrón, ambos Blist-Pack, 555 Loeke en Caja N°2 x36 / 764 Chef en Caja N°1 x36 — igual que los listados). ¿Los renombro "Cepillo Limpia Bombilla LK" / "… CH" como GRJ13/GRJ14, o es la misma pieza física y los unifico en un solo código?
   - `GRJ21` Bowls 330ml está `discontinuo` **pero es la única pieza de la receta del art 071 "Bowl Multi Uso 330ml"** (activo, 2 rutas: GRJ21 → Fábrica → virgilio y caja A4 N°10 ×1/4; sin est_madre, stock 0, 0 movimientos). ¿El 071 se vende? Si no → marco 071 discontinuado y GRJ21 queda como está (no se borra: tiene receta y ruta colgando). Si sí → GRJ21 no puede estar discontinuo.

3. **Los 10 cartones "LOKE"** (H1A, H1C, H2C, H4C, I2A, I2B, I3C, I42, K5D, A1B1): hoy los 10 tienen `marca='LOEKE'` (tu decisión del 08-09: "la marca loke no va"), y **marca 'LOKE' ya no es posible**: el CHECK `componente_marca_chk` sólo admite LOEKE/CHEF. Familia de OC que le toca a cada uno hoy (formato|marca|categoría, según `_oc_validar_carton`):

   | cartón | formato | familia hoy | tamaño de la familia hoy |
   |---|---|---|--:|
   | H1A, H1C, H2C, H4C, I2B, I42, K5D | LOKE | **Formato LOKE · LOEKE** (múltiplo 16.000, mín 1.000/código) | 11 (+ CART186, G2A, I3B, M2B) |
   | I2A (Cartón 115), I3C (Cartón 121) | **Huevo** | Formato Huevo · LOEKE (múltiplo 25.000, mín 2.000/código) | 22 |
   | A1B1 (Cartón 120, Envases Vihal) | **Bolsa** | Formato Bolsa · LOEKE (mínimo 20.000) | 3 (A1B, A1B1, BOLSA550) |

   Si volviera la marca LOKE: habría que ampliar el CHECK y la familia "LOKE·LOEKE" se partiría en **LOKE·LOKE = 8** (H1A H1C H2C H4C I2B I3B I42 K5D) y **LOKE·LOEKE = 3** (CART186 G2A M2B), cada una con su múltiplo de 16.000 → dos pedidos mínimos en vez de uno. **¿Confirmás que queda como está (marca LOEKE, submarca LOKE sólo como formato)?** Y aparte: I2A e I3C no son formato LOKE sino Huevo — ¿está bien que estén en la lista de "los 10"?

---

## 6. 717 / 537 / 567 — confirmación, sin propuesta

El "catálogo" es el backlog de los dos listados mayoristas sin los E (§4bl/§4bm/§4bn: 199 códigos → quedan 3). **Hoy ninguno de los tres existe en `GP2.articulo`** (verificado), y el dueño los dejó pendientes a propósito (§4bj-bis, 11-09).

| cód | qué es | dónde aparece hoy |
|---|---|---|
| 717 | Chef "Cuchillo de Untar Acrílico/Cuch Plast x4" | listado CH (uxb 24, caja N°1); hoja Cajas fila 275 marcada **"discontinuo"** (col H); est_madre **0 uni/mes**; grupo A de `ARTICULOS_FUERA_DE_GP2.md` (Log/Fabr, 0 partes) |
| 537 | Loeke "Pela y Pica Ajo de Acero" | listado LK (uxb 12, caja N°7); hoja Cajas fila 161 (D=7, F=12); Conversion: gemelos Chef **781** y **649**; **no** está en est_madre ni en Costos |
| 567 | "Corta Palta" (§4bj-bis) | **en ninguna tabla ni hoja de la base** (ni listados, ni Cajas, ni Costos, ni est_madre; el único "567" es el precio $567,41 de la Caja N°10) |

No puedo re-derivar el "199" porque los xlsx de los listados no están en el repo (`uni_x_articulo_x_caja` en base tiene 287 códigos sin artículo, casi todos reventa/importado/discontinuo, sin el filtro que usó esa sesión). Lo que sí se confirma: fuera de los E, **el backlog documentado son exactamente estos 3 y siguen sin modelar.**

---

## Resumen para el dueño (≤10 líneas)

1. Palos 231/232/233: SQL listo en §1.3 — caja N°15 (A9B) y 12 x caja como el 234, componente nuevo `BANDITA` en Sector Cartón (stock 0, sin proveedor), receta A9B 1/12 + bandita 1, 6 rutas insumo→Fábrica→Virgilio. Sólo falta tu "dale".
2. Ojo: 231/232/233 también figuran como que Tierra Nativa los entrega TERMINADOS (`articulo_prov_at`). Con tu modelo (Fábrica pone la bandita) eso sobra: ¿lo desactivo?
3. Bandita: ¿quién la vende? En la LP hay "Banditas 35x194" (Pol, $8.250, "Falta Prov") y "Super Bands N°15" (López José Daniel, $1,08/u).
4. PEST1: único insumo comprable sin proveedor; UPDATE a Pat Bet Plast listo, espera tu sí. Va en los 7 inox 941E–948E.
5. 941E/946E: la planilla los trata como importados sin cartón ni caja (coincide con GP2). 942E–945E/948E: Caja N°12 ✔, pero en GP2 la caja está sólo en el FK (no en receta ni ruta) y la planilla dice 24 x caja para 942E/945E. 947E no existe en ningún lado.
6. El xlsx de faltantes del 08-09 NO está en el repo: reconstruí lo nombrado y lo re-verifiqué (§4). Prov Servicio sigue en 0/11 (New Metal, Chormium, Almafuerte, Valeria); Ruben/Edwin/Nacho/Ezequiel y los cajones CAJ1-3 no existen; 6 cartones duros y ~14 insumos de sector (precintos, etiquetas, bolsas de filtro) tampoco. Subí el archivo de nuevo y lo guardo en el repo.
7. "2 limpia": GRJ28/29 mismo nombre → ¿LK/CH?; GRJ21 discontinuo pero es la receta del 071 Bowl → ¿el 071 se vende?
8. Cartones LOKE: los 10 están en marca LOEKE (marca LOKE ya no la admite la base); 7 van a la familia LOKE·LOEKE (11 códigos), I2A/I3C son Huevo, A1B1 es Bolsa. ¿Queda así?
9. 717/537/567: siguen sin modelar, a propósito; 567 no aparece en ningún dato de la base.

---

# §7. Segunda vuelta (2026-09-13, tarde) — lo que el dueño pidió traer para decidir

Todo re-consultado contra `hrxfctzncixxqmpfhskv` schema `GP2`. **Nada escrito en la base.**
`db/verificar.sql` entero **antes**: 35 reglas, las 35 en **0**.

> **Tres cosas de §1–§5 se RETIRAN por medición.** Están marcadas ⛔ abajo. Si alguna sesión
> futura lee §1.3 o §2 sin leer esto, va a repetir un error ya descartado.

---

## 7.1 `articulo_prov_at` 92/94/95 — el `activo=false` arregla menos de lo que parece

**Lo incómodo primero: el 234 (fila id 93) tiene EXACTAMENTE el mismo problema y no estaba en la
lista.** Y no son 4 filas: son **34**.

### Lo medido

| Qué | Valor |
|---|--:|
| Filas de `articulo_prov_at` | 91 |
| Con paso `proveedor_at` en la ruta (bien modeladas) | 45 |
| **Artículo de GP2 SIN paso `proveedor_at` en su ruta** | **34** |
| Filas cuyo `cod_art` no es un artículo de GP2 | 12 |
| Entregas registradas de 231/232/233/**234** | **0** |
| Filas de inventario en la ubicación 54 (Tierra Nativa) | **0** |

Las 34 por proveedor: **Cabral 26**, Tierra Nativa **4** (231, 232, 233 **y 234**), Maspoli 3,
Pettofrezza 1. O sea los palos no son la excepción: son 4 de 34, y el caso hermano del 234 —
misma ruta `insumo → Fábrica → virgilio`, mismo proveedor, misma caja — **está activo igual**.

El que sí está bien modelado es el **591**: su ruta 956 tiene el paso `proveedor_at` (Tierra
Nativa) en el orden 2. Ésa es la forma de un artículo que entra terminado. Ninguno de los cuatro
palos la tiene.

### ⛔ Se retira: "`activo=false` cierra la puerta"

`crear_entrega_prov_at` (leído hoy de `pg_get_functiondef`, no de `db/`) chequea la asignación así:

```sql
if not exists (select 1 from articulo_prov_at a
                where a.proveedor_at_id = p_prov_at_id and a.cod_art = p_cod_art) then
```

**No mira `activo`.** Lo que sí lo mira es `entregas_prov_at_bundle` (`where coalesce(a.activo,true)`),
que es de donde `Prov Art Terminado/Entregas/EntregasAT_GP2.html` saca la lista — y ésa es la
**única** pantalla que llama a la RPC. Conclusión exacta: **`activo=false` saca el artículo de la
pantalla (que es por donde entra un operario), pero la RPC lo sigue aceptando si alguien la llama
derecho.**

### Qué pasa si se registra una entrega (confirmado leyendo `recepcion_virgilio`)

Consume **toda la receta** desde `ubic_de('proveedor_at', 13)` = ubicación **54**, que tiene **0
filas de inventario**. Un 231 dejaría `GRJ22 −1`, `A9B −1/12` y `BANDITA −1` en la 54. Lo mismo
haría el 234 (GRJ17 + A9B), y lo mismo cualquiera de las 26 de Cabral (el 501 arrastraría 14 rutas).

### Las tres opciones (elegir una)

**A — Consistente con lo que explicaste (recomendada): los CUATRO palos fuera del catálogo AT.**

```sql
-- ANTES (para pegar el resultado en el HISTORIAL)
select id, cod_art, descripcion, activo from "GP2".articulo_prov_at where id in (92,93,94,95) order by id;

update "GP2".articulo_prov_at set activo = false
 where id in (92,93,94,95) and cod_art in ('231','232','233','234') and proveedor_at_id = 13;
-- esperado: UPDATE 4

-- DESPUES
select id, cod_art, activo from "GP2".articulo_prov_at where proveedor_at_id = 13 order by id;
-- esperado: 92/93/94/95 en false, 96 (591) en true
```

*Riesgo:* si Tierra Nativa **sí** entrega el 234 terminado (es el único de los cuatro que no lleva
bandita), lo sacás de la pantalla de Entregas y hay que modelarle la ruta con paso `proveedor_at`
como el 591. Por eso es pregunta y no deducción.

**B — Sólo los tres, como venía.** `where id in (92,94,95)`. Deja al 234 con el mismo agujero y la
base queda diciendo dos cosas distintas de cuatro artículos gemelos.

**C — El arreglo de raíz, y las 34 de una.** Que la RPC exija lo que el modelo ya dice: que el
artículo tenga un paso `proveedor_at` en su ruta. Es una migración de función, no de datos, y no
depende de `activo`:

```sql
-- dentro de crear_entrega_prov_at, reemplazando el if de la asignación
if not exists (select 1 from articulo_prov_at a
                where a.proveedor_at_id = p_prov_at_id and a.cod_art = p_cod_art
                  and coalesce(a.activo, true)) then
  raise exception 'El articulo % no esta asignado (o esta inactivo) para ese proveedor', p_cod_art;
end if;
```
*(Ojo: el comment de la función dice que el chequeo se aflojó a propósito porque 5 filas tenían la
descripción vacía — 193, 231, 232, 233, 591. Agregar `activo` NO revive ese bug: aquél era por
`descripcion`, no por `activo`.)*

**A y C no se pisan.** Lo prolijo es hacer las dos.

---

## 7.2 Proveedor de `BANDITA` (componente 916) — los candidatos, con el dato que los separa

`v_planilla_precio`, todo lo que dice "band" o nombra el palo de amasar:

| # | Proveedor | Producto | Precio | Fecha lista | Última compra | ¿Existe en `proveedor_insumo`? |
|--:|---|---|--:|---|---|---|
| 1 | 2147 Gráfica Pol | **Banditas 35 × 194 mm** (f390) | $8.250,00 | 15-04-2026 | — | **sí**, "Talleres Gráficos Pol" (13, rubro Sector Cartón) |
| 2 | 2147 Gráfica Pol | Bandita Ralladores (f389) | $8.250,00 | 15-04-2026 | — | ídem |
| 3 | 4399 López José Daniel | Super Bands Bolsa N°15 (Bandita Negra) (f514) | $1,08 | 05-12-2025 | 09-12-2025 | **NO** — habría que darlo de alta primero |
| 4 | 2147 Gráfica Pol | *Etiqueta* Palo de Amasar 40cm (f408) | $9.500,00 | 15-04-2026 | — | ídem |

**Lo que inclina, sin decidirlo:** `BANDITA` está en **Sector Cartón**, y el único proveedor de esa
lista con rubro Sector Cartón es Pol. El #3 es el único con precio por unidad ($1,08) y compra
real, pero es una gomita elástica ("Super Bands", "Bandita Negra"), no una faja impresa, y **López
José Daniel no existe como `proveedor_insumo`** (la FK `componente_proveedor_fkey` exige el nombre
exacto, así que elegirlo son dos escrituras, no una).

El #1 es el único cuya medida (35 × 194 mm) es la de una faja que rodea un palo.

```sql
-- OPCIÓN Pol (#1, #2 o #4 — el nombre del proveedor es el mismo)
update "GP2".componente set proveedor = 'Talleres Gráficos Pol' where id = 916 and codigo = 'BANDITA';

-- OPCIÓN López José Daniel (#3) — hay que crearlo antes
insert into "GP2".proveedor_insumo (nombre, cod_prov, rubro) values ('Lopez Jose Daniel', '4399', 'Sector Cartón');
update "GP2".componente set proveedor = 'Lopez Jose Daniel' where id = 916 and codigo = 'BANDITA';

-- verificación (cualquiera de las dos)
select id, codigo, proveedor from "GP2".componente where id = 916;
```

El **precio** es una segunda pregunta: $8.250 no es por unidad (es el millar o el paquete) y ninguna
de las tres filas dice a cuántas unidades corresponde.

---

## 7.3 `PEST1` (768) — con qué se cruzó, y por qué la respuesta es "sí, pero hay dos"

⛔ **Se corrige §2.** Ahí decía que en el bloque de Pat Bet Plast hay "Insertos Importados $90,26" y
que "ninguno dice mango de madera". **Sí lo dice, en otro proveedor, y con el mismo código ISIS.**

El cruce es **`cod_isis`**, no el texto:

| cod ISIS | Proveedor | Producto en la LP | Precio | Fecha lista | Última compra |
|---|---|---|--:|---|---|
| **4776** | 797 Pitzus Manuel (**Pat Bet Plast**) | Insertos Importados (f345) | **$90,26** | 01-08-2026 | **28-11-2025** |
| **4776** | 4465 **Kollplast** | **Inserto Mgo Madera** (f1076) | **$219,97** | 07-08-2026 | — |
| 3096 | 4465 Kollplast | Inserto Pisapapas (f1077) | $219,97 | 07-08-2026 | — |
| 0116 | 797 Pat Bet Plast | Inserto CH Cortos+ojal (cuch/espat/bati/cane) (f325) | $190,99 | 01-08-2026 | 30-04-2026 |

Los tres apoyos de "Pat Bet Plast", y el que lo discute:

1. **El hermano.** El único otro `PEST` de GP2 es `PEST2` "Insertos Pisa Papas" (735), y **ya tiene
   proveedor Pat Bet Plast**. Mismo prefijo, mismo sector, **mismo `material_id` 742** (PP 2630).
2. **El material.** De los 21 componentes con material 742: 12 Pat Bet Plast, 6 Pettofrezza,
   2 JL Matricería, 1 sin proveedor (que es PEST1). Mayoría, no prueba.
3. **La compra real.** El 4776 de Pat Bet Plast tiene última compra 28-11-2025; el de Kollplast
   nunca se compró.
4. **En contra:** el que se llama **literalmente** "Inserto **Mgo Madera**" — la descripción exacta
   de PEST1 — es el de **Kollplast**, y Kollplast **también existe** en `proveedor_insumo` (id 12).
   Kollplast cotiza los dos (4776 y 3096), o sea es la alternativa de Pat Bet Plast en toda la línea.

**La plata:** PEST1 consume **684 uni/mes** (`v_consumo_componente`, 7 artículos). La diferencia
entre los dos precios es $129,71 por unidad → **$88.722 por mes / $1.064.664 por año**. No es una
elección cosmética.

```sql
-- OPCIÓN Pat Bet Plast (el que ya tiene el hermano PEST2, y el único comprado)
update "GP2".componente set proveedor = 'Pat Bet Plast'
 where id = 768 and codigo = 'PEST1' and sector_id = 6 and proveedor is null;

-- OPCIÓN Kollplast (el que la lista llama "Inserto Mgo Madera")
update "GP2".componente set proveedor = 'Kollplast'
 where id = 768 and codigo = 'PEST1' and sector_id = 6 and proveedor is null;

-- verificación
select id, codigo, descripcion, proveedor from "GP2".componente where id = 768;
```

> ✅ **DECIDIDO Y APLICADO el 2026-09-13** — *"PEST 1, KollPlast. pero deja registrado que a partir
> de noviembre aprox no se debería inyectar más"*. `componente` 768 → `proveedor = 'Kollplast'`.
> Invariante `A2` en 0 (Kollplast ya tenía la ubicación de inyector 60) y el costo no se movió
> (PEST1 no tiene fila en `precio_proveedor`). **Queda anotado que PEST1 se deja de inyectar
> ~noviembre 2026** — ver CONOCIMIENTO §4cz, con lo que hay que hacer y lo que NO hay que cargarle
> mientras tanto.

Con cualquiera de los dos, PEST1 deja de ser el único insumo comprable sin proveedor (los otros 18
son 17 de `fabricacion` + 1 `discontinuo`).

---

## 7.4 `941E`–`948E` — el cuadro, ordenado por plata — ⛔ EL CUADRO DE CAJAS QUEDÓ VIEJO (2026-09-14)

> **La columna "GP2 caja" de abajo ya no vale: los siete están en `A9B` Caja N°15** desde el 14-09
> (CONOCIMIENTO §4do), y las dos líneas que decían "—" para 941E/946E también quedaron obsoletas:
> los dos tienen caja, receta y ruta.
>
> **Y el punto (a) — "la caja está en el FK y NO está en la receta, 14 artículos" — está CERRADO.**
> Medido el 14-09: de los **193** artículos con `componente_caja_id`, **0** no tienen su línea de
> receta y **0** tienen la línea sin paso de ruta. Los 14 se resolvieron entre el 13 y el 14-09; los
> $16.200/mes que calculaba esta sección **ya se están cobrando**. No queda nada que hacer acá.

⛔ **Se corrige §3**, que leía la hoja Cajas y decía "los listados mandan, falta el dato". **La hoja
COSTOS — la que calcula el costo, el criterio que vos mismo fijaste el 11-09 — confirma la hoja
Cajas al centavo**: su columna M es $360 ÷ (uni x caja).

| Art | Descripción | GP2 caja | GP2 uxc | Planilla *Cajas* F (uxc) | Planilla *Costos* M ($/uni) | Est Madre uxb | uni/mes | Caja que GP2 NO costea |
|---|---|---|--:|--:|--:|--:|--:|--:|
| 943E | Cucharón Inox | A2 (N°12) | 12 | 12 | 30,00 | 12 | 144 | **$4.320** |
| 942E | Cuchara Inox | A2 (N°12) | 12 | **24** | **15,00** | 12 | 132 | **$3.960** |
| 948E | Espumadera Inox | A2 (N°12) | 12 | 12 | 30,00 | 12 | 108 | **$3.240** |
| 945E | Espátula Calada Inox | A2 (N°12) | 12 | **24** | **15,00** | 12 | 82 | **$2.460** |
| 944E | Cuchara Fideos Inox | A2 (N°12) | 12 | 12 | 30,00 | 12 | 74 | **$2.220** |
| 941E | Espátula Lisa Inox | — | 12 | sin fila | sin M | 12 | 86 | — |
| 946E | Cuchara Calada Inox | — | 12 | sin fila | sin M | 12 | 58 | — |
| 947E | — | no existe | — | no existe | no existe | no está | — | — |

Tres cosas separadas, de mayor a menor:

**(a) La caja está en el FK y NO está en la receta — $16.200/mes sólo en los 94xE.** Los 5 que
tienen caja la tienen únicamente en `articulo.componente_caja_id`: su receta es **1 línea (PEST1)**
y tienen **1 sola ruta**. No hay línea de caja ni paso de caja. **No es privativo de los 94xE: son
14 artículos**, y el más caro no es un E:

| Art | Caja | uxc | $/mes sin costear |
|---|---|--:|--:|
| 222 | A2 | 12 | **32.580** |
| 312 | A2 | 12 | 9.420 |
| 395 | A8 | 12 | 8.509 |
| 943E | A2 | 12 | 4.320 |
| 942E | A2 | 12 | 3.960 |
| 948E | A2 | 12 | 3.240 |
| 945E | A2 | 12 | 2.460 |
| 944E | A2 | 12 | 2.220 |
| 311 | A2 | 12 | 1.020 |
| 910 | A2 | 12 | 720 |
| 715 | A1 | 24 | 20 |
| 818, 058, 059 | A4 / A9 | 12 | 0 (sin Est Madre) |

**Total: $68.469 por mes / $821.628 por año de caja que hoy no entra al costo.** Los otros 175
artículos con caja sí la llevan en la receta.

**(b) ¿24 o 12 por caja en 942E y 945E?** La planilla lo dice **dos veces** (Cajas F=24 y Costos
M=15). GP2 y `est_madre` dicen 12 — pero el `uxb` de est_madre da exactamente `proy_uni_mes / 12`
en los **siete**, así que no es un testimonio independiente: es el mismo 12 repetido.
`uni_x_articulo_x_caja` (los listados mayoristas, que según tu regla mandan) **no tiene ningún
94xE**. O sea: la planilla es la única fuente con dato propio, y dice 24.

```sql
-- si va 24 (lo que dice la planilla en sus dos hojas)
update "GP2".articulo set articulos_por_caja = 24 where codigo in ('942E','945E');
-- verificación
select codigo, articulos_por_caja from "GP2".articulo where codigo ~ '^94[0-9]E$' order by 1;
```

**(c) 941E / 946E sin caja: GP2 y la planilla coinciden** (Costos filas 124 y 129 sólo tienen la
columna E = Importados, sin L de cartón ni M de caja; Importados f104/f113 los da a USD 0,66).
**No hay nada que cambiar.** Y **947E no existe en ningún lado** — ni GP2, ni Cajas, ni Cartones,
ni Costos, ni Importados, ni la LP, ni est_madre.

---

## 7.5 332 / 335 / 337 y 573 / 556 / 517

### Los tres inox: no hay nada que decidir en GP2, el que está viejo es el sitio

`[usuario 2026-09-13, textual]` *"332/7 y 630/7 son discontinuos. Se reemplazaron por 941/8E"*.

- **332, 335 y 337 no existen en `GP2.articulo`** (verificado). No están "discontinuados en GP2":
  no están. Están en `est_madre` (136 / 64 / 48 uni/mes) porque la Est Madre arrastra
  discontinuados — la misma trampa del 515 (§4cw).
- **Su reemplazo son los 94xE de §7.4.** Es el mismo cajón: los cubiertos de acero inox.
- Lo que queda por hacer **no es en este repo**: darlos de baja en loekemeyer.com, que los sigue
  mostrando activos.

### ⛔ Se retira: "573, 556 y 517 no tienen despiece en ningún lado". **Dos de los tres sí lo tienen, en la planilla.**

| Cód | Qué es | Dónde está el despiece | Estado real |
|---|---|---|---|
| **573** Bombilla Color Metalizado | hoja **Bombillas** fila 2: *"bombilla ALUMINIO COLOR ANODIZADO ART: 755/L573"* | caño 135 mm $186,32 · resorte $66,10 · niquelado resorte $26,06 · tapón aluminio $40,50 · anodizado $175 · corte cañito $85 = **$578,98**, con tiempos (gallolado 5,50 s · doblado 5,97 s · estampado 5,00 s) | **despiece COMPLETO.** Gemelo Chef 755. Caja N°2, 24 x caja, cartón E=21. Est Madre 52 uni/mes |
| **517** Pinza Gastronómica | hoja **Materiales Loeke** filas 166-167 + hoja **Remaches** fila 54 | `517D` pala de acero (fleje 121,3 × 0,8) + `517D` manija de acero (fleje 167,3 × 0,8), tallerista **GUILLE**; 3 remaches **SR1 + SR2 + SR3** | **despiece COMPLETO**, pero la hoja Materiales fila 276 tiene `#REF!` y **no está en la hoja Costos**. Sin gemelo Chef. Caja N°7, 12 x caja |
| **556** Sacayerba | — | hoja Costos fila 225: `C='Fab'`, **`E='xx'`** (sin material), L=89 cartón, M=10,91 caja N°2, N=5,90 → $105,81 | **el único sin despiece de verdad.** La planilla lo costea **sólo como envase**: dice "Fab" y no tiene ni material ni mano de obra. Materiales Loeke fila 27 tiene "sacayerba" con `#REF!`. Gemelo Chef 765 |

Ninguno de los tres existe en `GP2.articulo`. **573 y 517 se pueden dar de alta con lo que ya hay**
(573 es casi un calco de las otras bombillas; 517 son 2 flejes + 3 remaches + Guille); **556 no**,
porque ni la planilla sabe de qué está hecho.

---

## 7.6 `GP2_FALTANTES_20260908.xlsx`

**Sí, subilo de nuevo.** Sigue sin estar en el repo (`find` en todo `/home/user`, 13-09). Sin él,
§4 es la reconstrucción de las menciones sueltas de CONOCIMIENTO, no el archivo fila por fila —
faltan ~6 filas de Prov Servicio y el resto de las 26 de Insumos-Partes que nadie nombró nunca.
Cuando lo subas se guarda en el repo (trampa §4v: la planilla de costos se pidió "muchísimas veces"
por no estar guardada).

---

## 7.7 Resumen de las 5 decisiones (ordenadas por plata)

| # | Decisión | Plata en juego | Estado |
|--:|---|--:|---|
| 1 | La caja en el FK pero no en la receta (14 artículos) | **$821.628 / año** | no preguntado antes; sale de §7.4 |
| 2 | PEST1: Pat Bet Plast ($90,26) o Kollplast ($219,97) | **$1.064.664 / año** de diferencia | espera tu sí |
| 3 | 942E / 945E: 24 o 12 por caja | $38.520 / año | espera tu sí |
| 4 | `articulo_prov_at`: opción A (4 filas), B (3) o C (la RPC) | latente: stock en negativo en la ubic. 54 | espera tu sí |
| 5 | Proveedor de BANDITA: Pol o López José Daniel | precio todavía sin unidad | espera tu sí |


---

# §8. Cierre del 2026-09-13 (tarde): las 5 decisiones, y el hallazgo que dejaron

| # | Decisión del dueño | Estado |
|--:|---|---|
| 1 | PEST1 → **Kollplast**, y anotado que deja de inyectarse ~noviembre 2026 | ✅ aplicado (componente 768) |
| 2 | `articulo_prov_at`: **opción A** — *"es la misma lógica que lo de cimarron"* | ✅ aplicado (ids 92/93/94/95 en `activo=false`; el 591 sigue activo) |
| 3 | BANDITA → **Talleres Gráficos Pol** | ✅ aplicado (componente 916) |
| 4 | Las 14 cajas a la receta | ✅ aplicado (recetas 923–936, rutas 978–993, pasos 3744–3791) |
| 5 | 942E / 945E: **12 por caja** (contra la planilla, que dice 24) | ✅ decidido — no había que cambiar nada; ver CONOCIMIENTO §4dd |

Invariantes 35/35 en 0 antes y después. Snapshot de costos previo:
`zz_backups."GP2_Snap_costos_cajas_20260913"`.

**Lo que apareció al medir el punto 4 y es más grande que todo lo anterior:
`v_costo_componente` cobra la CAJA ENTERA por unidad — ARS 38.538.090 por mes sobre 189
artículos, pre-existente.** El mecanismo, la prueba y las dos formas de arreglarlo están en
CONOCIMIENTO §4dc. **ARREGLADO** en la misma sesión (*"1 arregla"*), migración `la_caja_se_cobra_por_su_parte_no_entera`, verificado en 6 testigos al centavo y `db/` regenerado con md5 contra la vista viva. Queda registrado en la auditoría de Supabase.
