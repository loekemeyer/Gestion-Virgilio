/* v26.97 (Luis, 05/10/2026) — las 9 cajas del 809 (nacional, Chef) salen PRIMERO en las NP de CH.

   El cambio 809E → 809 vive en la base (`gv_web_np_809_nacional` + `GV_NP_Cambio_Codigo`, el mismo
   registro de v25.40 en sentido contrario) y la foto de picking la reescribe cada 5 minutos la Edge
   Function con el código del PEDIDO (809E). Si la Edge Function deja de aplicar el registro, el 809E
   vuelve solo y la NP pide caja que no se pickeó de la góndola correcta.

   Este test:
   (A) corre el bloque de mapeo REAL de la Edge Function con un caso 809E → 809 de Chef;
   (B) candados sobre el SQL: la función NO toca nada empezado / pickeado / armado / facturado (Luis:
       «que no joda pedidos ya pickeados, armados, en proceso, facturados»), respeta el cupo, sólo
       toma el 809E sin L, y NO usa `delete` (el conector de las sesiones cloud se cuelga con él);
   (C) el parche del trigger de empresa (el facturado «Mixto» de F22F) y la regla protegida.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const ts = fs.readFileSync(path.join(root, "supabase", "functions", "gv-ppp-web-tandas-diarias", "index.ts"), "utf8");
const sql = fs.readFileSync(path.join(root, "sql", "gv_np_809_nacional_v2697.sql"), "utf8");
const reglas = JSON.parse(fs.readFileSync(path.join(root, "scripts", "reglas-protegidas.json"), "utf8")).reglas || [];
const fails = [];

// ── (A) el mapeo de la Edge Function, corrido de verdad ───────────────────
const FIN = "porArt[a] = (porArt[a] ?? 0) + cj;";
const ini = ts.indexOf("const porArt: Record<string, number> = {};");
const fin = ts.indexOf(FIN);
if (ini < 0 || fin < 0) {
  fails.push("no encontré el bloque de mapeo en la Edge Function (¿se borró la aplicación de GV_NP_Cambio_Codigo?)");
} else {
  const cuerpo = ts.slice(ini, fin + FIN.length)
    .replace("const porArt: Record<string, number> = {};", "const porArt = {};")
    .replace(/\(n\.items as \{[^}]*\}\[\] \?\? \[\]\)/, "(n.items ?? [])") + "\n}";
  const armar = new Function("n", "k", "emp", "cambio", cuerpo + "\nreturn porArt;");
  const cambio = new Map([["235|1|809E", { dest: "809", factor: 1 }]]);
  const casos = [
    { n: { items: [{ art: "809E", cajas: 5 }, { art: "824", cajas: 5 }] }, k: "235|1", emp: "chef", esp: { "809": 5, "824": 5 } },
    { n: { items: [{ art: "809E", cajas: 3 }] }, k: "236|1", emp: "chef", esp: { "809E": 3 } },   // otra NP: no se toca
  ];
  casos.forEach(function (c, i) {
    let got;
    try { got = armar(c.n, c.k, c.emp, cambio); } catch (e) { fails.push("(A) caso " + i + ": explotó — " + e.message); return; }
    if (JSON.stringify(got) !== JSON.stringify(c.esp)) {
      fails.push("(A) caso " + i + ": esperaba " + JSON.stringify(c.esp) + " y salió " + JSON.stringify(got));
    }
  });
}

// ── (B) candados de la función ────────────────────────────────────────────
const i0 = sql.indexOf("create or replace function public.gv_web_np_809_nacional");
const i1 = sql.indexOf("end $fn$;", i0);
const fn = i0 >= 0 && i1 > i0 ? sql.slice(i0, i1) : "";
if (!fn) fails.push("(B) no encontré la función gv_web_np_809_nacional en el SQL");
const sinComentarios = fn.replace(/--[^\n]*/g, "");
[
  [/Registros_Produccion_Virgilio[\s\S]{0,200}'no: la tanda ya empezo'/, "una tanda EMPEZADA por un operario no se toca"],
  [/p\.tipo = 'picking'[\s\S]{0,200}'no: la tanda ya se pickeo'/, "una tanda con PICKING no se toca"],
  [/Entregas_Virgilio[\s\S]{0,200}'no: la NP ya tiene armado'/, "una NP ARMADA no se toca"],
  [/Facturacion_NP[\s\S]{0,200}'no: la NP ya se facturo'/, "una NP FACTURADA no se toca"],
  [/'no: la NP ya esta cambiada'/, "una NP ya cambiada no se vuelve a cambiar"],
  [/'no: la NP ya trae 809'/, "una NP que ya trae 809 se salta (el renombre chocaría con su línea)"],
  [/_n9_r\.cajas > _n9_rest/, "el cupo no se pasa: una línea que no entra ENTERA se salta"],
  [/_n9_r\.cajas > _n9_disp/, "no se cambia más de lo que hay del 809 en la góndola"],
  [/upper\(btrim\(b\.articulo\)\) = '809E'/, "sólo el 809E SIN L (el de Chef)"],
  [/b\.empresa = 'chef'/, "sólo NP de Chef"],
  [/np_809_nacional_activo/, "falta el interruptor"],
  [/np_809_nacional_cupo/, "falta el cupo"],
  [/update public\."PPP_Web_Base" w set articulo = '809'/, "la línea se RENOMBRA en el lugar (no se borra)"],
  [/_n9_sim := true/, "sin el interruptor prendido sólo simula"],
].forEach(function (x) { if (!x[0].test(sinComentarios)) fails.push("(B) " + x[1]); });
if (/\bdelete\s+from\b|\bdrop\s+(function|table)\b|\btruncate\b/i.test(sinComentarios)) {
  fails.push("(B) la función usa delete/drop/truncate: el conector de Supabase de las sesiones cloud se cuelga a los 60 s con eso");
}
if (!/cron\.schedule\('gv-np-809-nacional', '3-59\/5 9-23 \* \* \*'/.test(sql)) {
  fails.push("(B) falta el cron (3 minutos después de la Edge Function, escalonado)");
}

// ── (C) el trigger de empresa y la regla protegida ────────────────────────
if (!/m\.tipo IN \('separado','ajuste'\)/.test(sql)) {
  fails.push("(C) falta el parche de trg_normalizar_empresa_stock: el facturado de una tanda trasladada (X|MOV-Y) cae en 'Mixto'");
}
if (!/v26\\\.93-mov-ajuste/.test(sql)) fails.push("(C) el parche del trigger perdió su marca de idempotencia");
["gv_web_np_809_nacional", "trg_normalizar_empresa_stock"].forEach(function (o) {
  if (!reglas.some(function (r) { return r.objeto === o; })) fails.push("(C) " + o + " no está en scripts/reglas-protegidas.json");
});

if (fails.length) { console.error("np-809-nacional: FALLA\n  - " + fails.join("\n  - ")); process.exit(1); }
console.log("np-809-nacional: OK — la Edge Function aplica 809E→809 y la función no toca nada empezado/pickeado/armado/facturado");
