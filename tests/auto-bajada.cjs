/* Regresión idea 7180 — stkAutoBajadaCompute (bajada automática racks → góndola).
   Función pura sobre _stk: por código con capacidad cargada calcula
   masters = min(piso(hueco/CxM), piso(racks/CxM)) y propone bajar masters×CxM cajas.
   Cubre: caso normal con factor del maestro · góndola llena (hueco 0) no propone ·
   CxM derivado de la PLANIMETRÍA cuando no hay maestro (todas las celdas ocupadas con
   el mismo ratio entero inner/master) · planimetría inconsistente → va a sinMaster ·
   racks insuficientes para 1 master → no aparece · orden por código numérico.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const mv = function (cod, dep, delta) { return { cod_art: cod, deposito: dep, delta: delta, tipo: "inicial", ts: "2026-08-01T10:00:00Z" }; };
    _stk = {
      cutoff: 0,
      movs: [
        mv("100", "terminado", 40), mv("100", "racks", 50),
        mv("200", "terminado", 30), mv("200", "racks", 10),
        mv("300", "terminado", 10), mv("300", "racks", 20),
        mv("400", "racks", 30),
        mv("500", "racks", 5)
      ],
      factors: { "100": { cajasXMaster: 12 }, "500": { cajasXMaster: 12 } },
      cap: [
        { cod: "300", cajas_max: 20 }, { cod: "300", cajas_max: 30 },   // capacidad SUMA por código (50)
        { cod: "100", cajas_max: 100 }, { cod: "200", cajas_max: 30 },
        { cod: "400", cajas_max: 50 }, { cod: "500", cajas_max: 20 }
      ],
      plani: [
        { cod_art: "300", estado: "ocupado", master_cajas: 2, innercajas: 16 },   // ratio 8
        { cod_art: "300", estado: "ocupado", master_cajas: 1, innercajas: 8 },    // ratio 8 (consistente)
        { cod_art: "300", estado: "libre",   master_cajas: 1, innercajas: 99 },   // libre: se ignora
        { cod_art: "400", estado: "ocupado", master_cajas: 1, innercajas: 6 },    // ratio 6
        { cod_art: "400", estado: "ocupado", master_cajas: 1, innercajas: 8 }     // ratio 8 → inconsistente
      ]
    };
    const res = stkAutoBajadaCompute();
    const by = {}; res.bajar.forEach(function (x) { by[x.cod] = x; });

    // 100: cap 100, gond 40 → hueco 60; racks 50; CxM 12 (maestro) → min(5,4)=4 masters = 48 cajas
    out.normal = !!by["100"] && by["100"].masters === 4 && by["100"].cajas === 48 && by["100"].master === 12 && by["100"].hueco === 60;
    // 200: góndola llena (30/30) → no propone
    out.gondolaLlena = !by["200"];
    // 300: sin maestro, CxM 8 de planimetría; cap 50 (20+30 sumadas), gond 10 → hueco 40; racks 20 → min(5,2)=2 masters = 16 cajas
    out.cxmPlani = !!by["300"] && by["300"].master === 8 && by["300"].masters === 2 && by["300"].cajas === 16 && by["300"].capg === 50;
    // 400: planimetría inconsistente (6 vs 8) → sin CxM → va a sinMaster
    out.planiInconsistente = !by["400"] && res.sinMaster.some(function (x) { return x.cod === "400"; });
    // 500: racks 5 < 1 master (12) → ni bajar ni sinMaster
    out.racksInsuf = !by["500"] && !res.sinMaster.some(function (x) { return x.cod === "500"; });
    // orden por código numérico
    out.orden = res.bajar.map(function (x) { return x.cod; }).join(",") === "100,300";
    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("auto-bajada:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
