/* Regresión idea 5334 — _pppComputeErrors (panel de errores de la PPP).
   Cubre: 🚮 "sacar" (programado pero YA entregado, vía entSet) · ⚠ "sin zona" SOLO si ni el
   barrio ni la columna `zona` la resuelven (el fix de los falsos positivos tipo José León
   Suárez) · ⚠ "zona no coincide" (barrio vs columna, comparación normalizada: acentos y
   mayúsculas no cuentan) · zonas EXENTAS (Retira/Super/Expo) no marcan nada · pedidos Súper
   (KRIKOS) exentos · tandas inconsistentes por RUTAS mezcladas y por VARIAS FECHAS ·
   excepción Ciudadela (pegada a la fábrica camino a Zona 1 → no cuenta como ruta aparte).
   pppZonaDeBarrio se stubbea con un mapa fijo para no depender de la tabla viva. Sale 1 si falla. */
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
    // mapa barrio→zona controlado (reemplaza tabla viva + overrides)
    const MAPA = { "flores": "Zona 1 - CABA Sur", "moron": "Zona 5 - GBA Oeste", "ciudadela": "Zona 5 - GBA Oeste" };
    window.pppZonaDeBarrio = function (b0) { return MAPA[String(b0 || "").toLowerCase().trim()] || ""; };

    const P = function (o) { return Object.assign({ programmed: true, tanda: "", zona: "", localidad: "", fecha_entrega: "2026-08-29", tipo: "", razon_social: "X", np: "0" }, o); };
    const errsOf = function (res, np) { const hit = [].concat(res.sacar, res.sinZona, res.zonaDif).find(function (q) { return String(q.np) === String(np); }); return hit ? hit._err : null; };

    // ---- sacar: programado pero YA entregado ----
    let res = _pppComputeErrors([P({ np: "98001", localidad: "Flores" })], new Set(["98001"]));
    out.sacar = res.sacar.length === 1 && res.sacar[0]._err.indexOf("sacar") >= 0;

    // ---- sin zona: SOLO si ni barrio ni columna la resuelven ----
    res = _pppComputeErrors([P({ np: "98002", localidad: "Barrio Desconocido", zona: "" })], null);
    out.sinZona = res.sinZona.length === 1;
    // barrio desconocido PERO columna zona cargada (autozona Supabase) → NO es sin-zona
    res = _pppComputeErrors([P({ np: "98003", localidad: "Jose Leon Suarez", zona: "Zona 6 - GBA Norte" })], null);
    out.sinZona_fixAutozona = res.sinZona.length === 0;

    // ---- zona no coincide (barrio dice 1, Excel dice 5) / coincidencia normalizada ----
    res = _pppComputeErrors([P({ np: "98004", localidad: "Flores", zona: "Zona 5 - GBA Oeste" })], null);
    out.zonaDif = res.zonaDif.length === 1 && res.zonaDif[0]._err.indexOf("zonadif") >= 0;
    res = _pppComputeErrors([P({ np: "98005", localidad: "Flores", zona: "ZONA 1 – caba sur" })], null);
    out.zonaNormalizada = res.zonaDif.length === 0 && res.sinZona.length === 0;

    // ---- zonas exentas y pedidos Súper: no marcan nada ----
    res = _pppComputeErrors([P({ np: "98006", localidad: "quien sabe", zona: "Retira" }),
                             P({ np: "98007", localidad: "quien sabe", tipo: "KRIKOS" })], null);
    out.exentas = res.sinZona.length === 0 && res.zonaDif.length === 0;

    // ---- tanda con RUTAS mezcladas (Zona 1 = ruta sur/oeste vs Zona 5 = ruta norte... según _pppRuta) ----
    res = _pppComputeErrors([P({ np: "98010", tanda: "T1", localidad: "Flores" }),
                             P({ np: "98011", tanda: "T1", localidad: "Moron" })], null);
    out.rutasMezcladas = res.tandasMal.length === 1 && res.tandasMal[0].tanda === "T1" && res.tandasMal[0].rutas === 2;

    // ---- excepción Ciudadela: no cuenta como ruta aparte ----
    res = _pppComputeErrors([P({ np: "98012", tanda: "T2", localidad: "Flores" }),
                             P({ np: "98013", tanda: "T2", localidad: "Ciudadela" })], null);
    out.ciudadelaExenta = res.tandasMal.length === 0;

    // ---- tanda con VARIAS FECHAS de entrega ----
    res = _pppComputeErrors([P({ np: "98014", tanda: "T3", localidad: "Flores", fecha_entrega: "2026-08-29" }),
                             P({ np: "98015", tanda: "T3", localidad: "Flores", fecha_entrega: "2026-08-30" })], null);
    out.variasFechas = res.tandasMal.length === 1 && res.tandasMal[0].fechas === 2 && res.tandasMal[0].rutas <= 1;

    // ---- sin nada raro → panel limpio ----
    res = _pppComputeErrors([P({ np: "98016", tanda: "T4", localidad: "Flores", zona: "Zona 1 - CABA Sur" })], new Set());
    out.limpio = res.sacar.length + res.sinZona.length + res.zonaDif.length + res.tandasMal.length === 0 &&
      pppErroresHtml(res) === "";   // v13.12: sin errores no se dibuja nada (dueño: "sacá esas 2 alertas")

    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("ppp-errores:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
