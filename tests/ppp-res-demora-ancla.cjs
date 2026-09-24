/* v22.16 (Luis, 24/09) — el Resumen de la PPP no cuenta como DEMORA la espera que no lo es:
   la parte de un pedido partido por un importado que todavia no llego, y el retiro o turno que
   el cliente eligio para mas adelante. El backend (gv_ppp_demora_ancla) dice desde que fecha se
   cuenta; aca se corre pppResumenHtml de verdad y se mira la celda de "Mayor demora".

   Casos:
   (A) LK 0221, pedido 07/09, sale 09/12, importado llega 29/11 -> demora 10 (no 93), con 📦.
   (B) el mismo dia, un pedido comun de 30 dias -> la mayor demora del dia es 30, no 93.
   (C) sin respuesta del backend (mapa vacio) -> vuelve a contar desde el pedido: 93.
   (D) el pop-up del camion dice por que (llega el 29/11, 93 d desde el pedido). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "load" });

  const r = await p.evaluate(() => {
    const ped = function (np, rs, loc, m3, recep, entrega) {
      return { np: np, tanda: "E91C", cod: rs, razon_social: rs, m3: m3, localidad: loc, zona: "", fecha: recep, fecha_entrega: entrega, programmed: true };
    };
    const leer = function (prog) {
      const host = document.createElement("div");
      host.innerHTML = pppResumenHtml(prog);
      const fila = [...host.querySelectorAll(".ppp-restbl tbody tr")].find(function (tr) { return tr.children[0].textContent.trim() === "09/12"; });
      const td = fila ? fila.children[fila.children.length - 1] : null;
      return { txt: td ? td.textContent.replace(/[📦📅]/gu, "").trim() : null, ico: td ? td.textContent : "", title: td && td.querySelector(".dem-anc") ? td.querySelector(".dem-anc").title : "" };
    };
    // mapa cargado y fresco: que pppDemAnclaNeed no vaya a la red
    _pppDemAncla = { "LK 0221": { motivo: "importado", ancla: "2026-11-29" } }; _pppDemAnclaTs = Date.now();
    const A = leer([ped("LK 0221", "Laza Ariel", "Ituzaingo", 0.009, "07/09/2026", "09/12/2026")]);
    const B = leer([ped("LK 0221", "Laza Ariel", "Ituzaingo", 0.009, "07/09/2026", "09/12/2026"),
                    ped("LK 0300", "Otro", "Ituzaingo", 0.5, "09/11/2026", "09/12/2026")]);
    // pop-up del camion
    pppResCamTgl(Object.keys(_pppResCam)[0]);
    const ov = document.getElementById("pppResPopOv");
    const pop = ov ? ov.textContent : "";
    _pppDemAncla = {}; _pppDemAnclaTs = Date.now();
    const C = leer([ped("LK 0221", "Laza Ariel", "Ituzaingo", 0.009, "07/09/2026", "09/12/2026")]);
    return { A: A, B: B, C: C, pop: pop, keys: Object.keys(_pppResCam || {}) };
  });

  const fallas = [];
  if (r.A.txt !== "10") fallas.push("(A) demora del importado: esperaba 10, dio " + r.A.txt);
  if (r.A.ico.indexOf("📦") < 0) fallas.push("(A) falta el icono 📦");
  if (!/29\/11/.test(r.A.title) || !/93/.test(r.A.title)) fallas.push("(A) el title no dice la fecha y la demora bruta: " + r.A.title);
  if (r.B.txt !== "30") fallas.push("(B) mayor demora del dia: esperaba 30, dio " + r.B.txt);
  if (r.C.txt !== "93") fallas.push("(C) sin backend tiene que contar desde el pedido: esperaba 93, dio " + r.C.txt);
  if (!/llega el 29\/11/.test(r.pop) || !/93 d desde el pedido/.test(r.pop)) fallas.push("(D) el pop-up no explica la demora (" + r.keys.join(",") + "): " + r.pop.slice(0, 200));

  await b.close();
  if (fallas.length) { console.error("ppp-res-demora-ancla: FALLA\n  " + fallas.join("\n  ")); process.exit(1); }
  console.log("ppp-res-demora-ancla: OK — importado cuenta desde que llega (10, no 93), el dia toma la demora real y sin backend vuelve a la cuenta vieja");
})();
