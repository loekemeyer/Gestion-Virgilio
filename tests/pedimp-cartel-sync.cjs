// v25.12 (Luis, 30/09) — tocar «Cartel», la fecha de reingreso o la entrega global le pide a LK
// que rehaga el cartel de las páginas YA, con la función LIVIANA (la sync entera tarda ~11 s y
// anon corta a los 3 s). El switch «Web» no la llama: lo aplica la sync entera del cron 39.
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "importacion.js"), "utf8");
const idx = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };
const cuerpo = (nombre) => { const i = src.indexOf("function " + nombre + "("); if (i < 0) return ""; const j = src.indexOf("\n}\n", i); return src.slice(i, j); };
const sync = cuerpo("_impSyncPaginas");
ok(/rpc\/sync_reingresos_cartel_virgilio/.test(sync), "_impSyncPaginas tiene que llamar a sync_reingresos_cartel_virgilio");
ok(!/rpc\/sync_reingresos_virgilio"/.test(sync), "no la sync entera: tarda ~11 s y anon corta a los 3 s");
ok(/PWEB_LK_URL/.test(sync) && /PWEB_LK_ANON/.test(sync), "va a LK con su clave pública");
ok(/^const PWEB_LK_URL\s*=/m.test(idx) && /^const PWEB_LK_ANON\s*=/m.test(idx), "PWEB_LK_URL / PWEB_LK_ANON tienen que ser globales en index.html");
const cartel = cuerpo("pedImpReingresoWeb");
ok(/_impSyncPaginas\(\)/.test(cartel) && cartel.indexOf("_impSyncPaginas()") > cartel.indexOf("r.ok"), "el switch Cartel dispara la sync DESPUÉS de guardar");
ok(/_impSyncPaginas\(\)/.test(cuerpo("pedImpSetReingreso")), "la fecha de reingreso dispara la sync");
ok(/_impSyncPaginas\(\)/.test(cuerpo("pedImpSetEntregaGlobal")), "la entrega global dispara la sync");
ok(!/_impSyncPaginas\(\)/.test(cuerpo("pedImpWebVisible")), "el switch Web no la llama (lo aplica la sync entera)");
if (fallas.length) { console.log("pedimp-cartel-sync: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("pedimp-cartel-sync: ✓ OK");
