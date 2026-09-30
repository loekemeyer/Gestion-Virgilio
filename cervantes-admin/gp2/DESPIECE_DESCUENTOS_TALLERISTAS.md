# Despiece: qué se le descuenta a cada tallerista cuando entrega

Generado el 2026-09-21 desde la base (`GP2`, ruta/ruta_paso + articulo_componente + componente_bom).
Fuente de verdad del descuento: las funciones `GP2.recepcion_virgilio(p jsonb)` (Virgilio) y
`GP2.crear_entrega_tallerista(...)` / el constructor `recepcionTall()` de `gp2-motor.js` (Cervantes).

## 1. Las dos puertas de entrega

| Puerta | Pantalla | Qué entra | Qué se descuenta del tallerista |
|---|---|---|---|
| **Virgilio** — artículo terminado | `Talleristas/Recepcion/RecepcionVirgilio_GP2.html` (hoy con candado en el menú, ver LOCKS 18/09 entrada 10) | el terminado, que queda en la ubicación Virgilio | **TODA la receta del artículo** (`articulo_componente`): el componente principal se transforma en el terminado (`recepcion_virgilio`), el resto sale como `consumo_virgilio` |
| **Cervantes** — parte armada / semi-elaborado | `Talleristas/Recepcion/EntregasTalleristas_GP2.html` | la parte, que vuelve a la ubicación de su sector | **el BOM de la parte** (`componente_bom`) como `consumo_tall`; si no tiene BOM, la pieza de entrada 1:1; si el paso es in-place, nada extra |

Reglas finas:

- **Principal (marcado `*` abajo):** lo elige `recepcion_virgilio` con `order by (sector_id=2) desc, cantidad desc, componente_id` — o sea prioriza sector 2, después la mayor cantidad. Es el que viaja como `comp_transformado`; el neto es el mismo cualquiera sea el elegido.
- **La caja y el cartón también se descuentan al tallerista.** Las líneas tipo `A8 x0.08` o `CART506 x1` son parte de `articulo_componente`, y `recepcion_virgilio` las saca de la ubicación del ORIGEN (el tallerista), no del sector.
- **Un mismo artículo puede tener dos talleristas** (505 = Danica + Lucho, 506 = Alex + Martin): son rutas duplicadas por tallerista, no un error.
- Los GRJ que aparecen como línea de descuento (GRJ10, GRJ5, GRJ13…) los arma OTRO tallerista por la puerta de Cervantes (sección 3).

## 2. Virgilio — artículo terminado (por tallerista)

Formato: `ARTÍCULO — componente ×cantidad | …` · `*` = principal (se transforma en el terminado).
Excluye artículos discontinuados. **156 pares (tallerista, artículo) sobre 154 artículos distintos** — el 505 y el 506 los entregan dos talleristas cada uno — repartidos en **11 contrapartes tallerista**; los Prov. AT (Pintos, Pettofrezza, Cabral, Maspoli, López José, The Plast, Paternal Goma, Carriero, Melinox, Tierra Nativa) entran por la misma RPC con `origen_tipo='proveedor_at'`.

### Fábrica (44) — Cervantes armando directo, no es un tallerista externo
- 058 Cierra Bolsa x2 — PC4 ×2* | CART058 ×1 | A9 ×0,083333
- 070 Set Tapers 0.8 Lts / 1.5 Lts / 3 Lts — GRJ30 ×1* | A4 ×0,25
- 071 Bowl Multi Uso 330ml — GRJ21 ×1* | A4 ×0,25
- 207 Ñoquera Madera Mgo Redondo — G1C ×1* | GRJ12B ×1 | A1 ×0,083333
- 229 Ñoquera Madera — G2B ×1* | GRJ12 ×1 | A9 ×0,083333
- 231 Palo de Amasar 30cm — GRJ22 ×1* | BANDITA ×1 | A9B ×0,083333
- 232 Palo de Amasar 40cm — GRJ23 ×1* | BANDITA ×1 | A9B ×0,083333
- 233 Palo de Amasar 50cm — GRJ24 ×1* | BANDITA ×1 | A9B ×0,083333
- 234 Palo de Amasar Frances 40 cm — GRJ17 ×1* | A9B ×0,083333
- 248 Cuchara Nylon Reforzada 33 Cm — PB2 ×1* | A1A ×1 | A7B ×0,083333
- 255 Mate Inox Térmico — GRJ26 ×1* | A4 ×0,125
- 256 Mate Madera Cerámica — GRJ27 ×1* | A4 ×0,125
- 280 Manga Repostera + 4 Boquillas — PV14 ×4* | BOM8B ×1 | F1A ×1 | A2 ×0,083333
- 299 Muñeco Silicona Antiderrame — G6B ×1* | PA3 ×1 | A11 ×0,083333
- 390 Cuchara Calada Nylon 1 Pza — PV6 ×1* | K6B ×1 | A2 ×0,041667
- 391 Cuchara Fideos Nylon 1 Pza — PV5 ×1* | K6C ×1 | A6 ×0,041667
- 392 Cucharon Nylon 1 Pza — PV2 ×1* | K7A ×1 | A6 ×0,041667
- 393 Espátula Calada Nylon 1 Pza — PV7 ×1* | K7B ×1 | A2 ×0,041667
- 394 Espátula Lisa Nylon 1 Pza — PV3 ×1* | K7C ×1 | A2 ×0,041667
- 441 Colador de Pasta Plástico — GRJ25 ×1* | A4 ×0,083333
- 507 Rompenueces — G1B ×1* | D5-M78 ×1 | A8 ×0,083333
- 542 Ahueca Papas — D16B ×1* | PC10 ×1 | PA18 ×1 | G5A ×1 | A9 ×0,083333
- 543 Ahueca Frutas — D16A ×1* | PC10 ×1 | PA18 ×1 | G5B ×1 | A9 ×0,083333
- 570 Pala De Canelones — E6 ×1* | F2 ×1 | V10 ×2 | PC10 ×1 | PA18 ×1 | F2B ×1 | A6 ×0,041667
- 707 Rompenueces — N6C ×1* | B1-M78 ×1 | A8 ×0,083333
- 715 Cierra Bolsa x2 — PC4 ×4* | CART715 ×1 | A1 ×0,041667
- 718 Cuchillito De Untar Plast x2 — PEP9 ×1* | A1 ×0,041667
- 720 Ahueca Papas — D16B ×1* | PA19 ×1 | PB6 ×1 | N2B ×1 | PC6 ×1 | A3 ×0,083333
- 722 Ahueca Frutas — D16A ×1* | PA19 ×1 | PB6 ×1 | N2C ×1 | PC6 ×1 | A3 ×0,083333
- 842 Espátula Lisa Nylon 1 Pza — PV3 ×1* | R2C ×1 | A2 ×0,041667
- 843 Cuchara Calada Nylon 1 Pza — PV6 ×1* | R1B ×1 | A2 ×0,041667
- 844 Cuchara Fideos Nylon 1 Pza — PV5 ×1* | Q3A ×1 | A6 ×0,041667
- 845 Cucharón Nylon 1 Pza — PV2 ×1* | Q3B ×1 | A6 ×0,041667
- 846 Espátula Calada Nylon 1 Pza — PV7 ×1* | R1A ×1 | A2 ×0,041667
- 858 Pala De Canelones Ac. Inox. — E6 ×1* | F2 ×1 | V10 ×2 | PA19 ×1 | PC7 ×1 | O2C ×1 | PC6 ×1 | A2 ×0,083333
- 908 Cuchara Nylon 33 Cm — PB2 ×1* | Q3D ×1 | A7B ×0,083333
- 909 Ñoquera Madera — S2A ×1* | GRJ12 ×1 | A5 ×0,083333
- 941E Espátula Lisa Ac. Inox — PEST1 ×1* | A9B ×0,083333
- 942E Cuchara Ac. Inox — PEST1 ×1* | A9B ×0,083333
- 943E Cucharon Ac. Inox — PEST1 ×1* | A9B ×0,083333
- 944E Cuchara Fideos Ac. Inox — PEST1 ×1* | A9B ×0,083333
- 945E Espatula Calada Ac. Inox — PEST1 ×1* | A9B ×0,083333
- 946E Cuchara Calada Ac. Inox — PEST1 ×1* | A9B ×0,083333
- 948E Espumadera Ac. Inox — PEST1 ×1* | A9B ×0,083333

### Martin Cornejo (30)
- 043 Abrelatas Uña 3 En 1 — C3 ×1* | C10 ×1 | V9 ×2 | V13 ×2 | PA2 ×1 | Q4C ×1 | A8 ×0,083333
- 097 Afila Cuchillos — E3 ×8* | E4 ×0,066667 | V5 ×2 | PEP4 ×1 | T4A ×1 | A1 ×0,166667
- 103 Abrelatas Uña Cromado — A8 ×1* | C10 ×1 | V9 ×1 | H1C ×1 | A11 ×0,083333
- 104 Sacacorchos Mgo Ergonómico Nylon — D1 ×1* | V11 ×1 | PB8A ×1 | K5D ×1 | A9 ×0,083333
- 114 Afila Cuchillos — E3 ×8* | E4 ×0,066667 | V5 ×2 | PEP4 ×1 | H4C ×1 | A1 ×0,166667
- 116 Corta Pizza Familiar — E12 ×1* | Z34 ×1 | LL1 ×1 | PC10 ×1 | PA18 ×1 | V12 ×1 | I2B ×1 | A8 ×0,083333
- 312 Pala De Torta Acero Inox — PA18 ×1* | PA13 ×1 | Z22 ×1 | PA17 ×1 | F3A ×1 | A2 ×0,083333
- 500 Abrelata Uña Pie Color — C1 ×1* | C10 ×1 | V9 ×1 | CART500 ×1 | A9 ×0,083333
- 504 Afila Cuchillos — E3 ×8* | E4 ×0,066667 | V5 ×2 | PEP4 ×1 | C3A ×1 | A1 ×0,166667
- 506 Abrelatas Uña Rojo — A10 ×1* | C10 ×1 | V9 ×1 | CART506 ×1 | A11 ×0,083333
- 508 Sacafuentes Articulado — Z1A ×1* | Z2A ×1 | PC12 ×1 | V6 ×1 | W8 ×1 | V18D ×1 | G2C ×1 | A8 ×0,166667
- 511 Abrelatas Uña 3 En 1 — C4 ×1* | C10 ×1 | V9 ×2 | V13 ×2 | PA1 ×1 | G3B ×1 | A9 ×0,083333
- 520 Sacacorcho Tipo Mozo Cromado — C15 ×1* | D4 ×1 | E15 ×1 | D1 ×1 | D14 ×1 | V2 ×1 | V1 ×1 | V3 ×1 | E2A ×1 | A11 ×0,083333
- 521 Sacacorcho Combinado Cromado — C16 ×1* | D4 ×1 | D1 ×1 | D14 ×1 | V2 ×1 | V1 ×1 | E1A ×1 | A11 ×0,083333
- 530 Sacacorcho Tipo Mozo Color — B4 ×1* | D4 ×1 | E15 ×1 | D1 ×1 | D14 ×1 | V2 ×1 | V1 ×1 | V3 ×1 | E3A ×1 | A11 ×0,083333
- 531 Sacacorcho Combinado Color — B4 ×1* | C8 ×1 | D4 ×1 | D1 ×1 | D14 ×1 | V2 ×1 | V1 ×1 | V3 ×1 | E3B ×1 | A11 ×0,083333
- 559 Corta Ravioles c/Mango Loeke — E12 ×1* | LL1 ×1 | LL2 ×1 | PC10 ×1 | PA18 ×1 | V12 ×1 | F2A ×1 | A8 ×0,083333
- 562 Corta Pizza 6cm Mgo Loeke — E12 ×1* | Z34 ×1 | LL1 ×1 | PC10 ×1 | PA18 ×1 | V12 ×1 | F4A ×1 | A9 ×0,083333
- 564 Corta Pizza 8cm Mgo Madera — E9 ×1* | Z35 ×1 | LL1 ×1 | PEP8 ×1 | V12 ×1 | F4B ×1 | A3 ×0,083333
- 581 Sacacorcho Mango Ergonómico — D1 ×1* | V11 ×1 | CCE2B ×1 | PB8A ×1 | A9 ×0,083333
- 706 Abrelatas Uña — A8 ×1* | C10 ×1 | V9 ×1 | Ñ3C ×1 | A1 ×0,083333
- 708 Sacafuentes Articulado — Z1A ×1* | Z3A ×1 | PC12 ×1 | V6 ×1 | W8 ×1 | V18D ×1 | N4A ×1 | A8 ×0,166667
- 730 Sacacorcho Tipo Mozo Color — B7 ×1* | D4 ×1 | E15 ×1 | D1 ×1 | D14 ×1 | V2 ×1 | V1 ×1 | V3 ×1 | O4A ×1 | A8 ×0,083333
- 731 Sacacorcho Combinado Color — B7 ×1* | C8 ×1 | D4 ×1 | PC8 ×1 | D14 ×1 | V2 ×1 | V1 ×1 | V3 ×1 | T3B ×1 | A8 ×0,083333
- 735 Sacacorcho Cabo Ergonómico — D1 ×1* | V11 ×1 | PB8A ×1 | T3A ×1 | A9 ×0,083333
- 856 Pala De Torta Ac. Inox. — PA19 ×1* | PB6 ×1 | Z22 ×1 | O3D ×1 | A5 ×0,041667
- 857 Cuchillo De Torta Ac. Inox — PA19 ×1* | PB6 ×1 | Z21 ×1 | O3B ×1 | A5 ×0,041667
- 859 Corta Ravioles c/Mango Loeke — E12 ×1* | LL1 ×1 | LL2 ×1 | PA19 ×1 | PC7 ×1 | V12 ×1 | N2A ×1 | A3 ×0,083333
- 862 Corta Pizza Familiar — E12 ×1* | Z34 ×1 | LL1 ×1 | PA19 ×1 | PC7 ×1 | V12 ×1 | N1A ×1 | A9 ×0,083333
- 863 Corta Pizza Gastro. Mgo Chef Ø 8 Cm — E9 ×1* | Z35 ×1 | LL1 ×1 | PEP8 ×1 | PA19 ×1 | PB6 ×1 | V12 ×1 | S1A ×1 | PC6 ×1 | A8 ×0,083333

### Pettofrezza Rafael (17)
- 053 Pinza De Fiambre Inox Cacha Plásticas 23 Cm — F9 ×1* | F10 ×1 | PC8 ×2 | C9 ×1 | O3A ×1 | A2 ×0,083333
- 054 Pinza De Ensalada Inox Cachas Plásticas 23cm — F11 ×2* | PC8 ×2 | C9 ×1 | N3A ×1 | A2 ×0,083333
- 055 Pinza De Fideos Inox Cachas Plásticas 25m Cm — F13 ×1* | F14 ×1 | PC8 ×2 | C9 ×1 | Q2C ×1 | A2 ×0,083333
- 101 Abrelatas A Manija — W6 ×2* | C6 ×1 | Z40 ×1 | Z43 ×1 | W1P ×1 | W2P ×1 | W3P ×1 | W4 ×1 | PA7B ×1 | PB5 ×1 | V7 ×1 | H1A ×1 | A9 ×0,166667
- 315 Pisa Papas Acero Inox — M1 ×1* | PC11 ×1 | PA10 ×1 | F3B ×1 | A2 ×0,083333
- 355 Pisa Papas Nylon con Mgo — PC11 ×1* | PA10 ×1 | PV1 ×1 | F3C ×1 | A6 ×0,041667
- 501 Abrelatas A Manija — W6 ×2* | A4 ×1 | B13 ×1 | C6 ×1 | W1P ×1 | W2P ×1 | W3P ×1 | W4 ×1 | PC14 ×1 | PA12 ×1 | V7 ×1 | D2A ×1 | A9 ×0,166667
- 523 Sacacorcho Doble Aleta — D2 ×1* | D3 ×1 | V8 ×2 | PC15A ×1 | E4A ×1 | A8 ×0,083333 | E13 ×1
- 551 Cuchillo De Untar Mgo Plast x2 — E8 ×2* | PA4 ×2 | L4A ×1 | A9 ×0,083333
- 594 Pinza De Fideos Mgo Plástico 25cm — F13 ×1* | F14 ×1 | PC8 ×2 | C9 ×1 | G4A ×1 | A2 ×0,083333
- 595 Pinza De Fiambre Mgo Plástico 23cm — F9 ×1* | F10 ×1 | PC8 ×2 | C9 ×1 | G4B ×1 | A2 ×0,083333
- 596 Pinza De Ensalada Mgo Plástico 23cm — F11 ×2* | PC8 ×2 | C9 ×1 | G4C ×1 | A2 ×0,083333
- 609 Pisa Papas Ac. Inox. — M1 ×1* | PA19 ×1 | Q5D ×1 | PEST2 ×1 | A2 ×0,083333
- 701 Abrelatas A Manija — W6 ×2* | A7 ×1 | B13 ×1 | C6 ×1 | W1P ×1 | W2P ×1 | W3P ×1 | W4 ×1 | PC13 ×1 | PA7A ×1 | V7 ×1 | N7A ×1 | A3 ×0,166667
- 723 Sacacorcho Doble Aleta Metálico Cuerpo en Nylon Reforzado — D2 ×1* | D3 ×1 | V8 ×2 | PC15B ×1 | Ñ1A ×1 | A3 ×0,083333 | E13 ×1
- 789 Pisa Papas Nylon Con Mgo — PC11 ×1* | PV1 ×1 | R3A ×1 | PEST2 ×1 | A6 ×0,041667
- 878 Cuchillo De Untar Mgo Plast. x2 — E8 ×2* | PA5 ×2 | P3B ×1 | A1 ×0,041667

### Lucho (12)
- 059 Cuchillo de Untar Plástico x2 — PEP9 ×2* | CART059 ×1 | A9 ×0,083333
- 099 Pelapapas Mgo Plástico Ergonómico — Z23A ×1* | PEP1 ×1 | Ñ4A ×1 | D9 ×1 | A1 ×0,083333
- 123 Pelador Mgo Plástico — Z23A ×1* | PC1B ×1 | I42 ×1 | D9 ×1 | A11 ×0,083333
- 186 Pelapapas Mgo Plástico Ergonómico — Z23A ×1* | PEP1 ×1 | D9 ×1 | CART186 ×1 | A1 ×0,083333
- 505 Pelador Mgo Plástico — Z23 ×1* | PC1A ×1 | B3A ×1 | D9 ×1 | A11 ×0,083333
- 518 Sacafuente Pizzero — E10 ×1* | PEP7 ×1 | W8 ×1 | G7B ×1 | A3 ×0,083333
- 519 Cuchillo Untar Mgo Madera x2 — E7 ×2* | W5 ×2 | PEP5 ×2 | G3A ×1 | A9 ×0,083333
- 546 Corta Queso Blandos Mango Loeke — C13 ×1* | PC10 ×1 | PA18 ×1 | CCC4 ×1 | A9 ×0,083333
- 569 Pelanaranjas x 1 Display — G5C ×1* | PV17 ×1 | A11 ×0,083333
- 586 Pelapapas Mgo Ergonomico — Z23A ×1* | PEP3 ×1 | C5A ×1 | D9 ×1 | A9 ×0,083333
- 587 Pelador Metálico Corte Laser — E2 ×1* | Z23B ×1 | PC10 ×1 | PA18 ×1 | C5B ×1 | A8 ×0,083333
- 719 Cuchillo Untar Mgo Madera x2 — E7 ×2* | W5 ×2 | PEP5 ×2 | Ñ3A ×1 | A9 ×0,083333

### Alex Escalante (11)
- 052 Cepillo Lavavajilla — PB8B ×1* | PA19 ×1 | GRJ14 ×1 | Q4A ×1 | A6 ×0,083333
- 307 Cepillo Limpia Vaso y Mamadera — PB8B ×1* | PA19 ×1 | GRJ13 ×1 | S3C ×1 | A9B ×0,041667
- 395 Descorazonador De Manzana — 1686 ×1* | PC10 ×1 | PA18 ×1 | G1A ×1 | A8 ×0,083333
- 506 Abrelatas Uña Rojo — A10 ×1* | C10 ×1 | V9 ×1 | CART506 ×1 | A11 ×0,083333
- 510 Abrelata Uña Cromado — A15 ×1* | C10 ×1 | V9 ×1 | A2B ×1 | A11 ×0,083333
- 515 Batidores — PC10 ×1* | PA13 ×1 | C12 ×1 | A1C1 ×1 | A8 ×0,083333
- 534 Cepillo Lavavajilla — PA13 ×1* | GRJ14 ×1 | PA17 ×1 | Q4B ×1 | A4 ×0,041667
- 535 Cepillo Limpia Vaso y Mamadera — PA13 ×1* | GRJ13 ×1 | PA17 ×1 | K1A ×1 | A9B ×0,041667
- 547 Corta Torta — F6B ×1* | PV8 ×1 | A4 ×0,083333
- 615 Batidores — PB8B ×1* | PA19 ×1 | C12 ×1 | O2A ×1 | A8 ×0,083333
- 818 Corta Torta — PV8B ×1* | O2D ×1 | A4 ×0,083333

### Danica Garcia (11)
- 057 Destapa Corona x1 Cromado — C5 ×1* | Z25A ×1 | G8B ×1 | A11 ×0,083333
- 498 Llavero Destapador Pie Cromado — Z45 ×1* | Z25A ×1 | Z25B ×1 | G8A ×1 | A11 ×0,083333
- 499 Llavero Destapador Pie Color — Z22 ×1* | Z25A ×1 | Z25B ×1 | G8D ×1 | A11 ×0,083333
- 505 Pelador Mgo Plástico — Z23 ×1* | PC1A ×1 | B3A ×1 | D9 ×1 | A11 ×0,083333
- 516 Destapa Corona x1 Cromado Suelto — C5 ×1* | Z25A ×1 | L4B1 ×1 | A9 ×0,01
- 550 Filtro Para Bombillas — BOM13 ×2* | BOM14 ×2 | CCG6B ×1 | BOLSA550 ×1 | A9 ×0,027778
- 590E Pincel Silicona 11 Gms — PINCEL590 ×1* | CART590 ×1 | A11 ×0,083333
- 590ES Pincel Silicona 11 gms s/Cartón — PINCEL590 ×1* | A11 ×0,02
- 700 Destapa Corona x1 Blanco — B8 ×1* | Z25A ×1 | O1B ×1 | A9 ×0,083333
- 760 Filtro de Bombilla — BOM13 ×2* | BOM14 ×2 | CCG6B ×1 | BOLSA760 ×1 | A11 ×0,041667
- 890E Pincel Silicona 11 Gms — PINCEL590 ×1* | CART890 ×1 | A11 ×0,083333

### IJUPA (11)
- 031 Filtro De Café 10cm — A1B ×1* | A9 ×0,041667 | IC3 ×0,0083
- 034 Filtro De Café Gastro 14cm — L4B ×1* | A8 ×0,041667 | IC3V ×0,0134
- 066 Abrelatas Super Mariposa — Z12 ×1* | Z30 ×1 | Z41 ×1 | Z42 ×1 | W7P ×1 | W9P ×1 | PA7B ×1 | PA8B ×1 | V7 ×1 | D4B ×1 | A8 ×0,083333
- 108 Pelapapas Mango Metálico — M7 ×1* | Z23A ×1 | H2C ×1 | D9 ×1 | A9 ×0,083333
- 120 Filtro De Café — A1B1 ×1* | A9 ×0,041667 | IC3 ×0,0083
- 502 Abrelatas Mariposa Cromado — B9 ×1* | B11 ×1 | B13 ×1 | Z12 ×1 | W7P ×1 | W9P ×1 | PA12 ×1 | PA8A ×1 | V7 ×1 | D3A ×1 | A8 ×0,083333
- 512 Abrelatas Mariposa Capuchon Rojo — B11 ×1* | B13 ×1 | Z12 ×1 | Z29 ×1 | W7P ×1 | W9P ×1 | PA12 ×1 | PA8A ×1 | PA9 ×1 | V7 ×1 | D2B ×1 | A8 ×0,083333
- 513 Pelador Mgo Metálico — Z23 ×1* | M5 ×1 | B1A ×1 | D9 ×1 | A9 ×0,083333
- 713 Pelador Mgo Metálico — Z23 ×1* | M7 ×1 | P6A ×1 | D9 ×1 | A1 ×0,083333
- 836 Filtro De Café 10 Cm — G8C ×1* | A9 ×0,041667 | IC3 ×0,0083
- 867 Filtro De Cafe Gastronómico Ø 14 Cm — D5B ×1* | A8 ×0,041667 | IC3V ×0,0134

### Gentile Norberto (10)
- 557 Bombilla Resorte Chata — GRJ6 ×1* | Pliego Ad 557 ×0,0625 | A8 ×0,041667
- 558 Bombilla Resorte Tradicional — GRJ5 ×1* | Pliego Ad 558 ×0,0625 | A8 ×0,041667
- 654 Bombilla Autolimpiante Inox — GRJ4 ×1* | Pliego Ad 654 ×0,0625 | A8 ×0,041667
- 658 Bombilla Plana Ancha Metalizada — GRJ19 ×1* | Pliego Ad 658 ×0,0625 | A8 ×0,041667
- 659 Bombilla Pico de Loro Acero Inox — GRJ18 ×1* | Pliego Ad 659 ×0,0625 | A8 ×0,041667
- 758 Bombilla Plana Ancha Metalizada — GRJ19 ×1* | Pliego Ad 758 ×0,0625 | A8 ×0,041667
- 759 Bombilla Pico de Loro Acero Inox — GRJ18 ×1* | Pliego Ad 759 ×0,0625 | A8 ×0,041667
- 762 Bombilla Resorte Chata — GRJ6 ×1* | Pliego Ad 762 ×0,0625 | A1 ×0,041667
- 763 Bombilla Resorte Tradicional — GRJ5 ×1* | Pliego Ad 763 ×0,0625 | A1 ×0,041667
- 769 Bombilla Autolimpiante Inox — GRJ4 ×1* | Pliego Ad 769 ×0,0625 | A1 ×0,041667

### Carlos Aguirre (7)
- 115 Batidor Pera — GRJ10 ×1* | I2A ×1 | A5 ×0,083333
- 544 Batidor Pera Alambre — GRJ10 ×1* | C1A ×1 | A2 ×0,083333
- 560 Pinza Corta Alambre 21cm — N7 ×1* | G3C ×1 | CV14 ×1 | A8 ×0,083333
- 580 Batidor Mini — GRJ10A ×1* | G7A ×1 | A11 ×0,083333
- 709 Descorazonador De Manzana — 1686 ×1* | PA19 ×1 | PB6 ×1 | A8 ×0,083333
- 800 Pinza Corta Alambre 21 Cm — N7 ×1* | O5A ×1 | CV14 ×1 | A8 ×0,083333
- 802 Batidor Pera Alambre — GRJ10 ×1* | P4A ×1 | A2 ×0,083333

### Blist-Pack SA (2)
- 555 Cepillo Limpia Bombilla — GRJ28 ×1* | A8 ×0,027778
- 764 Cepillo Limpia Bombilla — GRJ29 ×1* | A1 ×0,027778

### Cavallero German (1)
- 121 Pisa Papas Inox. — M1 ×1* | PA10B ×1 | PC11 ×1 | I3C ×1 | A3 ×0,083333

## 3. Cervantes — partes armadas / semi-elaborados (9 casos)

Lo que vuelve a un sector (no terminados). `consumo_tall` desde la ubicación del tallerista.

| Tallerista | Devuelve | Sector | Se le descuenta |
|---|---|---|---|
| Alex Escalante | C12B | Bombilla | BOM10 ×1 · IE1 ×1 · W1B ×1 |
| Alex Escalante | GRJ10 | Garage | IE4 ×3 · IE5 ×1 · LL7B ×1 · LLF8 ×1 |
| Alex Escalante | GRJ10A | Garage | ABPM ×1 · EP10 ×1 · IE4 ×3 · IE5 ×1 |
| IJUPA | M6 | Crudo | M10 ×1 (transformación 1:1) |
| IJUPA | M8 | Crudo | M9 ×1 (transformación 1:1) |
| Lucho | J1 | Crudo | F7 ×1 (transformación 1:1) |
| Martin Cornejo | GRJ5 | Garage | BOM12 ×1 · BOM8 ×1 |
| Martin Cornejo | GRJ6 | Garage | BOM12 ×1 · BOM8 ×1 |
| Martin Cornejo | X4 | Crudo | X1 ×1 (transformación 1:1) |

Los GRJ que consumen los artículos de la sección 2 (GRJ4, GRJ12, GRJ13, GRJ14, GRJ17…GRJ30) NO figuran acá: se descuentan directamente en la entrega del terminado en Virgilio, sin pasar por una entrega de parte en Cervantes.
## 4. Lo que hay que mirar antes de confiar en esto en producción

1. **`GP2.movimiento` está en 0 filas y las 1.324 filas de `inventario` están todas en cantidad 0.** Este despiece es lo que la configuración VA a descontar, no lo que descontó.
2. **389 de los 404 pares (tallerista, componente a descontar) no tienen fila de inventario en la ubicación del tallerista** — los 15 cargados son todos de Carlos Aguirre. Al primer registro real, esos descuentos arrancan de la nada: cajas, cartones y pliegos incluidos.
3. **La pantalla de Virgilio está apagada** (candado en `GP2_MODULOS.html` desde el 18/09), así que hoy la puerta de la sección 2 no se usa desde el menú.
4. **Bug latente ya comentado en `gp2-motor.js:313-318`**: en la cascada del BOM, la línea principal sólo multiplica por su cantidad si `q > 0` — con un BOM de `q` fraccionario (una entrada que rinde dos salidas, q = 0,5) el consumo de esa entrada saldría al doble. Hoy no muerde porque el único caso ≠ 1 es GRJ10/GRJ10A → IE4 ×3.
5. **`GP2.componente` tiene códigos repetidos**: `A4`, `A8`, `Z22` y `M1` son DOS componentes distintos cada uno (A8 es la Caja N°2 y también el Cuerpo Uña CH Serigr.; M1 es el Disco Inox y también el Cartón 220). Acá cada línea es la que realmente usa esa receta, pero un despiece leído por código, fuera de este archivo, puede confundir una caja con una pieza.
6. **La base se mueve mientras se lee.** Entre las 17:44 y las 18:20 del 21/09 el componente del Afila Cuchillos pasó de `K9` a `E3` y cambió de sector, y con eso cambió cuál es el principal de los artículos 097, 114 y 504 (de `E4 ×0,07` a `E3 ×8`). No fue un misterio: es la tanda de correcciones de la entrada (4) del `[HISTORIAL]` de `LOCKS.txt` de ese mismo día, hecha en otra sesión en paralelo — la misma que pasó el 070 a Fábrica y creó `ROLLOETIQ`. **La foto de este archivo es de las 18:20**; un despiece se re-verifica contra la base antes de entregarlo, no se copia de una consulta de hace media hora. Mismo día, más tarde, el dueño **dio de baja `ROLLOETIQ`** (y su proveedor Sumatik) porque las etiquetas no se evalúan por ahora: el 070 y el 071 ya salen **sin** esa línea, y este archivo quedó corregido — ver `CONOCIMIENTO_GP2.md` §4eq (e).
