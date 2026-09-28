// v23.08 (problema 579): el service worker y los .js propios tienen que PARSEAR, y ningún
// archivo del repo puede llevar marcas de conflicto de merge. El 28/09 (c21f3b6) se pusheó
// sw.js con `<<<<<<< HEAD` adentro: el SW no se instalaba y ningún test lo vio.
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { execSync } = require("child_process");
const root = path.join(__dirname, "..");
let fallas = 0;

// 1) los scripts que carga el navegador tal cual (sin build): tienen que compilar
const scripts = ["sw.js", "recepcion.js", "planimetria.js", "supabase-config.js",
                 "cervantes/sw.js", "selector/sw.js"];
for (const f of scripts) {
  const p = path.join(root, f);
  if (!fs.existsSync(p)) continue;
  try { new vm.Script(fs.readFileSync(p, "utf8"), { filename: f }); }
  catch (e) { console.log("FALLA " + f + " no parsea: " + e.message); fallas++; }
}

// 2) marcas de conflicto en cualquier archivo de texto versionado
const re = /^(<{7}|>{7})( |$)|^={7}$/m;
const archivos = execSync("git ls-files", { cwd: root, encoding: "utf8" }).split("\n")
  .filter(f => /\.(js|cjs|mjs|html|json|css|sql|ts|md|yml|yaml|sh)$/.test(f));
for (const f of archivos) {
  let s; try { s = fs.readFileSync(path.join(root, f), "latin1"); } catch (_e) { continue; }
  const m = s.match(re);
  if (m) {
    const linea = s.slice(0, m.index).split("\n").length;
    console.log("FALLA " + f + ":" + linea + " tiene una marca de conflicto de merge");
    fallas++;
  }
}

// 3) los .json versionados tienen que ser JSON válido (el 28/09 settings.local.json quedó con
//    marcas de conflicto commiteadas y el archivo entero dejó de leerse)
for (const f of archivos.filter(x => x.endsWith(".json"))) {
  try { JSON.parse(fs.readFileSync(path.join(root, f), "utf8").replace(/^\uFEFF/, "")); }
  catch (e) { console.log("FALLA " + f + " no es JSON válido: " + e.message); fallas++; }
}

console.log(fallas ? "js-parsea: " + fallas + " falla(s)"
                   : "js-parsea: OK — " + scripts.length + " scripts parsean, " + archivos.length + " archivos sin marcas de conflicto");
process.exit(fallas ? 1 : 0);
