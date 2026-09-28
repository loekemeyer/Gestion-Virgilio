// v23.03 (Luis, 28/09): el chip "💰 Deuda" dice desde cuándo, y la fecha viene de su propia RPC
// (gv_cuarentena_deuda_desde) DENTRO del allSettled: si falla, la marcación sigue en pie.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html").toString("utf8");
let bad = 0;
const ok = (c, m) => { if (!c) { bad++; console.error("✗ " + m); } else console.log("✓ " + m); };
const i0 = src.indexOf("const _st = await Promise.allSettled([");
const i1 = src.indexOf("]);", i0);
ok(i0 > 0 && src.slice(i0, i1).includes('aprRpc("gv_cuarentena_deuda_desde"'), "la fecha va en el allSettled (falla sola)");
ok(/_st\[3\]\.status === "fulfilled"/.test(src), "se lee con su propio status");
ok(/" · desde " \+ dsTxt/.test(src), "el chip de deuda muestra 'desde dd/mm'");
process.exit(bad ? 1 : 0);
