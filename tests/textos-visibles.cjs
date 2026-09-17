/* v19.38 (Luis, 2026-09-17) — LOS TEXTOS QUE VE EL USUARIO SE ESCRIBEN EN CASTELLANO NEUTRO.

   Lo pidió Luis con una captura del pop-up de cancelar, que decía
   *"Buscando qué se lleva puesto cancelar 98507…"*:
   ***"la gramática. «Que se lleva puesto» no es muy profesional"***.

   El problema no fue ese cartel suelto: fue que la MISMA jerga estaba en tres módulos distintos
   (cancelar en la PPP, anular en Cuarentena, cancelar en Facturación), porque cada uno se
   escribió copiando al anterior. Este test corta esa cadena.

   ⚠ Mira SÓLO texto visible: `innerHTML`, `title=`, `alert(`, `confirm(`, `placeholder`,
   `textContent`, mensajes de estado y de error. Los COMENTARIOS del código quedan afuera a
   propósito — ahí la voz coloquial explica mejor y no la lee ningún operario.

   Si este test se pone en rojo, la respuesta NO es agregar la frase a la lista blanca: es
   reescribir el texto. La lista de abajo son formas que ya llegaron a la pantalla una vez.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const ARCHIVOS = ["index.html", "recepcion.js", "planimetria.js", "monitor/tv.html"];

/* Cada entrada: qué no va, y con qué se reemplaza. El "cómo" importa más que el "no": sin la
   sugerencia, el que lo lea mañana no sabe qué se espera en su lugar. */
const PROHIBIDO = [
  [/se lleva puesto/i,                 "decí QUÉ se busca o qué se mueve: «Buscando el pedido X y su mercadería…»"],
  [/va a explicar esto mañana/i,       "«queda guardado con tu nombre»"],
  [/el pedido murió/i,                 "«el pedido no se entrega»"],
  [/\badentro de (una|la|el|un)\b/i,   "«dentro de»"],
  [/\bal pedo\b/i,                     "«de más», «sin sentido»"],
  [/\bquilombo\b/i,                    "«lío», «problema»"],
  [/\bun bardo\b/i,                    "«un problema»"],
  [/\bcagam?os\b/i,                    "escribilo sin puteada"],
  [/\bla concha\b/i,                   "escribilo sin puteada"],
  [/\bboludez\b/i,                     "«un detalle», «algo menor»"],
  [/\bchamuy\w*/i,                     "decí qué pasa de verdad"],
  [/\bre (bien|mal|rápido|lento)\b/i,  "sin el «re»"]
];

/* Una línea produce texto visible si arma HTML, un aviso o un mensaje de estado. */
const VISIBLE = /innerHTML|outerHTML|\btitle="|\btitle='|alert\(|confirm\(|placeholder|textContent|\.err\s*=|_msg\s*=|setStatus\(|SetStatus\(|showToast\(|ShowToast\(|<div|<span|<button|<b>|<p>/;

const fallas = [];
for (const rel of ARCHIVOS) {
  const abs = path.join(__dirname, "..", rel);
  if (!fs.existsSync(abs)) continue;
  // latin1: `index.html` tiene un byte NUL adentro y leerlo como texto "limpio" se lo come.
  const lineas = fs.readFileSync(abs, "latin1").split("\n");
  lineas.forEach((l, i) => {
    const t = l.trim();
    if (/^(\/\/|\/\*|\*|--|#)/.test(t)) return;          // comentario: no lo ve nadie
    if (!VISIBLE.test(l)) return;                        // no es texto de pantalla
    for (const [re, sug] of PROHIBIDO) {
      const m = l.match(re);
      if (m) fallas.push(rel + ":" + (i + 1) + "  «" + m[0] + "» → " + sug + "\n      " + t.slice(0, 120));
    }
  });
}

if (fallas.length) {
  console.log("textos-visibles: ✗ FAIL — " + fallas.length + " texto(s) que ve el usuario con jerga:\n  - " +
              fallas.join("\n  - ") +
              "\n\n  Reescribilos. Agregarlos a la lista blanca no es el arreglo.");
  process.exit(1);
}
console.log("textos-visibles: ✓ OK (" + ARCHIVOS.length + " archivos, " + PROHIBIDO.length + " formas vigiladas)");
