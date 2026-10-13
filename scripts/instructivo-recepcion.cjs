/* Arma el instructivo gráfico de RECEPCIÓN DE MERCADERÍA (tallerista) en una hoja de
   40 × 50 cm: HTML autocontenido (capturas embebidas en base64) + PDF listo para imprimir.

   Las capturas son REALES: salen de correr la app con Playwright
   (docs/instructivos/caps-recepcion/_generar-capturas*.cjs). Si cambia una pantalla:
     node docs/instructivos/caps-recepcion/_generar-capturas.cjs
     node docs/instructivos/caps-recepcion/_generar-capturas-botonera.cjs
     node scripts/instructivo-recepcion.cjs
   Salida: docs/instructivos/recepcion-tallerista.html y .pdf  */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { ({ chromium } = require("playwright")); }

const ROOT = path.join(__dirname, "..");
const CAPS = path.join(ROOT, "docs/instructivos/caps-recepcion");
const OUT  = path.join(ROOT, "docs/instructivos");

const img = (f) => "data:image/png;base64," + fs.readFileSync(path.join(CAPS, f)).toString("base64");

const PASOS = [
  { n: 1,  img: "00b-botonera-rt.png", t: "Tocá RT y Enviar",
    d: "El primer toque <b>selecciona</b>. <b>Enviar</b> arranca. Queda con borde rojo: la tarea está abierta." },
  { n: 2,  img: "01-tipo.png",         t: "¿Qué vas a cargar?",
    d: "<b>Talleristas</b> o <b>Prov. Art. Terminado</b>." },
  { n: 3,  img: "02-lista.png",        t: "Elegí quién entrega",
    d: "Buscá por nombre. Es <b>el que trae la mercadería</b>." },
  { n: 4,  img: "03-linea.png",        t: "Fecha y línea",
    d: "La fecha es la de hoy. <b>LK = Loeke · CH = Chef.</b> Gris = ese tallerista no trabaja para esa empresa." },
  { n: 5,  img: "04-doc.png",          t: "¿Qué documentación recibís?",
    d: "Lo que te deja en la mano: <b>Remito</b>, <b>Factura</b> o los dos." },
  { n: 6,  img: "05-remito.png",       t: "Número y fecha del papel",
    d: "Copiá el número <b>tal cual</b>. Sin eso, <b>Continuar</b> no se prende." },
  { n: 7,  img: "06-codigos.png",      t: "Los códigos del proveedor",
    d: "<b>OC 120</b> = lo que falta que entregue. ¿El código no está? <b>Introducir código diferente</b>." },
  { n: 8,  img: "07-cajas.png",        t: "Cuántas cajas",
    d: "Contá y tipeá. <b>Siguiente</b>. Para corregir: tocá el código otra vez y <b>Quitar</b>." },
  { n: 9,  img: "08-cargados.png",     t: "Lo cargado queda en verde",
    d: "Repetí con cada código. <b>Enviar</b> dice cuántos llevás." },
  { n: 10, img: "09-resumen.png",      t: "Revisá y sacá la foto",
    d: "Mirá que los números sean los que contaste. <b>Sin foto no se puede enviar.</b>" },
  { n: 11, img: "10-resumen-foto.png", t: "Confirmar y enviar",
    d: "Las cajas entran a <b>A guardar</b>. A la góndola van después, con <b>MG</b>." },
  { n: 12, img: "11-exceso.png",       t: "Si entró más que la OC",
    d: "Antes de enviar: <b>Enviar WhatsApp a Thomas</b>. Recién ahí se habilita Confirmar." }
];

const OJO = [
  ["RT queda ABIERTO", "Para cerrarlo: <b>RT</b> otra vez y <b>Enviar</b>. Abierto no deja empezar picking ni armado."],
  ["¿Entraste por error?", "Botón rojo de abajo: <b>✕ Anular recepción</b>."],
  ["Te fuiste por la mitad", "En la botonera sale <b>▶ Seguir recepción</b>. Volvés al mismo paso."],
  ["No está en góndola", "Queda en <b>A guardar</b>. Se guarda con <b>MG</b>."]
];

const tarjeta = (p) => `
  <div class="paso">
    <div class="cab"><span class="num">${p.n}</span><span class="tit">${p.t}</span></div>
    <img src="${img(p.img)}" alt="paso ${p.n}">
    <div class="dsc">${p.d}</div>
  </div>`;

const htmlCon = (COLS, anchos) => `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>Recepción de mercadería — tallerista</title>
<style>
  @page { size: 400mm 500mm; margin: 0; }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body { width: 400mm; height: 500mm; padding: 10mm 9mm 8mm;
         font-family: "Segoe UI", system-ui, -apple-system, Roboto, sans-serif; color: #0f172a;
         background: #fff; display: flex; flex-direction: column; }
  header { display: flex; align-items: flex-end; gap: 8mm; border-bottom: 1.6mm solid #0f172a;
           padding-bottom: 3mm; margin-bottom: 4mm; }
  h1 { font-size: 17mm; line-height: .95; margin: 0; letter-spacing: -.4mm; font-weight: 900; }
  h1 small { display: block; font-size: 6.4mm; font-weight: 800; color: #475569; letter-spacing: 0;
             margin-top: 1.6mm; }
  .marca { margin-left: auto; text-align: right; font-size: 4.6mm; font-weight: 800; color: #475569;
           line-height: 1.35; }
  .marca b { display: block; font-size: 6.2mm; color: #0f172a; }
  .grilla { display: grid; grid-template-columns: var(--cols, repeat(5, 1fr)); gap: 4.5mm; flex: 1; align-items: stretch; }
  .col { display: flex; flex-direction: column; gap: 6.2mm; }
  .paso { break-inside: avoid; }
  .cab { display: flex; align-items: center; gap: 2.2mm; margin-bottom: 1.6mm; }
  .num { flex: none; width: 10.4mm; height: 10.4mm; border-radius: 50%; background: #0f172a; color: #fff;
         font-size: 6.6mm; font-weight: 900; display: flex; align-items: center; justify-content: center; }
  .tit { font-size: 7mm; font-weight: 900; line-height: 1.08; }
  .paso img { display: block; width: 100%; border: .45mm solid #cbd5e1; border-radius: 2mm; }
  .dsc { font-size: 5.85mm; line-height: 1.26; color: #334155; margin-top: 1.4mm; }
  .dsc b { color: #0f172a; }
  footer { margin-top: 4mm; border-top: 1.2mm solid #0f172a; padding-top: 3mm;
           display: grid; grid-template-columns: repeat(4, 1fr); gap: 5mm; }
  .ojo b.h { display: block; font-size: 5.8mm; font-weight: 900; margin-bottom: 1mm; }
  .ojo { font-size: 5.1mm; line-height: 1.3; color: #334155; border-left: 1.2mm solid #dc2626; padding-left: 2.6mm; }
  .pie { margin-top: 2.5mm; font-size: 3.6mm; color: #64748b; text-align: right; }
</style></head>
<body style="${anchos ? "--cols:" + anchos.map(a => a.toFixed(3) + "fr").join(" ") : ""}">
  <header>
    <h1>RECEPCIÓN DE MERCADERÍA<small>Paso a paso en el celular — ejemplo: entrega de un tallerista</small></h1>
    <div class="marca"><b>Gestión Virgilio</b>Botón <b style="display:inline">RT</b> · Recepción Mercadería</div>
  </header>
  <div class="grilla">${COLS.map(col => '<div class="col">' + col.map(n => tarjeta(PASOS[n - 1])).join("") + '</div>').join("")}</div>
  <footer>${OJO.map(([h, t]) => `<div class="ojo"><b class="h">${h}</b>${t}</div>`).join("")}</footer>
  <div class="pie">Las pantallas son las de la app de verdad. Si no coincide con lo que ves en el celular, avisá al supervisor.</div>
</body></html>`;

/* Reparte los 12 pasos en 5 columnas CONSECUTIVAS de la altura más pareja posible
   (partición lineal por DP): sin eso quedan huecos muertos al pie de media hoja. */
function repartir(alturas, nCols, gap) {
  const n = alturas.length, INF = Infinity;
  const best = Array.from({ length: n + 1 }, () => new Array(nCols + 1).fill(INF));
  const corte = Array.from({ length: n + 1 }, () => new Array(nCols + 1).fill(0));
  best[0][0] = 0;
  for (let c = 1; c <= nCols; c++) {
    for (let i = 1; i <= n; i++) {
      for (let k = c - 1; k < i; k++) {
        if (best[k][c - 1] === INF) continue;
        let h = 0; for (let j = k; j < i; j++) h += alturas[j] + (j > k ? gap : 0);
        const v = Math.max(best[k][c - 1], h);
        if (v < best[i][c]) { best[i][c] = v; corte[i][c] = k; }
      }
    }
  }
  const cols = []; let i = n;
  for (let c = nCols; c >= 1; c--) { const k = corte[i][c]; cols.unshift(Array.from({ length: i - k }, (_, j) => k + j + 1)); i = k; }
  return cols;
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();

  // 1) medir cada tarjeta al ancho real de columna
  const COLS0 = [[1,2,3],[4,5,6],[7,8],[9,10],[11,12]];
  await p.setContent(htmlCon(COLS0), { waitUntil: "load" });
  const med = await p.evaluate(() => {
    const g = document.querySelector(".grilla");
    const gap = parseFloat(getComputedStyle(g).rowGap) || 0;
    const alt = [].map.call(document.querySelectorAll(".paso"), e => e.getBoundingClientRect().height);
    return { alt, gap, libre: g.getBoundingClientRect().height };
  });
  const COLS = repartir(med.alt, 5, med.gap);

  /* 2) anchos por columna: la que sobra espacio se ensancha (sus capturas se ven más
        grandes) y la que se pasa se angosta, hasta que las 5 terminan parejas. Sin esto
        quedan hasta 8 cm de hoja en blanco al pie de media hoja. */
  let anchos = [1, 1, 1, 1, 1];
  let medidas = null;
  for (let it = 0; it < 14; it++) {
    await p.setContent(htmlCon(COLS, anchos), { waitUntil: "load" });
    medidas = await p.evaluate(() => {
      const g = document.querySelector(".grilla");
      const gapCol = parseFloat(getComputedStyle(document.querySelector(".col")).rowGap) || 0;
      return { libre: g.getBoundingClientRect().height,
               alt: [].map.call(document.querySelectorAll(".col"), c => {
                 const ps = c.querySelectorAll(".paso"); let h = (ps.length - 1) * gapCol;
                 ps.forEach(e => { h += e.getBoundingClientRect().height; }); return h; }) };
    });
    const obj = medidas.alt.reduce((a, b) => a + b, 0) / 5;
    anchos = anchos.map((w, i) => w * Math.pow(obj / medidas.alt[i], 0.55));
    const sum = anchos.reduce((a, b) => a + b, 0);
    anchos = anchos.map(w => w * 5 / sum);
  }
  const html = htmlCon(COLS, anchos);
  fs.writeFileSync(path.join(OUT, "recepcion-tallerista.html"), html);
  await p.setContent(html, { waitUntil: "load" });
  const sob = await p.evaluate(() => {
    const H = document.querySelector(".grilla").getBoundingClientRect().height;
    const gapCol = parseFloat(getComputedStyle(document.querySelector(".col")).rowGap) || 0;
    return [].map.call(document.querySelectorAll(".col"), c => {
      const ps = c.querySelectorAll(".paso"); let h = (ps.length - 1) * gapCol;
      ps.forEach(e => { h += e.getBoundingClientRect().height; });
      return Math.round((H - h) / 1512 * 400); });
  });
  console.log("columnas:", COLS.map(c => c.join("-")).join(" | "));
  console.log("sobra por columna (mm):", sob.join(", "), "· anchos:", anchos.map(a => a.toFixed(2)).join(" "));
  await p.pdf({ path: path.join(OUT, "recepcion-tallerista.pdf"),
                width: "400mm", height: "500mm", printBackground: true,
                margin: { top: "0", right: "0", bottom: "0", left: "0" } });
  await b.close();
  const st = fs.statSync(path.join(OUT, "recepcion-tallerista.pdf"));
  const pags = (fs.readFileSync(path.join(OUT, "recepcion-tallerista.pdf"), "latin1").match(/\/Type\s*\/Page[^s]/g) || []).length;
  console.log("PDF listo:", Math.round(st.size / 1024) + " KB ·", pags, "página(s)");
})();
