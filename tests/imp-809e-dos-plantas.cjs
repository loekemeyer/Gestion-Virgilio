/* v22.93 — 809E en LK y 809E en CH son DOS productos (Thomas, 26/09: "no es lo mismo 809E en LK y 809E
   en CH"): cambia el packaging y el FOB (0,70 LK / 0,47 CH). ocgFetchImportados los sumaba en una línea y
   el sobrante de Loeke tapaba lo que le falta a Chef: pedía 372 u cuando Chef solo necesita 3.120.

   Chequea, sin red:
   - dos ítems 809E (clave 809E|CH y 809E|LK), cada uno con SU proyección, stock, en curso, FOB y reingreso;
   - a pedir CH = 10.800 − 480 − 7.200 = 3.120 · LK = 0 (y no 372 sumados);
   - un código de una sola planta sigue igual (clave = código, sin planta);
   - el MC tipeado en una línea no mueve la otra;
   - editar el FOB de la línea CH escribe SÓLO la fila de Chef (id=in.(129)), no cod_art=eq.809E;
   - en Pedidos se ven las dos líneas con su chip LK / CH, y en la sección de OC la de CH;
   - «Cargar pedido ya hecho»: "809E CH 1224" cae en la fila de Chef y "809E LK 144" en la de Loeke.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async function () {
    const base = { proveedor: "Ownland", uni_x_caja: 12, meses_objetivo: 10, stock_insumos: 0, principal: true, activo: true, cajas_pedidas: 0, unidades_pedidas: 0 };
    const ORD = [
      Object.assign({}, base, { id: 129, cod_art: "809E", marca: "CH", descripcion: "Corta Queso", fob_uni: 0.47, est_madre_eff: 1080,
        stock_actual: 480, stock_cajas: 40, stock_cajas_bruto: 40, stock_total: 480, pedido_curso: 7200 }),
      Object.assign({}, base, { id: 100, cod_art: "809E", marca: "LK", descripcion: "Corta Queso", fob_uni: 0.7, est_madre_eff: 300,
        stock_actual: 4116, stock_cajas: 343, stock_cajas_bruto: 343, stock_total: 4116, pedido_curso: 1632 }),
      Object.assign({}, base, { id: 7, cod_art: "598E", marca: "LK", proveedor: "Hugo Wong", descripcion: "Pelador Negro", fob_uni: 0.3,
        est_madre_eff: 100, stock_actual: 200, stock_cajas: 17, stock_cajas_bruto: 17, stock_total: 200, pedido_curso: 0 })
    ];
    const REING = [{ cod_art: "809E", marca: "CH", reingreso_est: "2026-12-18" }, { cod_art: "809E", marca: "LK", reingreso_est: "2026-11-01" }];
    const VOL = [{ cod: "809E", largo_cm: 44, ancho_cm: 26, alto_cm: 28, m3_master: 0.032032, uni_master: 144 }];
    const calls = [];
    window.fetch = function (u, o) {
      const s = String(u); calls.push({ u: s, m: (o && o.method) || "GET", b: o && o.body });
      let body = [];
      if (s.indexOf("gv_importados_ordenes") >= 0) body = ORD;
      else if (s.indexOf("/rest/v1/Importados?") >= 0 && s.indexOf("reingreso_est=not.is.null") >= 0) body = REING;
      else if (s.indexOf("/rest/v1/Importados_Volumen") >= 0) body = VOL;
      else if ((o && o.method) === "PATCH") body = [{ ok: 1 }];
      return Promise.resolve({ ok: true, status: 200,
        headers: { get: function (h) { return String(h).toLowerCase() === "content-range" ? "0-" + Math.max(0, body.length - 1) + "/" + body.length : null; } },
        json: function () { return Promise.resolve(body); }, text: function () { return Promise.resolve(JSON.stringify(body)); } });
    };
    const out = {};
    const g = await ocgFetchImportados();
    const pick = (k) => (g.items || []).find((x) => x.key === k) || null;
    const ch = pick("809E|CH"), lk = pick("809E|LK"), n = pick("598E");
    out.n809 = (g.items || []).filter((x) => x.cod === "809E").length;
    out.ch = ch && { planta: ch.planta, proy: ch.proyUni, stock: ch.stockUni, curso: ch.enCurso, aPedir: ch.aPedirUni, fob: ch.fobUni, reing: ch.reingresoEst, ids: ch.det.map((d) => d.id) };
    out.lk = lk && { planta: lk.planta, proy: lk.proyUni, stock: lk.stockUni, curso: lk.enCurso, aPedir: lk.aPedirUni, fob: lk.fobUni, reing: lk.reingresoEst, ids: lk.det.map((d) => d.id) };
    out.normal = n && { key: n.key, planta: n.planta, aPedir: n.aPedirUni };

    // pantalla Pedidos, buscando 809E (el término gana sobre "Solo Pedido")
    await openPedidosImportacion();
    _stkPop.data = g;
    pedImpSetQ("809E");
    const filas = [...document.querySelectorAll("#stkPopBody tr")].filter((tr) => /809E/.test(tr.innerText) && tr.querySelector("input[type=number]"));
    out.filasPantalla = filas.map((tr) => tr.innerText.replace(/\s+/g, " ").slice(0, 40));
    out.chips = filas.map((tr) => { const sp = [...tr.querySelectorAll("td:first-child span")].find((x) => /^(LK|CH)$/.test(x.innerText.trim())); return sp ? sp.innerText.trim() : null; });

    // MC por línea
    pedImpSetMC(encodeURIComponent("809E|CH"), 5);
    out.mcCh = _pedImpMcOf(ch); out.mcLk = _pedImpMcOf(lk);

    // FOB de la línea CH → sólo la fila 129
    window.prompt = () => "0.5";
    window.facAuthWriteHeaders = async (h) => Object.assign({ apikey: "x", Authorization: "Bearer y" }, h || {});
    calls.length = 0;
    await pedImpEditFob(encodeURIComponent("809E|CH"));
    out.patchFob = calls.filter((c) => c.m === "PATCH").map((c) => c.u.split("/rest/v1/")[1]);

    // sección importados del generador de OC
    _oc = { gen: { imp: g, items: [] }, genFiltro: "" };
    const oc = document.createElement("div"); oc.innerHTML = ocBodyGenImportados();
    const ocFila = [...oc.querySelectorAll("tr")].find((tr) => /809E/.test(tr.innerText));
    out.ocFila = ocFila ? ocFila.innerText.replace(/\s+/g, " ").slice(0, 60) : null;

    // Cargar pedido ya hecho
    const it = _pedHechoItem("809E");
    out.hechoDets = it ? it.det.map((d) => d.id + ":" + d.marca).sort() : null;
    _pedHecho = { modo: "texto", texto: "809E CH 1224\n809E LK 144", prov: "Ownland", sel: {} };
    out.hechoTexto = _pedHechoLineas().map((l) => l.cod + " " + l.marca + " → " + (l.det ? l.det.id : null) + (l.err ? " (" + l.err + ")" : ""));
    _pedHecho = { modo: "lista", prov: "Ownland", sel: { "809E|CH": "1224" }, q: "" };
    out.hechoLista = _pedHechoLineas().map((l) => l.cod + " " + l.marca + " → " + (l.det ? l.det.id : null));
    return out;
  });

  await b.close();
  const fallas = [];
  const ok = function (c, m) { console.log((c ? "  ok   " : "  FALLA") + " · " + m); if (!c) fallas.push(m); };
  ok(r.n809 === 2, "809E sale en DOS líneas (dio " + r.n809 + ")");
  ok(r.ch && r.ch.planta === "CH" && r.ch.aPedir === 3120, "CH: a pedir 3.120 (10.800 − 480 − 7.200) · dio " + JSON.stringify(r.ch));
  ok(r.lk && r.lk.planta === "LK" && r.lk.aPedir === 0, "LK: a pedir 0 (le sobra) · dio " + JSON.stringify(r.lk));
  ok(r.ch && r.ch.fob === 0.47 && r.lk && r.lk.fob === 0.7, "cada línea con su FOB (CH 0,47 · LK 0,70)");
  ok(r.ch && r.ch.reing === "2026-12-18" && r.lk && r.lk.reing === "2026-11-01", "cada línea con su reingreso");
  ok(r.ch && r.ch.ids.join() === "129" && r.lk && r.lk.ids.join() === "100", "cada línea con SU fila del maestro (129 / 100)");
  ok(r.normal && r.normal.key === "598E" && !r.normal.planta && r.normal.aPedir === 800, "un código de una sola planta no cambia (598E, a pedir 800) · " + JSON.stringify(r.normal));
  ok(r.filasPantalla.length === 2, "en Pedidos se ven 2 líneas de 809E · " + JSON.stringify(r.filasPantalla));
  ok((r.chips || []).slice().sort().join() === "CH,LK", "cada línea con su chip LK / CH · " + JSON.stringify(r.chips));
  ok(r.mcCh === 5 && r.mcLk !== 5, "el MC tipeado en CH no mueve LK (CH " + r.mcCh + " · LK " + r.mcLk + ")");
  ok(r.patchFob.length === 1 && /^Importados\?id=in\.\(129\)$/.test(r.patchFob[0]), "el FOB de CH escribe sólo la fila 129 · " + JSON.stringify(r.patchFob));
  ok(!!r.ocFila && /CH/.test(r.ocFila) && /3120/.test(r.ocFila.replace(/\./g, "")), "la sección importados de OC muestra 809E CH con 3.120 · " + r.ocFila);
  ok(r.hechoDets && r.hechoDets.join() === "100:LK,129:CH", "Cargar pedido ve las dos marcas · " + JSON.stringify(r.hechoDets));
  ok(r.hechoTexto.join("|") === "809E CH → 129|809E LK → 100", "texto: 809E CH → 129 · 809E LK → 100 · " + JSON.stringify(r.hechoTexto));
  ok(r.hechoLista.join("|") === "809E CH → 129", "lista: 809E|CH → 129 · " + JSON.stringify(r.hechoLista));
  ok(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fallas.length) { console.log("imp-809e-dos-plantas: " + fallas.length + " FALLA(S)"); process.exit(1); }
  console.log("imp-809e-dos-plantas: OK");
})();
