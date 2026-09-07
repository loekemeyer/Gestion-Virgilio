/* v13.97 — En pantalla NO se ven los códigos de evento: van los nombres de siempre.
   Dueño 07/09: "yo nunca entendí CCR y CCN; para mí es control remitos, carga camión y recepción
   remitos, sólo esos nombres entiendo". Los códigos son de la tabla de eventos, no del que mira la
   pantalla: se colaban en los `title` de En Salida y de la tabla de tandas ("evento CCN", "Armado
   terminado (TAP)", "No hay evento TAL"…).
   (a) ninguna solapa de la PPP muestra CCR / CCN / CRN / TAP / TAL, ni en el texto ni en los title;
   (b) En Salida abre con los tres pasos escritos con su nombre y en orden;
   (c) los chips que explicaban el circuito siguen ahí, pero en castellano.
   Este test es el candado: si alguien vuelve a poner un código en la pantalla, falla.
   Sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = { codigos: [] };
    const J = (data) => { const n = Array.isArray(data) ? data.length : 0; return Promise.resolve({ ok: true, status: 200,
      headers: { get: (h) => String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null },
      json: () => Promise.resolve(data), text: () => Promise.resolve(JSON.stringify(data)) }); };
    window.fetch = () => J([]);
    window._pppEmitError = function () {};

    // una NP en salida con el paso 1 hecho y el 2 pendiente — el caso que traía los códigos
    const np = "98585";
    _pppParsed = { prog: [{ np: np, tanda: "D56D", cod: "4274", razon_social: "Lin Liqin", m3: 0.113,
      localidad: "Soldati", direccion: "x", zona: "Zona 1 - CABA Sur", fecha_entrega: "04/09/2026", programmed: true }], aprogramar: [] };
    _pppDelivered = new Set(); _pppMetaEntSet = new Set(); _pppControladoCR = new Set();
    _pppEnSalida = new Map([[np, { np: np, tanda: "D56D", razon_social: "Lin Liqin", m3: 0.113,
      estado: "sin_carga", control_previo: true, armada: true, facturada: true,
      fecha_carga: null, cargado_at: null, fecha_entrega: "2026-09-04", dias_sin_controlar: 3 }]]);

    const re = /\b(CCR|CCN|CRN|TAP|TAL|CCA)\b/;
    const barrer = (tab) => {
      try { _pppTab = tab; pppRenderProg(); } catch (_e) { return ""; }
      const el = document.getElementById("pppPreview");
      const h = el ? el.innerHTML : "";
      let m; const rg = /(?:title="([^"]*)"|>([^<]+)<)/g;
      while ((m = rg.exec(h))) {
        const s = (m[1] || m[2] || "").trim();
        if (re.test(s)) out.codigos.push(tab + ": " + s.slice(0, 100));
      }
      return h;
    };
    ["plan", "enviaje", "ent", "resumen", "prog"].forEach(barrer);

    const hSal = barrer("enviaje");
    out.pasos = /1\.<\/b> Control Remitos/.test(hSal) && /2\.<\/b> Carga Camión/.test(hSal) && /3\.<\/b> Recepción Remitos/.test(hSal);
    out.ordenBien = hSal.indexOf("Control Remitos") < hSal.indexOf("Carga Camión") && hSal.indexOf("Carga Camión") < hSal.indexOf("Recepción Remitos");
    out.salteable = /se puede saltear si los remitos no llegaron/.test(hSal);
    out.chip = /✔ controlada · falta cargar/.test(hSal);
    out.chipTitle = /Paso 1 de 3 hecho: Control Remitos\. Falta el paso 2: Carga Camión\./.test(hSal);
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.codigos.length === 0, "ninguna solapa muestra códigos de evento" + (r.codigos.length ? ":\n     · " + r.codigos.slice(0, 6).join("\n     · ") : ""));
  chk(r.pasos, "En Salida escribe los tres pasos: Control Remitos · Carga Camión · Recepción Remitos");
  chk(r.ordenBien, "y en ese orden");
  chk(r.salteable, "aclara que el control se puede saltear si los remitos no llegaron");
  chk(r.chip, "el chip del paso 1 hecho sigue estando");
  chk(r.chipTitle, "y su explicación ya no nombra ningún código");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nppp-sin-codigos OK");
})();
