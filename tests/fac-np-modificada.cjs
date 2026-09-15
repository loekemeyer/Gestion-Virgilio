/* v18.29 (Luis) — El badge ✏ MOD en la columna NP de FACTURACIÓN.
   *"un cliente que manda un pedido y después llama para cambiar algo … en el módulo de
   facturación debería tener un badge al lado del código en la columna NP que indique que fue
   modificado y que si alguien lo aprieta o le pone el mouse encima diga qué cambio se le hizo
   (para que se pueda facturar a mano correctamente en ISIS)"*.

   Chequea: (a) la NP modificada trae el badge, con el detalle en el globito; (b) la que no se
   tocó NO lo trae (control: si lo trajera siempre, el badge no diría nada); (c) tocarlo cuenta
   quién, cuándo, qué y por qué; (d) la NP de ISIS matchea aunque venga con ".0" pegado; (e) el
   badge está CABLEADO en la fila de Facturación y el fetch está cableado en la carga — un helper
   que nadie llama no sirve de nada.
   Sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    // ── control de no-trivialidad: sin datos, ninguna NP tiene badge ──────
    out.vacioSinBadge = facModChip("LK 0024") === "" && facModChip("98651") === "";

    _facMod = new Map([
      ["LK 0024", { mods: 2, ultima: "2026-09-15T12:00:00-03:00",
        resumen: "027: 1→7 cajas · + 025 ×3 | entrega: Rivadavia 100 → Depósito Lanús",
        cambios: [
          { cuando: "2026-09-15T12:00:00-03:00", quien: "Mariana", motivo: "cambió la entrega",
            que: "entrega: Rivadavia 100 → Depósito Lanús" },
          { cuando: "2026-09-15T10:30:00-03:00", quien: "Mariana", motivo: "el cliente llamó",
            que: "027: 1→7 cajas · + 025 ×3" }
        ] }],
      ["98651", { mods: 1, ultima: "2026-09-15T09:00:00-03:00", resumen: "− 992E",
        cambios: [{ cuando: "2026-09-15T09:00:00-03:00", quien: "Luis", motivo: "no había stock", que: "− 992E" }] }]
    ]);
    _facModTs = Date.now();

    // (a) la NP modificada
    const chip = facModChip("LK 0024");
    out.tieneBadge = /class="np-mod"/.test(chip) && /MOD/.test(chip);
    out.tipDice = /027: 1.*7 cajas/.test(chip) && /Dep.sito Lan.s/.test(chip) && /2 veces/.test(chip);
    out.tipAbre = /onclick="event\.stopPropagation\(\);facModVer\(/.test(chip);

    // (b) una NP que nadie tocó
    out.sinBadge = facModChip("LK 0007") === "";

    // (d) la NP de ISIS con ".0" pegado (así viene de la base en algunos lados)
    out.isisConPuntoCero = facModChip("98651.0") !== "" && _facNpKey("98651.0") === "98651";

    // (c) el detalle
    let dicho = ""; window.alert = function (m) { dicho = String(m); };
    facModVer("LK 0024");
    out.detalleQuien = /Mariana/.test(dicho);
    out.detalleQue = /Dep.sito Lan.s/.test(dicho) && /027/.test(dicho);
    out.detallePorQue = /cambió la entrega/.test(dicho) && /el cliente llamó/.test(dicho);
    out.detalleAvisaIsis = /no con el pedido original/i.test(dicho) && /Excel/.test(dicho);

    // (e) cableado: la fila de Facturación lo pinta, y la carga lo pide
    out.enLaFila = /_npSrcChip\(f\.np\)\}\$\{facModChip\(f\.np\)\}/.test(String(facRender));
    out.enLaCarga = Object.getOwnPropertyNames(window).some(function (k) {
      let v; try { v = window[k]; } catch (_e) { return false; }
      return typeof v === "function" && k !== "facFetchModif" && /facFetchModif\(\)/.test(String(v));
    });
    out.css = [...document.styleSheets].some((ss) => {
      try { return [...ss.cssRules].some((x) => /\.np-mod/.test(x.cssText)); } catch (_e) { return false; }
    });
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.vacioSinBadge, "control: sin modificaciones cargadas, ninguna NP trae badge");
  chk(r.tieneBadge, "la NP modificada trae el badge ✏ MOD en la columna NP");
  chk(r.tipDice, "el globito cuenta QUÉ se le cambió y cuántas veces");
  chk(r.tipAbre, "y tocarlo abre el detalle sin disparar el click de la fila");
  chk(r.sinBadge, "una NP que nadie tocó no trae badge ← si no, el badge no diría nada");
  chk(r.isisConPuntoCero, "la NP de ISIS matchea aunque venga como «98651.0»");
  chk(r.detalleQuien, "el detalle dice QUIÉN hizo cada cambio");
  chk(r.detalleQue, "qué cambió (incluida la dirección de entrega)");
  chk(r.detallePorQue, "y por qué");
  chk(r.detalleAvisaIsis, "y avisa que se factura con esto, no con el pedido original");
  chk(r.enLaFila, "el badge está cableado en la fila de Facturación, al lado del chip WEB/ISIS");
  chk(r.enLaCarga, "y las modificaciones se piden en la carga de Facturación");
  chk(r.css, "el CSS del badge está");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nfac-np-modificada OK");
})();
