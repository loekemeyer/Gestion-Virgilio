/* v29.83 — EL SISTEMA DE DISEÑO «GV-UI» (Luis, 13/10/2026).
   "quiero que agarremos una filosofía de diseño visual / front / usabilidad moderna y que
    cortemos con la basura... Deberíamos hacer un agente o .md o algo para que cuando se genere
    un módulo nuevo, haga un pase para dejar establecidas las normas de estética y diseño."

   Este test es el candado del SISTEMA, no de una pantalla. Mide:
     (a) las piezas existen y se cargan: gv-ui.css está linkeado en index.html, con ?v= de la app,
         y están docs/GV-UI.md y el agente del pase;
     (b) la paleta de gv-ui.css CUMPLE: cada color de TEXTO llega a 4,5:1 contra el fondo de la
         app, calculado acá con la fórmula WCAG 2.x (no copiado de ninguna tabla);
     (c) la escala está completa y es la escrita (11·12·14·16·20·30·46) y el espaciado base 4;
     (d) el módulo de referencia (analisis.js) USA el sistema: cero font-size propios, cero hex
         propios y su overlay entra con la clase .gv;
     (e) no hay token muerto: todo --gv-* declarado se usa en gv-ui.css o en analisis.js;
     (f) ningún token de color de texto cae en la zona prohibida (el ámbar #d97706 y el amarillo
         pleno como texto, que miden 2,97 y 1,57).

   Al escribir un módulo nuevo: pasalo por el agente `disenador-gvui` y copiale a su test el
   bloque (g) de tests/analisis-productivo.cjs. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const lee = (f, enc) => fs.readFileSync(path.join(root, f), enc || "utf8");

const fallos = [];
const ok = (c, m) => { if (!c) fallos.push(m); };

/* ── contraste WCAG 2.x, calculado acá ───────────────────────────────────────── */
function lum(h) {
  h = h.replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const c = [0, 2, 4].map((i) => parseInt(h.substr(i, 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
function ratio(a, b) {
  const x = lum(a), y = lum(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

/* ── (a) las piezas ──────────────────────────────────────────────────────────── */
ok(fs.existsSync(path.join(root, "gv-ui.css")), "(a) falta gv-ui.css: es la FUENTE del sistema");
ok(fs.existsSync(path.join(root, "docs/GV-UI.md")), "(a) falta docs/GV-UI.md: de dónde sale cada número");
ok(fs.existsSync(path.join(root, ".claude/agents/disenador-gvui.md")),
   "(a) falta el agente del pase (.claude/agents/disenador-gvui.md)");

const idx = lee("index.html", "latin1");   // latin1: el index tiene un byte NUL adentro
const mLink = idx.match(/href\s*=\s*["']gv-ui\.css\?v=([^"']+)["']/);
ok(!!mLink, "(a) gv-ui.css no está linkeado con ?v= en index.html: ninguna pantalla lo ve");
const mApp = idx.match(/APP_VERSION\s*=\s*["']v?([0-9][0-9.]*)["']/);
ok(!mLink || !mApp || mLink[1] === mApp[1],
   "(a) gv-ui.css?v=" + (mLink && mLink[1]) + " quedó atrás de APP_VERSION=" + (mApp && mApp[1]) +
   " — el celular se queda con los tokens viejos");

const css = lee("gv-ui.css");
const doc = lee("docs/GV-UI.md");
const ag = lee(".claude/agents/disenador-gvui.md");
ok(/docs\/GV-UI\.md/.test(ag) && /gv-ui\.css/.test(ag),
   "(a) el agente del pase no manda a leer el sistema antes de auditar");
ok(/analisis\.js/.test(ag) && /analisis\.js/.test(doc),
   "(a) el sistema no nombra su pantalla de referencia");

/* ── (b) la paleta cumple, medida ────────────────────────────────────────────── */
const tok = {};
const rootBlock = (css.match(/:root\s*\{([\s\S]*?)\n\}/) || ["", ""])[1];
ok(!!rootBlock, "(b) gv-ui.css no tiene bloque :root");
// SÓLO el :root — la media query del celular redefine la escala a propósito
rootBlock.replace(/--(gv-[a-z0-9-]+)\s*:\s*([^;]+);/g, (_m, k, v) => { tok[k] = v.trim(); return _m; });
ok(Object.keys(tok).length > 20, "(b) gv-ui.css no declara tokens --gv-*");

const FONDO = tok["gv-bg"] || "#f6f7f9";
const TEXTO = ["gv-ink", "gv-ink-2", "gv-error", "gv-ok", "gv-warn", "gv-info"];
const medidos = [];
TEXTO.forEach((k) => {
  if (!tok[k]) { fallos.push("(b) falta el token --" + k); return; }
  const r = ratio(tok[k], FONDO);
  medidos.push(k + " " + tok[k] + " = " + r.toFixed(2));
  ok(r >= 4.5, "(b) --" + k + " (" + tok[k] + ") mide " + r.toFixed(2) + ":1 sobre " + FONDO +
     " — el mínimo AA para texto es 4,5:1");
});
// el gris de adorno tiene que estar DECLARADO como que no sirve para texto
ok(tok["gv-muted"] && ratio(tok["gv-muted"], FONDO) < 4.5 && /NUNCA texto/i.test(css),
   "(b) --gv-muted tendría que ser el gris de líneas, con el aviso de que no sirve para texto");
// el amarillo pleno sólo como fondo, y su texto negro tiene que pasar
if (tok["gv-warn-solid"] && tok["gv-on-warn"]) {
  const r = ratio(tok["gv-on-warn"], tok["gv-warn-solid"]);
  ok(r >= 4.5, "(b) el texto sobre el amarillo pleno mide " + r.toFixed(2) + ":1");
  ok(ratio(tok["gv-warn-solid"], "#ffffff") < 3,
     "(b) ojo: --gv-warn-solid se está pareciendo a un color de texto; es un FONDO");
}

/* ── (f) la zona prohibida ───────────────────────────────────────────────────── */
const PROHIBIDOS = { "#d97706": "ámbar de 2,97:1 — usá --gv-warn (#92400e)",
                     "#f1c21b": "amarillo pleno: 1,57:1 como texto. Sólo de fondo con texto negro",
                     "#94a3b8": "gris de líneas: 2,39:1. Para texto va --gv-ink-2" };
Object.keys(PROHIBIDOS).forEach((hex) => {
  const re = new RegExp("(^|[^a-z-])color:\\s*" + hex + "\\b", "im");
  ok(!re.test(css), "(f) gv-ui.css usa " + hex + " como color de texto — " + PROHIBIDOS[hex]);
});

/* ── (c) la escala es la escrita ─────────────────────────────────────────────── */
const ESCALA = { "gv-fs-xs": "11px", "gv-fs-sm": "12px", "gv-fs-md": "14px",
                 "gv-fs-lg": "16px", "gv-fs-xl": "20px", "gv-fs-2xl": "30px", "gv-fs-hero": "46px" };
Object.keys(ESCALA).forEach((k) => {
  ok(tok[k] === ESCALA[k], "(c) --" + k + " es «" + tok[k] + "», el sistema dice " + ESCALA[k]);
});
// 14 px es el piso de un DATO: no puede haber un paso entre 12 y 14
ok(!/--gv-fs-[a-z0-9-]*:\s*13px/.test(css), "(c) apareció un paso de 13 px: la escala va de 12 a 14");
const SP = ["2px", "4px", "8px", "12px", "16px", "24px", "32px", "48px"];
SP.forEach((v, i) => ok(tok["gv-sp-" + (i + 1)] === v,
  "(c) --gv-sp-" + (i + 1) + " es «" + tok["gv-sp-" + (i + 1)] + "», el sistema dice " + v));
ok(tok["gv-tap"] === "44px", "(c) el blanco de toque tiene que ser 44px (WCAG 2.5.5 + Apple HIG)");
ok(tok["gv-row-compact"] === "32px" && tok["gv-row"] === "40px" && tok["gv-row-roomy"] === "48px",
   "(c) los altos de fila son 32 / 40 / 48");
// la tabla del sistema trae cifras tabulares, o la columna de números baila
ok(/\.gv-tbl[^{]*\{[^}]*tabular-nums/.test(css.replace(/\n/g, " ")),
   "(c) .gv-tbl sin font-variant-numeric: tabular-nums");

/* ── (d) la pantalla de referencia USA el sistema ────────────────────────────── */
const an = lee("analisis.js");
const fsPropios = [...new Set(an.match(/font-size:\s*[0-9.]+px/g) || [])];
ok(!fsPropios.length, "(d) analisis.js escribe " + fsPropios.length + " tamaños propios en vez de " +
   "los tokens: " + JSON.stringify(fsPropios));
const hexPropios = [...new Set(an.match(/#[0-9a-fA-F]{6}\b/g) || [])];
ok(!hexPropios.length, "(d) analisis.js escribe hex propios en vez de tokens: " + JSON.stringify(hexPropios));
ok(/ov\.className\s*=\s*"gv"/.test(an), "(d) el overlay de analisis.js no entra al sistema (falta className = \"gv\")");
["gv-state", "gv-item", "gv-tbl", "gv-err", "gv-msg", "gv-chip", "gv-hero"].forEach((c) => {
  ok(an.indexOf(c) >= 0, "(d) analisis.js no usa la clase del sistema «" + c + "»");
});

/* ── (e) sin tokens muertos ──────────────────────────────────────────────────── */
const usoTotal = css + an;
const muertos = Object.keys(tok).filter((k) => {
  const usos = (usoTotal.match(new RegExp("var\\(--" + k + "\\)", "g")) || []).length;
  return usos === 0;
});
ok(!muertos.length, "(e) tokens declarados que no usa nadie: " + JSON.stringify(muertos) +
   " — o se usan o se borran");

if (fallos.length) {
  console.error("GV-UI SISTEMA — FALLA:\n  " + fallos.join("\n  "));
  process.exit(1);
}
console.log("gv-ui-sistema OK — " + Object.keys(tok).length + " tokens, paleta medida (" +
            medidos.join(" · ") + "), escala completa y analisis.js sin px ni hex propios.");
