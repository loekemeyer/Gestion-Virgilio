/* v25.40 — CORREGIR CÓDIGOS (secundario → principal) SIN UNA PERSONA.

   El cambio vive en la base (`gv_web_np_sec_auto` + `GV_NP_Cambio_Codigo`), pero la foto de
   picking la reescribe cada 5 minutos la Edge Function `gv-ppp-web-tandas-diarias` con el
   código del pedido de la página. Si la Edge Function deja de aplicar el cambio, el secundario
   vuelve solo y el podado saca el principal: la corrección se deshace sin que nadie lo vea.

   Este test:
   (A) corre la lógica de mapeo de la Edge Function (el bloque real, extraído del archivo) contra
       casos armados a mano: 333 → 948E, conversión por UxB, la L de Chef, NP sin cambio;
   (B) candados sobre el SQL: el criterio es el del panel (sec_cubre = false), la tanda empezada
       no se toca, la L se conserva, y la red (trigger + podado) está.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const ts = fs.readFileSync(path.join(__dirname, "..", "supabase", "functions", "gv-ppp-web-tandas-diarias", "index.ts"), "utf8");
const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_np_secundario_auto_v2540.sql"), "utf8");
const fails = [];

// ── (A) el bloque de mapeo, corrido de verdad ─────────────────────────────
const ini = ts.indexOf("const porArt: Record<string, number> = {};");
const fin = ts.indexOf("porArt[a] = (porArt[a] ?? 0) + cj;");
if (ini < 0 || fin < 0) {
  fails.push("no encontré el bloque de mapeo en la Edge Function (¿se borró la aplicación de GV_NP_Cambio_Codigo?)");
} else {
  let cuerpo = ts.slice(ini, fin + "porArt[a] = (porArt[a] ?? 0) + cj;".length) + "\n}";
  // de TypeScript a JS: sacar las anotaciones de tipo del bloque
  cuerpo = cuerpo
    .replace("const porArt: Record<string, number> = {};", "const porArt = {};")
    .replace(/\(n\.items as \{[^}]*\}\[\] \?\? \[\]\)/, "(n.items ?? [])");
  const armar = new Function("n", "k", "emp", "cambio", cuerpo + "\nreturn porArt;");
  const cambio = new Map([
    ["1578|1|333", { dest: "948E", factor: 1 }],
    ["900|1|332", { dest: "945E", factor: 2 }],          // 332 va de a 24, 945E de a 12
    ["901|1|809", { dest: "809E", factor: 1 }],           // Chef: el trigger sin_l_chef lo guardó sin L
  ]);
  const casos = [
    { n: { items: [{ art: "333", cajas: 1 }, { art: "034", cajas: 2 }] }, k: "1578|1", emp: "lk", esp: { "948E": 1, "034": 2 } },
    { n: { items: [{ art: "333", cajas: 1 }, { art: "948E", cajas: 3 }] }, k: "1578|1", emp: "lk", esp: { "948E": 4 } },
    { n: { items: [{ art: "332", cajas: 3 }] }, k: "900|1", emp: "lk", esp: { "945E": 6 } },
    { n: { items: [{ art: "809L", cajas: 2 }] }, k: "901|1", emp: "chef", esp: { "809E": 2 } },
    { n: { items: [{ art: "333", cajas: 1 }] }, k: "7777|1", emp: "lk", esp: { "333": 1 } },   // otra NP: no se toca
  ];
  casos.forEach(function (c, i) {
    let got;
    try { got = armar(c.n, c.k, c.emp, cambio); } catch (e) { fails.push("caso " + i + ": explotó — " + e.message); return; }
    if (JSON.stringify(got) !== JSON.stringify(c.esp)) {
      fails.push("caso " + i + ": esperaba " + JSON.stringify(c.esp) + " y salió " + JSON.stringify(got));
    }
  });
}
if (!/GV_NP_Cambio_Codigo\?select=order_id,np_idx,cod_origen,cod_destino,factor/.test(ts)) {
  fails.push("la Edge Function no lee GV_NP_Cambio_Codigo");
}
if (!/rCam\.status !== 404[\s\S]{0,80}throw new Error/.test(ts)) {
  fails.push("si la lectura de GV_NP_Cambio_Codigo falla, la Edge Function tiene que frenar la foto (no escribirla igual)");
}

// ── (B) candados del SQL ──────────────────────────────────────────────────
const need = [
  [/v\.sec_cubre = false/, "el criterio tiene que ser el del panel (sec_cubre = false)"],
  [/la tanda ya empezó/, "una tanda empezada no se toca"],
  [/case when c\.con_l then 'L' else '' end/, "la L se conserva en el principal"],
  [/no da cajas enteras/, "si las cajas no dan enteras en el principal, no se adivina"],
  [/create trigger trg_gv_ppp_web_base_np_cambio/, "falta el trigger que no deja volver al secundario"],
  [/v25\\\.39-np-cambio/, "falta el parche del podado"],
  [/np_sec_auto_activo/, "falta el interruptor"],
];
need.forEach(function (x) { if (!x[0].test(sql)) fails.push("SQL: " + x[1]); });

if (fails.length) { console.error("np-sec-auto: FALLA\n  - " + fails.join("\n  - ")); process.exit(1); }
console.log("np-sec-auto: OK — la Edge Function aplica el cambio de código (5 casos) y el SQL tiene sus candados");
