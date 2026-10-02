/* v26.12 — candado ESTÁTICO del programa de impresión (tools/impresion/GV-Impresion.ps1).
   En CI no hay Windows ni PowerShell 2.0, así que se vigila lo que lo rompería allá:
     A. ASCII puro (PowerShell 2.0 lee un .ps1 sin BOM como ANSI: un acento se ve roto).
     B. Nada de PowerShell 3+ (Invoke-RestMethod, ConvertTo-Json, [ordered], ::new …).
     C. El C# no usa nada posterior a C# 3 ($"", ?., nameof, =>, var en campos …).
     D. Llama a las RPC con los MISMOS nombres de parámetros que sql/gv_impresion_programa_v2611.sql
        (PostgREST resuelve por nombre: uno mal escrito da "function not found").
     E. Los .bat tienen fin de línea de Windows y apuntan al .ps1.
     F. clave.txt está ignorado por git (el repo es público).
   Validado además, a mano, el 02/10: el parser de PowerShell 7.4 da 0 errores y el C# compila con LangVersion 3. */
const fs = require("fs"), path = require("path");
const dir = path.join(__dirname, "..", "tools", "impresion");
const ps = fs.readFileSync(path.join(dir, "GV-Impresion.ps1"), "latin1");
const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_impresion_programa_v2611.sql"), "utf8");
const out = {};
out.A_ascii = !/[^\x00-\x7F]/.test(ps);
const sinComent = ps.split("\n").filter(function (l) { return !/^\s*#/.test(l); }).join("\n");
out.B_ps2 = !/Invoke-RestMethod|Invoke-WebRequest|ConvertTo-Json|ConvertFrom-Json|\[ordered\]|::new\(|\$PSItem|-parallel|\bclass\s+\w+\s*\{(?![\s\S]*'@)/i.test(sinComent.replace(/@'[\s\S]*?'@/g, ""));
const cs = (ps.match(/-TypeDefinition @'([\s\S]*?)'@/) || [])[1] || "";
out.C_cs3 = cs.length > 500 && !/\$"|\?\.|nameof\(|=>|\basync\b|\bawait\b|\bdynamic\b|\?\?=/.test(cs);
function paramsSql(fn) {
  const m = sql.match(new RegExp("function public\\." + fn + "\\(([^)]*)\\)"));
  return m ? (m[1].match(/p_\w+/g) || []) : null;
}
function paramsPs(fn) {
  // el bloque que arma $c justo antes de Rpc "<fn>"
  const i = ps.indexOf('Rpc "' + fn + '"'); if (i < 0) return null;
  const antes = ps.slice(Math.max(0, i - 700), i);
  const desde = antes.lastIndexOf("[GvImp]::Dic()");
  return (antes.slice(desde).match(/\$c\["(p_\w+)"\]/g) || []).map(function (x) { return x.slice(4, -2); });
}
const rpcs = ["gv_imp_agente_latido", "gv_imp_agente_tomar", "gv_imp_agente_resultado"];
out.D_params = rpcs.every(function (fn) {
  const a = paramsSql(fn), b = paramsPs(fn);
  const ok = a && b && a.slice().sort().join(",") === b.slice().sort().join(",");
  if (!ok) console.error("  ✗", fn, "sql:", a, "ps:", b);
  return ok;
});
const bats = fs.readdirSync(dir).filter(function (f) { return /\.bat$/i.test(f); });
out.E_bat = bats.length >= 2 && bats.every(function (f) {
  const t = fs.readFileSync(path.join(dir, f), "latin1");
  return /\r\n/.test(t) && !/[^\r]\n/.test(t) && t.indexOf("GV-Impresion.ps1") >= 0 || /WScript\.Shell/.test(t);
});
out.F_gitignore = /^clave\.txt$/m.test(fs.readFileSync(path.join(dir, ".gitignore"), "utf8"));
const fallas = Object.keys(out).filter(function (k) { return out[k] !== true; });
console.log("imp-agente-ps:", JSON.stringify(out), fallas.length ? "✗ FAIL " + fallas.join(",") : "✓ OK");
process.exit(fallas.length ? 1 : 0);
