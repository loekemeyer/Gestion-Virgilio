/* Regresión v15.77 — window.GONDOLA se llena de GV_Lugar, no de "Planimetria".

   window.GONDOLA ({cod: [sector, orden]}) lo usan 25 lugares. El cambio es de DÓNDE
   se llena, no de qué forma tiene: por eso ninguno de los 25 se tocó.

   Chequea:
   - Con gv_lugar_articulo disponible, GONDOLA sale de ahí y NO se pide "Planimetria".
   - Clave pelada = el PRIMER lugar del RECORRIDO (menor `orden`), no el primero que
     llega ni el de menor número de sector. La tabla vieja guardaba un solo sector por
     código; acá un código está en varios (el 437E en F09-F12).
   - Los códigos que viven en las DOS empresas generan además su clave con sufijo
     ("437E LK"), porque pkCodEmpresa todavía la busca. Si desaparece de golpe, el
     picking cae al pelado — que para el 809E es la góndola de CHEF y el operario
     trae un Corta Queso en vez de un Corta Pizza.
   - Un código de UNA sola empresa NO genera clave con sufijo (no hace falta).
   - Si la vista no está (404) o viene vacía → cae a "Planimetria", como siempre.
   - Si no hay red → no rompe: queda la planimetría estática.
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
    const GV = [
      // 437E: cuatro lugares de LK y dos de CH. Ojo el `orden`: F12 va ANTES que F09
      // en el recorrido real (no sigue la numeración del pasillo, y está bien así).
      { cod: "437E", empresa: "LK", sector: "F12", orden: 261 },
      { cod: "437E", empresa: "LK", sector: "F09", orden: 316 },
      { cod: "437E", empresa: "LK", sector: "F10", orden: 317 },
      { cod: "437E", empresa: "CH", sector: "L07", orden: 400 },
      // 505: una sola empresa, dos lugares
      { cod: "505",  empresa: "LK", sector: "D18", orden: 281 },
      { cod: "505",  empresa: "LK", sector: "D01", orden: 298 }
    ];
    const realFetch = window.fetch;
    let modo = "ok", pidioPlanimetria = false;
    window.fetch = async function (url) {
      const u = String(url);
      if (u.indexOf("gv_lugar_articulo") >= 0) {
        if (modo === "404")   return { ok: false, status: 404, json: async () => [] };
        if (modo === "vacio") return { ok: true,  status: 200, json: async () => [] };
        if (modo === "red")   throw new Error("net");
        return { ok: true, status: 200, json: async () => GV };
      }
      if (u.indexOf("/Planimetria") >= 0) {
        pidioPlanimetria = true;
        return { ok: true, status: 200, json: async () => [{ cod: "999", sector: "Z99", orden: 9 }] };
      }
      return realFetch(url);
    };

    // --- (a) camino feliz
    window.GONDOLA = {}; pidioPlanimetria = false;
    await loadPlanimetriaRemote();
    out.noPidioPlanimetria   = (pidioPlanimetria === false);
    out.peladoEsPrimeroDelRecorrido = GONDOLA["437E"] && GONDOLA["437E"][0] === "F12";   // no F09, no F10
    out.peladoLlevaSuOrden   = GONDOLA["437E"] && GONDOLA["437E"][1] === 261;
    out.sufijoLK             = GONDOLA["437E LK"] && GONDOLA["437E LK"][0] === "F12";
    out.sufijoCH             = GONDOLA["437E CH"] && GONDOLA["437E CH"][0] === "L07";
    out.unaEmpresaSinSufijo  = !GONDOLA["505 LK"] && !!GONDOLA["505"];
    out.unaEmpresaPrimero    = GONDOLA["505"] && GONDOLA["505"][0] === "D18";

    // --- (b) la vista no está → cae a Planimetria
    window.GONDOLA = {}; modo = "404"; pidioPlanimetria = false;
    await loadPlanimetriaRemote();
    out.sin404CaeAPlanimetria = pidioPlanimetria && GONDOLA["999"] && GONDOLA["999"][0] === "Z99";

    // --- (c) la vista está pero vacía → también cae (no deja el picking sin góndola)
    window.GONDOLA = {}; modo = "vacio"; pidioPlanimetria = false;
    await loadPlanimetriaRemote();
    out.vaciaCaeAPlanimetria = pidioPlanimetria && !!GONDOLA["999"];

    // --- (d) sin red → no rompe
    window.GONDOLA = { "PREVIO": ["A01", 1] }; modo = "red"; pidioPlanimetria = false;
    let exploto = false;
    try { await loadPlanimetriaRemote(); } catch (_e) { exploto = true; }
    out.sinRedNoRompe = !exploto && !!GONDOLA["PREVIO"];

    window.fetch = realFetch;
    return out;
  });
  const bad = Object.entries(r).filter(([, v]) => v !== true).map(([k]) => k);
  console.log("gondola-gv-lugar:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none");
  await b.close();
  if (bad.length || errs.length) { console.error("✗ FALLA:", bad.join(", ") || "pageerrors"); process.exit(1); }
  console.log("✓ OK");
})();
