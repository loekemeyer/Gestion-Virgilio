// v25.60 — Control Remitos: un CR ANTERIOR a un FSS no cuenta (la NP volvió y se re-entrega). Caso LK 0122.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const i = src.indexOf("async function fetchCCRData()"); const j = src.indexOf("\nfunction _liosCajasCell", i);
if (i < 0 || j < 0) { console.error("FAIL: no encuentro fetchCCRData"); process.exit(1); }
const body = src.slice(i, j);
const T = (s) => new Date(s).getTime();
const ctx = {
  CC_REPARTO_DESDE_ISO: "2026-06-22T00:00:00-03:00", SUPABASE_FACTURACION_NP_ENDPOINT: "fac", SUPABASE_TABLE_ENDPOINT: "ev",
  gvEsTandaPrueba: () => false, facFetchCajas: async () => new Map(),
  supaFetchAll: async () => [{ np: "LK 0122", tanda: "E30A" }, { np: "LK 0200", tanda: "E31A" }, { np: "LK 0300", tanda: "E32A" }],
  supaFetchAllSafe: async (_e, q) => q.startsWith("opcion=eq.CCR") ? [
    { texto: "LK 0122|E30A", ts_cliente: "2026-09-29T08:27:56-03:00" },   // CR viejo, FSS después → vuelve
    { texto: "LK 0200|E31A", ts_cliente: "2026-09-29T08:00:00-03:00" },   // CR sin FSS → controlado
    { texto: "LK 0300|E32A", ts_cliente: "2026-10-01T08:00:00-03:00" } ] : [],  // CR nuevo después del FSS → controlado
  fetchSinSalidaMap: async () => new Map([["LK 0122", T("2026-09-30T08:13:28-03:00")], ["LK 0300", T("2026-09-30T08:00:00-03:00")]])
};
const fn = new Function(...Object.keys(ctx), body + "\nreturn fetchCCRData;")(...Object.values(ctx));
fn().then((items) => {
  const nps = items.map((x) => x.np).sort().join(",");
  if (nps !== "LK 0122") { console.error("FAIL: esperaba sólo LK 0122 en CR, dio [" + nps + "]"); process.exit(1); }
  console.log("ccr-fss-recontrol: OK — la NP devuelta por FSS vuelve a Control Remitos");
}).catch((e) => { console.error("FAIL", e); process.exit(1); });
