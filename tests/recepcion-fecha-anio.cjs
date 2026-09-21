/* v20.58 — la fecha que graba la Recepción lleva AÑO, y sin fecha no se graba.

   Qué pasó (21/09/2026, pedido de Elías): `opEnviar` de recepcion.js armaba el `Dia_mes`
   de "Entregas Prov AT" partiendo la fecha ISO y quedándose sólo con día y mes:

       const diaMes = (partes.length === 3) ? (partes[2] + "-" + partes[1]) : "";

   O sea que el año se tiraba SIEMPRE: el 100 % de esa tabla nacía sin año, y las 121 filas
   que hoy lo tienen se lo puso alguien a mano entre el 25 y el 31/08. De las 41 que habían
   quedado sin datar, 37 se pudieron recuperar leyendo Fecha_RTO / Fecha_Factura de la misma
   fila; las 4 de Pintos remito 0438 no tenían ninguna de las dos y hubo que preguntarlas.

   Y el mismo renglón, con `opState.fecha` vacío, escribía `Dia_mes = ""`: una entrega sin
   fecha entraba sin que nada avisara.

   Dos candados, entonces:
   1. el `Dia_mes` se arma con `partes[0]` (el año) adentro;
   2. `opEnviar` corta si la fecha no es una ISO válida.

   El centinela del lado de la base es `public.gv_fechas_carga_invalidas` (vacía = todo bien).

   Ojo: la rama del `else` (Entregas Tallerista Virgilio) guarda `Fecha: opState.fecha`
   entera y nunca tuvo el problema. */
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");
const fallos = [];

/* 1. El diaMes de Prov AT tiene que llevar el año */
const mDiaMes = src.match(/const diaMes = \(partes\.length === 3\)([\s\S]{0,160}?);/);
if (!mDiaMes) {
  fallos.push("no encontré la línea que arma `diaMes` en recepcion.js (¿se renombró?)");
} else {
  const cuerpo = mDiaMes[1];
  if (!/partes\[0\]/.test(cuerpo)) {
    fallos.push(
      "`diaMes` se arma SIN el año (falta partes[0]): vuelve el bug de las 41 filas sin datar.\n" +
      "    " + cuerpo.replace(/\s+/g, " ").trim()
    );
  }
  if (/partes\[2\]\s*\+\s*"-"\s*\+\s*partes\[1\]/.test(cuerpo)) {
    fallos.push("`diaMes` volvió al formato viejo dd-mm; tiene que ser dd/mm/aa");
  }
}

/* 2. Sin fecha no se graba */
const mEnviar = src.match(/async function opEnviar\(\)[\s\S]*?\n\}/);
if (!mEnviar) {
  fallos.push("no encontré la función opEnviar en recepcion.js");
} else if (!/\\d\{4\}-\\d\{2\}-\\d\{2\}[\s\S]{0,200}?opState\.fecha/.test(mEnviar[0])) {
  fallos.push("opEnviar ya no valida `opState.fecha`: una entrega puede entrar sin fecha");
}

if (fallos.length) {
  console.log("recepcion-fecha-anio: FALLA");
  fallos.forEach(f => console.log("  - " + f));
  process.exit(1);
}
console.log("recepcion-fecha-anio: OK — la fecha se graba con año y sin fecha no se graba");
