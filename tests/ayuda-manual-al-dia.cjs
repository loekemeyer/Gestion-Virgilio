/* v29.19 (Luis, 09/10/2026: «vamos a tener que poner algo que ajuste el manual en base a los
   cambios que se hicieron»). El manual del operario (ayuda/manual-operario.md) es lo único que sabe
   el asistente de ayuda: si la app cambia y el manual no, el asistente explica una pantalla que ya
   no existe. Este test se pone ROJO cuando se desfasan:
   (a) cada botón de la botonera (const filas + 🔀 Mover + PPP) está nombrado en el manual;
   (b) cada rótulo que el manual cita entre «…» existe en el código (index.html / recepcion.js):
       si alguien renombra o saca un botón, el manual queda viejo y esto falla;
   (c) manual.ts (lo que se empaqueta en gv-ayuda) = el .md.
   Al cambiar un botón o un rótulo de la botonera: actualizar el manual en el MISMO commit y correr
   node scripts/ayuda-manual-build.cjs. Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const ROOT = path.join(__dirname, "..");
let fallas = 0;
const ok = (c, m) => { if (c) console.log("  ✓ " + m); else { console.log("  ✗ " + m); fallas++; } };
const md = fs.readFileSync(path.join(ROOT, "ayuda/manual-operario.md"), "utf8");
const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
const src = html + "\n" + fs.readFileSync(path.join(ROOT, "recepcion.js"), "utf8");
const norm = (s) => s.replace(/\s+/g, " ");
const srcN = norm(src), mdN = norm(md);

// (a) botonera
const f = html.match(/const filas = \{([\s\S]*?)\n\};/);
ok(!!f, "(a) encuentro const filas");
const codigos = f ? [...f[1].matchAll(/"([A-Za-z]+)"/g)].map((m) => m[1]) : [];
const TITULO = { RKBM: "BR", INS: "📦", MOV: "🔀" };   // los que en la botonera se ven con otro rótulo
for (const c of codigos.concat(["MOV", "PPP"])) {
  const t = TITULO[c] || c;
  ok(new RegExp("\\*\\*" + t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\*\\*").test(md), "(a) el manual nombra **" + t + "** (" + c + ")");
}

// (b) rótulos citados
// Los que el código arma por partes (string concatenado): se verifica cada parte.
const PARTES = {
  "⛔ La tanda X ya la está pickeando…": ["⛔ La tanda ", " ya la está "],
  "Tanda … (pickeado)": [" (pickeado)"],
  "📦 Lo que llegó (a guardar)": ["📦 Lo que llegó"],
  "📦 Del excedente (lo que no entró)": ["📦 Del excedente"],
  "✕ Anular recepción de insumos": ["✕ Anular ' + (isIn ? \"recepción\" : \"entrega\") + ' de insumos"],
  "✕ Anular entrega de insumos": ["✕ Anular ' + (isIn ? \"recepción\" : \"entrega\") + ' de insumos"],
};
const rotulos = [...new Set([...mdN.matchAll(/«([^»]+)»/g)].map((m) => m[1].trim()))];
ok(rotulos.length >= 40, "(b) el manual cita " + rotulos.length + " rótulos");
const faltan = [];
for (const r of rotulos) {
  const partes = PARTES[r] || r.replace(/…/g, "").split(/\b[NX]\b/).map((s) => s.trim()).filter((s) => s.length >= 3);
  if (!partes.every((p) => srcN.includes(norm(p)))) faltan.push(r);
}
ok(!faltan.length, "(b) todos los rótulos del manual existen en la app" + (faltan.length ? " — FALTAN: " + faltan.join(" | ") : ""));

// (c)
const mts = fs.readFileSync(path.join(ROOT, "supabase/functions/gv-ayuda/manual.ts"), "utf8");
const m = mts.match(/export const MANUAL = (".*");\s*$/s);
ok(m && JSON.parse(m[1]) === md, "(c) manual.ts = el .md (correr scripts/ayuda-manual-build.cjs)");

process.exit(fallas ? 1 : 0);
