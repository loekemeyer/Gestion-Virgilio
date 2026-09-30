# Componentes sin cajón cargado — 2026-09-23

Pedido de Thomas: *"mandame un listado con todos los componentes que no tienen cajón cargado.
Por ejemplo, el descorazonador. Que lo marcás en uni."*

Dato: `GP2.componente.uni_x_cajon` vacío o 0, sin discontinuados. **433 componentes** en total,
pero sólo **28** son los que la tablet te está pidiendo hoy y por eso caen en unidades — el resto
o no se mueve por la tablet, o va en otro envase y el cajón no aplica. El Descorazonador (1686,
Sector Procesado) es uno de los 28.

| Grupo | Cuántos | Qué pasa |
|---|--:|---|
| A. La tablet los pide y no tienen cajón | 28 | El sugerido y la carga caen en **uni** ("sin cajón cargado") |
| B. Sin cajón, pero hoy no se envían ni reciben | 105 | Nadie los ve; cargarlos es prolijidad, no urgencia |
| C. El cajón no aplica | 300 | Van en paquete, en kg o viven en Virgilio |

## A.1 — Ni cajón ni kilo: no hay forma de convertir (14)

Son los peores: sin `uni_x_cajon` **y** sin `kg_x_uni`, la tablet no puede ofrecer ni cajones ni
kilos, así que el operario carga a ojo en unidades.

| Sector | Código | Descripción | Aparece en |
|---|---|---|---|
| Procesado | C13 | Corta Queso Bastidor c/Cilindro | Enviar |
| Procesado | Z12 | Alamb. Aluminio Ganch. | Enviar |
| Remache | CV18D | Tornillo Sacafuente p/Niquelar | Enviar |
| Remache | V18D | Tornillo Sacafuente | Enviar y Recibir |
| Plástico | PINCEL590 | Pincel Silicona 11 gms (granel) | Enviar |
| Bombilla | BOM13 | Filtro p/Bombilla | Enviar |
| Bombilla | BOM14 | Precinto p/Bombilla | Enviar |
| Bombilla | BOM8B | Tela Manga Repostera (rollo x 900) | Enviar |
| Bombilla | C12 | Paleta Batidor Resorte | Enviar y Recibir |
| Bombilla | C12B | Paleta Batidor Resorte sin cromar | Enviar y Recibir |
| Garage | GRJ13 | Cepillo Limpia Mamadera | Enviar |
| Garage | GRJ14 | Cepillo Limpia Vajilla | Enviar |
| Garage | GRJ28 | Cepillo Limpia Bombilla | Enviar |
| Garage | GRJ29 | Cepillo Limpia Bombilla | Enviar |

## A.2 — Tienen el kilo, les falta el cajón (14)

Acá el peso está cargado, así que la cantidad se puede escribir en kg; lo que falta es el
**cajón**, que es la referencia con la que se mira el sugerido.

| Sector | Código | Descripción | Kg x uni | Aparece en |
|---|---|---|--:|---|
| Procesado | 1686 | Descorazonador | 0,014508 | Enviar y Recibir |
| Procesado | W1B | Grampa Batidor | 0,001500 | Enviar y Recibir |
| Remache | CV6 | Rem Sacafuente 3.7 x 29.6 p/Niquelar | 0,002150 | Enviar |
| Remache | CV9 | Remache uña niq. p/Niquelar | 0,000567 | Enviar |
| Plástico | D9 | Clavo 505 Niq. | 0,006530 | Enviar y Recibir |
| Plástico | PA17 | Mangos Cuch y P Torta | 0,016625 | Enviar |
| Plástico | PEST2 | Insertos Pisa Papas | 0,003817 | Enviar |
| Plástico | PV14 | Picos Reposteros | 0,001100 | Enviar |
| Plástico | PV17 | Pela Naranjas | 0,007075 | Enviar |
| Plástico | PV8 | Corta Torta | 0,063150 | Enviar |
| Plástico | PV8B | Corta Torta Chef | 0,063150 | Enviar |
| Bombilla | BOM10 | Resorte Biconico | 0,009630 | Enviar |
| Bombilla | Z21 | Cuchillo Torta CH/LK | 0,019320 | Enviar |
| Fleje | IE1 | Fleje N° 33 | 0,024100 | Enviar |

**Sector Crudo no aparece: sus 76 componentes tienen el cajón cargado.** Los que faltan están
todos del lado del procesado para adelante.

## B — Sin cajón, pero hoy no se envían ni reciben (105)

No los ve nadie en la tablet, así que no hay número en uni molestando. Quedan anotados por si más
adelante entran a una ruta.

- **Sector Fleje, 45 en kg** (el cajón no es su unidad: se pesan): CHAPA430, IA1, IA2, IA4, IA5,
  IA6, IA8, IA9, IA10, IA11, IB1, IB2, IB3, IB4, IB5, IB6, IB7, IB8, IC1, IC2, IC4, IC7, IC8,
  IC9, IC10, ID1, ID5, ID6, ID8, ID9, IE6, IE8, IE10, IE11, IF1A, IF2, IF3, IF3A, IF4, IF5, IF8,
  IF9, IF10, IF11, IF13.
- **Sector Movimiento, 41**: son los nodos intermedios "X tras M<matriz>" (B1-M78, D5-M78,
  E6-M194, G1-M80, H7-M10, H7-M173, I12-M8, J8-M80 y 33 flejes "tras M…"). No viajan a un
  tercero: son la pieza a mitad de camino adentro de Cervantes.
- **Sector Garage, 11**: GRJ12, GRJ12B, GRJ17, GRJ21, GRJ22, GRJ23, GRJ24, GRJ25, GRJ26, GRJ27,
  GRJ30.
- **Sector Plástico, 7**: PA3, PC6, PCP2, PCP4A, PEST1, PIEA, PIEB.
- **Sector Alambre, 1**: FLEJE90_BRUTO (kg).

## C — Donde el cajón no aplica (300)

| Sector | Cuántos | Con qué se mueve |
|---|--:|---|
| Cartón (10) | 177 | Paquetón del formato (`carton_formato.uni_x_bolsa`), no cajón |
| Terminado (12) | 99 | Son artículos terminados: viven en Virgilio, se cuentan por caja del artículo |
| Bolsas Plásticas (14) | 13 | Resina del inyector, en kg |
| Caja (11) | 11 | Paquetes de 25 (`parametro.caja_uni_x_paquete`) |

## La consulta, para repetirla

```sql
select s.nombre sector, c.codigo, c.descripcion, c.unidad_medida, c.kg_x_uni
  from "GP2".componente c
  left join "GP2".sector s on s.id = c.sector_id
 where coalesce(c.uni_x_cajon,0) = 0
   and not coalesce(c.discontinuado,false)
   and c.sector_id not in (10,11,12,14)   -- saca los del grupo C
 order by s.nombre, c.codigo;
```

**Nada de esto se cargó**: cargar `uni_x_cajon` es escribir datos y lo autoriza el dueño. Cuando
pases los valores (aunque sea de los 28 de A), se cargan con el SQL a la vista primero.

## Para llenarlo: `COMPONENTES_SIN_CAJON_2026-09-23.xlsx`

Las mismas 433 filas en Excel (hoja **Sin cajón**, con filtro y los grupos en la columna A), más una
hoja **Leyenda** con qué significa cada grupo. La única columna que se escribe es la **H, "Uni x
cajón (a cargar)"**, la de fondo amarillo. Devolvé esa planilla y se carga desde ahí.

**El .xlsx no va al repo**: `.gitignore` excluye `*.xlsx` salvo dos excepciones (la planilla madre de costos y `Tablas_Madre_y_Dependencias.xls`), y esto es una foto para llenar, no un maestro. Vive en la carpeta de trabajo y se manda por chat; si se pierde, se regenera con la consulta de arriba.
