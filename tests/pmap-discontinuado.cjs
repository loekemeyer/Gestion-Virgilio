/* v30.03 — LA GÓNDOLA DE UN CÓDIGO DISCONTINUADO SE LIBERA (Luis, 2026-10-13:
   «si una góndola está asignada a un código discontinuo … esa góndola se tiene
   que liberar … También hay algunos artículos que conviven en una misma góndola»).

   Lo que se mide, con la pantalla CORRIENDO:
   (a) la celda con un código discontinuado se marca (clase + código tachado) y la
       leyenda lo dice con PALABRAS, no sólo con el color (GV-UI 5);
   (b) el aviso de arriba cuenta las celdas y cuántas se liberan ya;
   (c) el modal de la celda dice el motivo y ofrece «Liberar», que llama a
       gv_gondola_liberar con ESA celda y ESE código;
   (d) ⚠ la celda COMPARTIDA pierde sólo al discontinuado: el otro código sigue
       dibujado y su «Liberar» no existe;
   (e) con cajas adentro la base frena (NO_VACIA) y el front pregunta antes de forzar;
   (f) «Liberar las N que están en cero» sólo manda las de accion = 'liberar_ya'. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

/* A64: el caso de Luis — el 548 solo, discontinuado y en cero → la celda se libera.
   A67: compartida — 332 discontinuado CON cajas + 338 sano.
   A01: sana. */
const FILAS = [
  { sector: "A01", gondola: "A", celda: 1, empresa: "LK", cod: "502", descripcion: "502L", cajas_max: 105, max_fuente: "item", estado: "ok", discontinuado: null, disc_accion: null, celda_liberable: false },
  { sector: "A64", gondola: "A", celda: 64, empresa: "LK", cod: "548", descripcion: "Pela Papas", cajas_max: null, max_fuente: null, estado: "solo_mapa", discontinuado: "sin_compra", disc_accion: "liberar_ya", celda_liberable: true },
  { sector: "A67", gondola: "A", celda: 67, empresa: "LK", cod: "332", descripcion: "Rallador", cajas_max: 40, max_fuente: "item", estado: "ok", discontinuado: "a_mano", disc_accion: "liquidar_primero", celda_liberable: false },
  { sector: "A67", gondola: "A", celda: 67, empresa: "LK", cod: "338", descripcion: "Espumadera", cajas_max: 25, max_fuente: "item", estado: "ok", discontinuado: null, disc_accion: null, celda_liberable: false }
];

const fail = (m) => { console.error("✗ pmap-discontinuado: " + m); process.exit(1); };

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const rpc = [];
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.route("**/rest/v1/gv_planimetria_celda*", (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(FILAS) }));
  await p.route("**/rest/v1/rpc/gv_gondola_liberar", async (r) => {
    const body = JSON.parse(r.request().postData() || "{}");
    rpc.push(body);
    // la celda con cajas frena como lo hace la base
    if (body.p_sector === "A67" && !body.p_forzar) {
      return r.fulfill({ status: 400, contentType: "application/json",
        body: JSON.stringify({ message: "NO_VACIA: 332 en A67 todavia tiene 33.0 cajas en gondola (34.0 en total): primero se liquida." }) });
    }
    r.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify([{ ok: true, id: 1, sector: body.p_sector, cod: body.p_cod, quedan_en_celda: 0, celda_libre: true }]) });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const out = await p.evaluate(async () => {
    const o = {};
    window.__isSupervisor = true;
    window.facAuthWriteHeaders = async function () { return { apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" }; };
    await openPlanimMapa();
    const cel = function (sec) {
      return [...document.querySelectorAll("#pmapGrid .pmap-cell")]
        .find((c) => ((c.querySelector(".pmap-sec") || {}).textContent || "").trim() === sec);
    };
    const a64 = cel("A64"), a67 = cel("A67"), a01 = cel("A01");
    o.a64cls = a64 ? a64.className : "(no está)";
    o.a67cls = a67 ? a67.className : "(no está)";
    o.a01cls = a01 ? a01.className : "(no está)";
    o.a64tach = a64 ? !!a64.querySelector(".pmap-cod.disc") : false;
    o.a01tach = a01 ? !!a01.querySelector(".pmap-cod.disc") : false;
    o.a64tip = a64 ? a64.getAttribute("title") : "";
    // en la compartida, tachado SOLO el discontinuado
    o.a67cods = a67 ? [...a67.querySelectorAll(".pmap-cod")].map((e) => ({ t: e.textContent.trim(), disc: e.classList.contains("disc") })) : [];
    o.leyenda = (document.getElementById("pmapLeg") || {}).textContent || "";
    const box = document.getElementById("pmapDisc");
    o.avisoVisible = box ? !box.hidden : false;
    o.aviso = box ? box.textContent : "";

    // (c) el modal de A64
    pmapAbrirCelda("A64");
    const body = document.getElementById("pmapCeldaBody");
    o.modal = body ? body.textContent : "";
    o.btnLib = body ? [...body.querySelectorAll("button")].filter((x) => /Liberar/.test(x.textContent)).map((x) => x.textContent.trim()) : [];
    const bl = body ? [...body.querySelectorAll("button")].find((x) => /Liberar/.test(x.textContent)) : null;
    if (bl) bl.click();
    await new Promise((r) => setTimeout(r, 350));

    // (d) el modal de la compartida: un solo botón Liberar, el del 332
    pmapAbrirCelda("A67");
    const b2 = document.getElementById("pmapCeldaBody");
    o.modal67 = b2 ? b2.textContent : "";
    o.btnLib67 = b2 ? [...b2.querySelectorAll("button")].filter((x) => /Liberar/.test(x.textContent)).length : -1;
    // (e) frena y pregunta
    window.confirm = function (t) { o.confirmado = t; return false; };
    const bl2 = b2 ? [...b2.querySelectorAll("button")].find((x) => /Liberar/.test(x.textContent)) : null;
    if (bl2) bl2.click();
    await new Promise((r) => setTimeout(r, 350));

    // (f) liberar todas
    window.confirm = function () { return true; };
    pmapCerrarCelda();
    await pmapLiberarTodas();
    await new Promise((r) => setTimeout(r, 350));
    return o;
  });

  const rr = JSON.stringify(rpc);
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  if (!/pmap-disc/.test(out.a64cls)) fail("(a) A64 tiene que marcarse como discontinuada: " + out.a64cls);
  if (!/pmap-disc-ok/.test(out.a64cls)) fail("(a) A64 está en cero: tiene que decir que se libera: " + out.a64cls);
  if (!/pmap-disc/.test(out.a67cls)) fail("(a) A67 tiene un discontinuado: " + out.a67cls);
  if (/pmap-disc-ok/.test(out.a67cls)) fail("(a) A67 tiene cajas: NO se libera todavía: " + out.a67cls);
  if (/pmap-disc/.test(out.a01cls)) fail("(a) A01 está sana y no se marca: " + out.a01cls);
  if (!out.a64tach) fail("(a) el código discontinuado va tachado (el color no va solo)");
  if (out.a01tach) fail("(a) el código sano no va tachado");
  if (!/DISCONTINUADO/.test(out.a64tip || "")) fail("(a) el tooltip tiene que decirlo: " + out.a64tip);
  if (!/discontinuado/i.test(out.leyenda)) fail("(a) la leyenda lo dice con palabras: " + out.leyenda);
  if (!out.avisoVisible) fail("(b) el aviso de arriba tiene que verse");
  if (!/2 celda\(s\)/.test(out.aviso) || !/1<\/b> se liberan ya|1 se liberan ya/.test(out.aviso.replace(/\s+/g, " ")))
    fail("(b) el aviso cuenta 2 celdas y 1 liberable: " + out.aviso.replace(/\s+/g, " ").slice(0, 200));
  if (!/DISCONTINUADO/.test(out.modal) || !/no se compra/.test(out.modal)) fail("(c) el modal dice el motivo: " + out.modal.slice(0, 200));
  if (out.btnLib.length !== 1 || !/Liberar$/.test(out.btnLib[0])) fail("(c) un botón «🧹 Liberar» (sin «igual», está en cero): " + JSON.stringify(out.btnLib));
  if (!/"p_sector":"A64","p_cod":"548"/.test(rr)) fail("(c) la RPC va con la celda y el código: " + rr);
  const t332 = out.a67cods.find((x) => /332/.test(x.t)), t338 = out.a67cods.find((x) => /338/.test(x.t));
  if (!t332 || !t332.disc) fail("(d) en la compartida el 332 va tachado: " + JSON.stringify(out.a67cods));
  if (!t338 || t338.disc) fail("(d) el 338 sigue sano y dibujado: " + JSON.stringify(out.a67cods));
  if (out.btnLib67 !== 1) fail("(d) en la compartida hay UN botón Liberar (el del discontinuado): " + out.btnLib67);
  if (!/NO_VACIA|cajas/.test(String(out.confirmado || ""))) fail("(e) con cajas adentro pregunta antes de forzar: " + out.confirmado);
  if (/"p_sector":"A67"[^}]*"p_forzar":true/.test(rr)) fail("(e) se dijo NO y no tiene que forzar: " + rr);
  const todas = rpc.filter((x) => x.p_sector === "A64");
  if (!todas.length) fail("(f) «Liberar las que están en cero» tiene que mandar A64: " + rr);
  if (rpc.some((x) => x.p_sector === "A67" && x.p_forzar)) fail("(f) nunca manda la que tiene cajas forzada: " + rr);
  console.log("✓ pmap-discontinuado: celda marcada, aviso, modal con el motivo, celda compartida intacta, freno con cajas y liberar en bloque");
  await b.close();
})();
