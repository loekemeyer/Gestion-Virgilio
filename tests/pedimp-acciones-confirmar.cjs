/* v24.64 (Thomas) — 📦 y 📥 son íconos sin texto: al tocarlos sale un pop-up que dice qué hacen,
   y recién al confirmar se abren. Cancelar no abre nada. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const it = { cod: "503E", prov: "Ownland", key: "503E", desc: "Abrelatas", proyUni: 300, objetivoUni: 3000, stockUni: 500, enCurso: 1200, meses: 10,
      aPedirUni: 1300, uniMaster: 100, uxc: 12, fobUni: 0.5, m3Master: 0.05, det: [{ id: 7, curso: 1200, marca: "LK" }] };
    it.aPedirCajas = 13;
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: [it], meses: 10, minUsd: 25000, nac: { modo: "consolidada", valorM3: 110, tn: 0 } }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const llam = [];
    window.impRecibirAbrir = (id) => llam.push("recibir:" + id);
    window.pedImpBaches = (id) => llam.push("baches:" + id);
    const btn = (t) => [...document.querySelectorAll("#stkPopBody tbody button")].find((x) => x.textContent.trim() === t);
    const out = {};
    btn("📥").click();
    const ov = document.getElementById("pedImpAccOv");
    out.pop = !!ov; out.txt = ov ? ov.textContent : ""; out.antes = llam.length;
    ov.querySelector(".pedimp-acc-no").click();
    out.trasCancel = llam.length + (document.getElementById("pedImpAccOv") ? "+abierto" : "");
    btn("📥").click(); document.querySelector("#pedImpAccOv .pedimp-acc-si").click();
    btn("📦").click(); out.txtB = document.getElementById("pedImpAccOv").textContent; document.querySelector("#pedImpAccOv .pedimp-acc-si").click();
    out.llam = llam.join(",");
    return out;
  });
  if (!r.pop) fail("tocar 📥 tiene que abrir el pop-up de confirmación");
  if (!/Recibir/.test(r.txt) || !/503E/.test(r.txt) || !/LLEGÓ/.test(r.txt)) fail("el pop-up dice qué hace y de qué código: " + r.txt);
  if (r.antes !== 0) fail("sin confirmar no tiene que abrir nada");
  if (r.trasCancel !== "0") fail("Cancelar cierra y no abre nada: " + r.trasCancel);
  if (!/Baches/.test(r.txtB)) fail("el de 📦 explica Baches: " + r.txtB);
  if (r.llam !== "recibir:7,baches:7") fail("confirmando se abren los dos: " + r.llam);
  await b.close();
  if (!process.exitCode) console.log("✓ pedimp-acciones-confirmar: 📦 y 📥 piden confirmar");
})();
