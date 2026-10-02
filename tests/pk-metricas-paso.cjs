/* v26.25 (D12, 02/10/2026) — Métricas del picking POR PASO, sin afectar la operación.

   El picking anota en `GV_Picking_Paso_Evento` (tabla aparte, con su propia cola local):
   mostrado · ok · faltan · sin_stock · adelante · atras · oculta · visible.
   Corre el picking DE VERDAD (pkRender, pkOk, pkF/pkConfirmF, pkPrev, pkNext, pkSinStock)
   y chequea:
     A. la secuencia de eventos por paso, con la celda mostrada, esp y real;
     B. un re-dibujo del MISMO paso (pantalla de «Faltan») no anota otro 'mostrado';
     C. el PKC sale IGUAL que antes (mismo texto, mismo client_id) y por la cola de siempre
        no viaja ningún evento nuevo (Registros_Produccion_Virgilio no se toca);
     D. celular bloqueado → 'oculta' + 'visible' con dur_seg;
     E. el envío: 201 vacía la cola; 500 la conserva; 400 o 409 con varios pasa a mandar de a
        uno y descarta sólo el malo; un fetch que revienta no rompe nada;
     F. con el localStorage lleno (setItem tira) el picking sigue y el PKC sale igual;
     G. la cola tiene tope (PKM_MAX) para no comerse el lugar del guardado del picking.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let modo = "ok"; const posts = [];
  await p.route("**/rest/v1/GV_Picking_Paso_Evento**", async (route) => {
    const req = route.request();
    let body = []; try { body = JSON.parse(req.postData() || "[]"); } catch (_e) {}
    posts.push({ url: req.url(), prefer: req.headers()["prefer"] || "", n: body.length, body });
    if (modo === "ok") return route.fulfill({ status: 201, body: "" });
    if (modo === "500") return route.fulfill({ status: 500, body: "{}" });
    if (modo === "abort") return route.abort();
    if (modo === "400malo" || modo === "409dup") {   // rechaza el lote si trae el renglón marcado
      const malo = body.some((x) => x.paso === "MALO");
      const st = modo === "409dup" ? 409 : 400;
      return route.fulfill({ status: malo ? st : 201, body: malo ? '{"code":"23505"}' : "" });
    }
    return route.fulfill({ status: 201, body: "" });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof pkmEvento === "function" && typeof pkRender === "function");

  const r = await p.evaluate(async () => {
    const out = {}; const sent = [];
    window.enqueueReport = function (pl) { sent.push(pl); };
    window.trySendOneReport = null;
    window.updatePendingIndicator = function () {};
    localStorage.removeItem("gv_pkm_q_v1");
    const tm = document.getElementById("tandaModal"); if (tm) tm.style.display = "flex";

    _pk = { tanda: "E48K", legajo: "104", idx: 0, mode: "item", excOk: true, results: {},
      items: [
        { art: "501", key: "501", esp: 9, sector: "A11" },
        { art: "586", key: "586", esp: 10, sector: "B25" },
        { art: "508", key: "508", esp: 1, sector: "A74" }
      ] };
    pkRender();                                   // mostrado 0
    pkOk();                                       // ok 0 → mostrado 1
    pkF();                                        // re-dibuja el MISMO paso: no anota mostrado
    document.getElementById("pkFqty").value = "7";
    pkConfirmF();                                 // faltan 1 (real 7) → mostrado 2
    pkPrev();                                     // atras → mostrado 1
    pkNext();                                     // adelante → mostrado 2
    pkSinStock();                                 // sin_stock 2 → mostrado resumen
    const q = pkmQLeer();
    out.secuencia = q.map((x) => x.evento + ":" + (x.paso || x.nota)).join(" ");
    out.secuenciaOk = out.secuencia ===
      "mostrado:501 ok:501 mostrado:586 faltan:586 mostrado:508 atras:508 mostrado:586 adelante:586 mostrado:508 sin_stock:508 mostrado:resumen";
    const ok0 = q.find((x) => x.evento === "ok"), fal = q.find((x) => x.evento === "faltan"), ss = q.find((x) => x.evento === "sin_stock");
    out.camposOk = !!(ok0 && ok0.sector === "A11" && ok0.esp === 9 && ok0.real === 9 && ok0.es_exc === false &&
      ok0.tanda === "E48K" && ok0.legajo === "104" && ok0.art === "501" && /^\d{4}-\d\d-\d\dT/.test(ok0.ts_cliente));
    out.faltanOk = !!(fal && fal.real === 7 && fal.esp === 10 && fal.sector === "B25");
    out.sinStockOk = !!(ss && ss.real === 0);
    out.idsUnicos = new Set(q.map((x) => x.client_id)).size === q.length;

    // C. el PKC sale igual que siempre y por la cola de siempre no viaja nada nuevo
    out.pkcTextos = sent.map((x) => x.texto).join(" ");
    out.pkcOk = sent.length === 3 && sent.every((x) => x.opcion === "PKC") &&
      out.pkcTextos === "E48K|501|9|9|0 E48K|586|10|7|0 E48K|508|1|0|0" &&
      sent[0].id.indexOf("pkc_104_E48K_501_") === 0;

    // D. celular bloqueado
    let vis = "hidden";
    Object.defineProperty(document, "visibilityState", { configurable: true, get: () => vis });
    _pk = { tanda: "E48K", legajo: "104", idx: 1, mode: "item", excOk: true, results: {},
      items: [{ art: "501", key: "501", esp: 9, sector: "A11" }, { art: "586", key: "586", esp: 10, sector: "B25" }] };
    document.dispatchEvent(new Event("visibilitychange"));
    await new Promise((res) => setTimeout(res, 1100));
    vis = "visible";
    document.dispatchEvent(new Event("visibilitychange"));
    // 'oculta' manda la cola en el acto (keepalive): se mira lo enviado + lo que quedó, afuera.
    return out;
  });

  // E. envío
  await p.waitForTimeout(400);
  let rr = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    let i = 0; while (_pkmEnvio && i++ < 40) await espera(50);
    const antes = pkmQLeer().length; pkmFlush(false);
    i = 0; while ((_pkmEnvio || pkmQLeer().length) && i++ < 60) await espera(50);
    return { antes, despues: pkmQLeer().length };
  });
  const enviados = posts.flatMap((x) => x.body);
  r.envioOk = rr.despues === 0 && enviados.length >= 13 &&
    posts.every((x) => !/on_conflict/.test(x.url) && /return=minimal/.test(x.prefer)) &&
    new Set(enviados.map((x) => x.client_id)).size === enviados.length;
  r.envioDetalle = posts.map((x) => x.body.map((y) => y.evento).join(",")).join(" | ");
  const oc = enviados.filter((x) => x.evento === "oculta"), vi = enviados.filter((x) => x.evento === "visible");
  r.ocultaOk = oc.length === 1 && oc[0].paso === "586" && oc[0].tanda === "E48K";
  r.ocultaSaleEnElActo = posts.length > 0 && posts[0].body.some((x) => x.evento === "oculta");
  r.visibleOk = vi.length === 1 && vi[0].dur_seg >= 1 && vi[0].paso === "586";

  modo = "500";
  rr = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    pkmEvento("mostrado", { key: "X1", art: "X1", esp: 1 });
    let i = 0; while (_pkmEnvio && i++ < 40) await espera(50);
    pkmFlush(false); await espera(300); i = 0; while (_pkmEnvio && i++ < 40) await espera(50);
    return pkmQLeer().length;
  });
  r.conserva500 = rr === 1;

  modo = "abort";
  rr = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    pkmFlush(false); await espera(300); let i = 0; while (_pkmEnvio && i++ < 40) await espera(50);
    return pkmQLeer().length;
  });
  r.conservaAbort = rr === 1;

  modo = "400malo";
  rr = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    pkmEvento("mostrado", { key: "MALO", art: "MALO", esp: 1 });
    pkmEvento("mostrado", { key: "X2", art: "X2", esp: 1 });
    let i = 0;
    while (pkmQLeer().length && i++ < 80) { if (!_pkmEnvio) pkmFlush(false); await espera(80); }
    return { resto: pkmQLeer().length, deA1: _pkmDeA1 };
  });
  r.descartaSoloElMalo = rr.resto === 0 && posts.some((x) => x.n === 1 && x.body[0].paso === "X2" && x.prefer);

  // 409 = ya estaba (client_id único): de a uno, se descarta el duplicado y entra el nuevo
  modo = "409dup"; const desde = posts.length;
  rr = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    pkmEvento("mostrado", { key: "MALO", art: "MALO", esp: 1 });
    pkmEvento("mostrado", { key: "X3", art: "X3", esp: 1 });
    let i = 0;
    while (pkmQLeer().length && i++ < 80) { if (!_pkmEnvio) pkmFlush(false); await espera(80); }
    return { resto: pkmQLeer().length };
  });
  r.dup409 = rr.resto === 0 && posts.slice(desde).some((x) => x.n === 1 && x.body[0].paso === "X3");

  // F. localStorage lleno: el picking sigue y el PKC sale igual
  r.lleno = await p.evaluate(() => {
    const sent = []; window.enqueueReport = function (pl) { sent.push(pl); };
    const orig = Storage.prototype.setItem;
    Storage.prototype.setItem = function (k, v) { if (k === "gv_pkm_q_v1") throw new Error("QuotaExceededError"); return orig.call(this, k, v); };
    let ok = true;
    try {
      _pk = { tanda: "F22A", legajo: "104", idx: 0, mode: "item", excOk: true, results: {},
        items: [{ art: "513", key: "513", esp: 7, sector: "F30" }, { art: "505", key: "505", esp: 1, sector: "D18" }] };
      pkRender(); pkOk();
    } catch (e) { ok = false; }
    Storage.prototype.setItem = orig;
    return ok && _pk && _pk.idx === 1 && sent.length === 1 && sent[0].texto === "F22A|513|7|7|0";
  });

  // G. tope de la cola
  r.tope = await p.evaluate(() => {
    localStorage.removeItem("gv_pkm_q_v1");
    const orig = window.fetch; window.fetch = () => new Promise(() => {});   // nada sale
    _pkmEnvio = true;   // y nada intenta salir
    for (let i = 0; i < PKM_MAX + 150; i++) pkmEvento("mostrado", { key: "T" + i, art: "T" + i, esp: 1 });
    const q = pkmQLeer(); window.fetch = orig; _pkmEnvio = false;
    return q.length === PKM_MAX && q[q.length - 1].paso === "T" + (PKM_MAX + 149);
  });

  await b.close();
  const ok = r.secuenciaOk && r.camposOk && r.faltanOk && r.sinStockOk && r.idsUnicos && r.pkcOk &&
    r.ocultaOk && r.ocultaSaleEnElActo && r.visibleOk && r.envioOk && r.conserva500 && r.conservaAbort && r.descartaSoloElMalo && r.dup409 &&
    r.lleno && r.tope && !errs.length;
  console.log("pk-metricas-paso:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
