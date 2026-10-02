#!/usr/bin/env node
// Candado de la regla del armado automatico (Luis, 2026-10-01 / 02): maximo 5 NP por tanda,
// una sola gondola (LK o CH), el cliente con mas de 5 NP va entero, y es forward-facing.
// Luis pidio que quede "bien grande" arriba del CLAUDE.md para que no se olvide: este test
// falla si el bloque se borra, se diluye o queda enterrado, y si el codigo pierde las piezas.
const fs = require("fs");
const path = require("path");
const raiz = path.join(__dirname, "..");
const leer = (f) => fs.readFileSync(path.join(raiz, f), "latin1");
const md = fs.readFileSync(path.join(raiz, "CLAUDE.md"), "utf8");

const exigidos = [
  ["el titulo del bloque",      "ARMADO AUTOMÁTICO: MÁXIMO 5 NP POR TANDA · UNA SOLA GÓNDOLA"],
  ["el tope de 5",              "EL ARMADO AUTOMÁTICO NO ARMA UNA TANDA CON MÁS DE 5 NP."],
  ["una sola gondola",          "TODO LK O TODO CH, NUNCA MEZCLADO."],
  ["cliente con +5 va entero",  "UN CLIENTE O PEDIDO CON MÁS DE 5 NP VA ENTERO: NO SE PARTE."],
  ["forward-facing",            "LO YA ARMADO QUEDA COMO ESTÁ. NO SE PARTE NI SE REPORTA."],
  ["la cita de Luis",           "es forward-facing para el armado automático la regla"],
  ["la clave de config",        "tanda_max_nps"],
  ["el boton",                  "Modificar tanda"],
];
const fallas = exigidos.filter(([, txt]) => !md.includes(txt)).map(([q, t]) => `CLAUDE.md sin ${q} (buscaba: ${t})`);

const pos = md.indexOf("ARMADO AUTOMÁTICO: MÁXIMO 5 NP POR TANDA");
if (pos > 15000) fallas.push(`el bloque quedo en el caracter ${pos}; va arriba de todo`);

// Las piezas de codigo que la regla nombra tienen que seguir existiendo.
const sql = leer("sql/gv_armado_tope5_gondola_v2577.sql");
if (!/tanda_max_nps/.test(sql) || !/o\.gondola = r_cli\.gondola/.test(sql)) fallas.push("el SQL del armador perdio el tope o la gondola");
const edge = leer("supabase/functions/gv-ppp-web-tandas-diarias/index.ts");
if (!/function gondolaDe\(/.test(edge) || !/gondola:\s*gondolaDe\(/.test(edge)) fallas.push("la Edge Function no manda la gondola de cada NP");
const idx = leer("index.html");
if (!/pgaTandaModificarAbrir\(/.test(idx) || !/function pgaTandaPartirAbrir\(/.test(idx)) fallas.push("index.html perdio «Modificar tanda» / «Partir tanda»");

if (fallas.length) {
  console.error("regla-armado-tope5: FALLA");
  fallas.forEach((f) => console.error("  - " + f));
  process.exit(1);
}
console.log("regla-armado-tope5: OK — la regla esta arriba del CLAUDE.md y las piezas de codigo existen.");
