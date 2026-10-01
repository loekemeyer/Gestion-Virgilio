// v25.43 (Luis): tocar «⏰ N sin respuesta» en Clientes nuevos tiene que MOSTRAR los vencidos,
// no plegar el cuadro (el chip vivía dentro del título plegable y heredaba su onclick).
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const fails = [];
const i = src.indexOf("function pipeHtml()");
const cuerpo = src.slice(i, src.indexOf("\nfunction ", i + 20));
if (!/pipe-badge-venc[^\n]*\n[^\n]*event\.stopPropagation\(\);pipeSoloVencToggle\(\)/.test(cuerpo))
  fails.push("el chip no frena el click del título o no llama a pipeSoloVencToggle");
if (!/_apr\.pipeSoloVenc\s*\n?\s*\? pipeLista\(\)\.filter/.test(cuerpo))
  fails.push("la tabla no se filtra a los vencidos");
const t = src.indexOf("function pipeSoloVencToggle()");
if (t < 0) fails.push("falta pipeSoloVencToggle");
else {
  const f = src.slice(t, src.indexOf("\n}", t));
  if (!/aprSetColapsado\("vir_cli_colapsado", false\)/.test(f)) fails.push("no despliega el cuadro plegado");
  if (!/aprRender\(\)/.test(f)) fails.push("no redibuja");
}
if (fails.length) { console.error("pipe-sin-respuesta-filtra: FALLA\n - " + fails.join("\n - ")); process.exit(1); }
console.log("pipe-sin-respuesta-filtra: OK");
