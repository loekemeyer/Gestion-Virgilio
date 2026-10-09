// v29.24 — las tareas de módulo (guardado, bajar/ingreso a racks, Mover racks/Insumos/CP/RC) dejan un item
// SÓLO de Historial (id h_*). El replay de Terminar Día no lo puede re-mandar: duplicaba el evento.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
let fail = 0;
const ok = (c, m) => { console.log((c ? "OK  " : "FAIL") + " " + m); if (!c) fail++; };
const i = src.indexOf("async function bulkSendDayReplay");
const fnSrc = src.slice(i, src.indexOf("\n}\n", i) + 2);
const fn = new Function("desc", "GV_APP_TAG", "gvDispositivoId", "esLegajoEntrevista", "_gvNombrePrueba", "SUPABASE_TABLE_ENDPOINT", "SUPABASE_KEY", "fetch",
  fnSrc + "\nreturn bulkSendDayReplay;");
let sent = null;
const f = fn({}, "gestion", () => "d", () => false, () => null, "x", "k", async (u, o) => { sent = JSON.parse(o.body); });
(async () => {
  await f("104", [
    { id: "rt_104_a", opcion: "RT", ts: 1 },
    { id: "h_rkb_abc", opcion: "RKB", ts: 2, noReplay: true },
    { id: "h_mdt_abc", opcion: "MDT", ts: 3 },          // viejo, sin la marca: lo frena el prefijo
    { id: "h_mg_x", opcion: "MG", ts: 4, noReplay: true }
  ]);
  ok(sent && sent.length === 1 && sent[0].client_id === "rt_104_a", "el replay sólo manda el evento real (" + JSON.stringify(sent && sent.map(r => r.client_id)) + ")");
  const n = (src.match(/id: "h_[^\n]*status: "queued", noReplay: true/g) || []).length;
  ok(n === 3, "los 3 items de Historial de módulo llevan noReplay (" + n + ")");
  process.exit(fail ? 1 : 0);
})();
