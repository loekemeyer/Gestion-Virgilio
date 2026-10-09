// Genera supabase/functions/gv-ayuda/manual.ts desde ayuda/manual-operario.md.
// El manual es la ÚNICA fuente del asistente de ayuda: se edita el .md y se corre esto.
//   node scripts/ayuda-manual-build.cjs
const fs = require("fs"), path = require("path");
const root = path.join(__dirname, "..");
const md = fs.readFileSync(path.join(root, "ayuda/manual-operario.md"), "utf8");
const out = "// GENERADO por scripts/ayuda-manual-build.cjs desde ayuda/manual-operario.md — no editar a mano.\n" +
  "export const MANUAL = " + JSON.stringify(md) + ";\n";
fs.writeFileSync(path.join(root, "supabase/functions/gv-ayuda/manual.ts"), out);
console.log("manual.ts: " + md.length + " caracteres");
