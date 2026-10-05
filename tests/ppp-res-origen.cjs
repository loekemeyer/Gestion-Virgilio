/* v27.01 (Luis, 05/10) — el Resumen de la PPP dice el ORDEN DE PRIORIDAD del armado
   automático y, al tocar una celda, CÓMO llegó cada NP a ese día: automático (con la regla) o
   A MANO (quién y cuándo). Se corre la pantalla: se dibuja el Resumen, se clickean la celda
   de zona y la de camiones, y se lee el pop-up. Sin la RPC, la columna dice «—» (no inventa). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setViewportSize({ width: 1400, height: 900 });
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "load" });

  const r = await p.evaluate(() => {
    const ped = function (np, rs, loc, m3, recep, entrega, tanda) {
      return { np: np, tanda: tanda, cod: rs, razon_social: rs, m3: m3, localidad: loc, zona: "", fecha: recep, fecha_entrega: entrega, programmed: true };
    };
    const prog = [
      ped("LK 0221", "Laza Ariel", "Ituzaingo", 0.009, "07/09/2026", "09/12/2026", "F30A"),
      ped("LK 0300", "Cli Auto", "Ituzaingo", 0.5, "01/12/2026", "09/12/2026", "F31A"),
      ped("98700", "Cli Isis", "Ituzaingo", 0.3, "01/12/2026", "09/12/2026", "F32A")
    ];
    const out = {};
    // sin la RPC todavía: la columna existe y dice «—»
    _pppNpOrig = null;
    let host = document.createElement("div"); host.innerHTML = pppResumenHtml(prog); document.body.appendChild(host);
    out.orden = !!host.querySelector("details.ppp-res-orden") && /prioridad/i.test(host.querySelector("details.ppp-res-orden summary").textContent);
    out.ordenItems = host.querySelectorAll("details.ppp-res-orden li").length;
    const celdaZ5 = [...host.querySelectorAll(".ppp-restbl td.z5.zc")][0];
    celdaZ5.click();
    let ov = document.getElementById("pppResPopOv");
    out.sinRpc = [...ov.querySelectorAll("td.orig")].map(function (t) { return t.textContent.trim(); });
    // con la RPC
    _pppNpOrig = {
      "LK 0221": { np: "LK 0221", origen: "manual", por: "loekemeyer.n8n@gmail.com", cuando: "2026-09-29T10:32:39Z", regla: "Programada o movida A MANO (espera el importado que llega el 29/11)." },
      "LK 0300": { np: "LK 0300", origen: "automatico", por: null, cuando: null, regla: "Grupo de zonas: sale con el camión de su grupo." }
    };
    _pppNpOrigTs = Date.now();
    host.remove(); host = document.createElement("div"); host.innerHTML = pppResumenHtml(prog); document.body.appendChild(host);
    [...host.querySelectorAll(".ppp-restbl td.z5.zc")][0].click();
    ov = document.getElementById("pppResPopOv");
    out.th = [...ov.querySelectorAll("thead th")].map(function (t) { return t.textContent.trim(); });
    out.conRpc = {};
    [...ov.querySelectorAll(".pppres-tbl tbody tr")].forEach(function (tr) { out.conRpc[tr.children[0].textContent.trim()] = tr.querySelector("td.orig").textContent.replace(/\s+/g, " ").trim(); });
    [...host.querySelectorAll(".ppp-restbl td.cam")][0].click();
    ov = document.getElementById("pppResPopOv");
    out.cam = [...ov.querySelectorAll(".pppres-tbl tbody tr:not(.camh) td.orig")].map(function (t) { return t.textContent.replace(/\s+/g, " ").trim(); });
    // v27.05: con pauta, botoncito P# que abre por qué frenó y por qué no siguió
    _pppNpOrig["LK 0300"] = { np: "LK 0300", pauta: "P14a", titulo: "Su grupo ya sale en el plazo", fuente: "registrada", origen: "automatico",
      motivo: "Su grupo (GBA Oeste) ya tenía camión el 08/10.", previas: "P1 a P13 no la frenaron.", no_siguiente: "No pasó a P14b porque su grupo sale en el plazo.", tanda_info: "Tanda F31A: 1 NP" };
    host.remove(); host = document.createElement("div"); host.innerHTML = pppResumenHtml(prog); document.body.appendChild(host);
    [...host.querySelectorAll(".ppp-restbl td.z5.zc")][0].click();
    ov = document.getElementById("pppResPopOv");
    const btn = [...ov.querySelectorAll("button.pauta-b")].find(function (x) { return x.textContent === "P14a"; });
    out.btn = !!btn;
    if (btn) { btn.click(); const pv = document.getElementById("pppPautaOv"); out.pop = pv ? pv.textContent.replace(/\s+/g, " ") : ""; out.popVis = pv && pv.style.display === "flex"; }
    out.ordenP = [...host.querySelectorAll("details.ppp-res-orden li b")].map(function (x) { return x.textContent; });
    return out;
  });

  const f = [];
  if (!r.orden) f.push("no está el desplegable con el orden de prioridad del armado");
  if (r.ordenItems < 8) f.push("el orden de prioridad trae " + r.ordenItems + " pasos");
  if (!r.sinRpc.length || r.sinRpc.some(function (t) { return t !== "—"; })) f.push("sin la RPC tiene que decir «—»: " + JSON.stringify(r.sinRpc));
  if (!r.th.some(function (t) { return /Cómo llegó/.test(t); })) f.push("falta la columna «Cómo llegó a este día»: " + r.th.join("|"));
  const lk221 = r.conRpc["LK 0221"] || "";
  if (!/A mano/.test(lk221) || !/loekemeyer\.n8n/.test(lk221) || !/29\/09/.test(lk221)) f.push("LK 0221 no dice a mano, quién y cuándo: " + lk221);
  if (!/Automático/.test(r.conRpc["LK 0300"] || "") || !/Grupo de zonas/.test(r.conRpc["LK 0300"] || "")) f.push("LK 0300 no dice automático con su regla: " + r.conRpc["LK 0300"]);
  if (!/ISIS/.test(r.conRpc["98700"] || "")) f.push("98700 no dice ISIS: " + r.conRpc["98700"]);
  if (r.cam.length !== 3 || !r.cam.some(function (t) { return /A mano/.test(t); })) f.push("el pop-up de camiones no trae el origen: " + JSON.stringify(r.cam));
  if (!r.btn) f.push("no está el botón P14a en la celda");
  if (!r.popVis || !/GBA Oeste/.test(r.pop || "") || !/No pasó a P14b/.test(r.pop || "") || !/Tanda F31A/.test(r.pop || "")) f.push("el pop-up de la pauta no dice por qué frenó / por qué no siguió: " + r.pop);
  if ((r.ordenP || [])[0] !== "P1" || (r.ordenP || []).indexOf("P24") < 0) f.push("el orden no va numerado P1..P24: " + JSON.stringify(r.ordenP));
  if (errs.length) f.push("pageerrors: " + errs.join(" | "));
  console.log("ppp-res-origen:", JSON.stringify(r.conRpc));
  if (f.length) console.log("  ✗ " + f.join("\n  ✗ "));
  console.log(f.length ? "· ✗ FALLÓ" : "· ✓ OK");
  await b.close();
  process.exit(f.length ? 1 : 0);
})();
