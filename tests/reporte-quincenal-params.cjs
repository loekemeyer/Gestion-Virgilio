// v26.42 — Reporte quincenal a pedir (Luis, 02/10): las 5 variables de la plantilla de WhatsApp salen de
// `datos` de _pedImpResumenHoja, y el workflow se presenta con OIDC (sin secretos).
"use strict";
const fs = require("fs");
const path = require("path");
const R = path.join(__dirname, "..");
const { armarParams } = require(path.join(R, "scripts/reporte-quincenal/enviar.cjs"));
let fallas = 0;
const ok = (c, m) => { if (!c) { fallas++; console.error("✗ " + m); } else console.log("✓ " + m); };

const datos = { total: { curso: 200228.4, usd: 85154.2 }, filas: [
  { prov: "Zhixin", usd: 10273, nivel: 2 }, { prov: "Kangli", usd: 8747, nivel: 2 },
  { prov: "Fujian", usd: 21874, nivel: 3 }, { prov: "Frontier", usd: 0, nivel: 5 } ] };
const p = armarParams(datos, "2026-10-16");
ok(JSON.stringify(p) === JSON.stringify(["16/10", "85.154", "3", "200.228", "Zhixin y Kangli (prioridad 2)"]), "variables: " + JSON.stringify(p));
const muchos = { total: { usd: 1, curso: 0 }, filas: ["A", "B", "C", "D"].map((x) => ({ prov: x, usd: 1, nivel: 1 })) };
ok(armarParams(muchos, "2026-10-01")[4] === "A, B y 2 más (prioridad 1)", "más de 3 urgentes se resumen: " + armarParams(muchos, "2026-10-01")[4]);
ok(armarParams({ total: {}, filas: [{ prov: "X", usd: 0, nivel: 5 }] }, "2026-10-01")[4] === "—", "sin Est. Madre en ninguno → —");
ok(armarParams(datos, "2026-10-16").every((v) => v && !/\n|\s{5,}/.test(v)), "ninguna variable vacía ni con saltos (Meta las rechaza)");

const imp = fs.readFileSync(path.join(R, "importacion.js"), "utf8");
ok(/datos: datos \}/.test(imp) && /nivel: f\.urg\.nivel/.test(imp), "_pedImpResumenHoja devuelve datos con el nivel de prioridad");
const wf = fs.readFileSync(path.join(R, ".github/workflows/reporte-quincenal-importacion.yml"), "utf8");
ok(/id-token: write/.test(wf), "el workflow pide el token OIDC");
ok(/cron: "41 11 1,16 \* \*"/.test(wf), "corre los días 1 y 16");
ok(!/secrets\./.test(wf), "el workflow no usa ningún secreto");
const sc = fs.readFileSync(path.join(R, "scripts/reporte-quincenal/enviar.cjs"), "utf8");
ok(/"x-gh-oidc": oidc/.test(sc) && /lk_reporte-quincenal/.test(sc), "el script llama a lk_reporte-quincenal con el OIDC en x-gh-oidc");
process.exit(fallas ? 1 : 0);
