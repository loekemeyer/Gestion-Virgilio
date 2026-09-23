/* v21.42 (Luis, 2026-09-23) — la Recepción de Remitos que abre el SUPERVISOR desde el panel no
   puede firmar con legajo "0": el sistema entero toma 0 y 1 como legajos de prueba
   (`es_legajo_test`), así que ese CRN no contaba, el pedido nunca pasaba a Entregado y quedaba
   en Ocupación con la fecha vieja (E12C el 18/09) mientras Programación ya lo daba por salido.
   Chequea: (1) estático, openRemitosAdmin ya no llama showControlRemitos("0"…);
            (2) en vivo, gvLegajoSupervisor() firma con el mail y nunca con 0/1. */
const path = require("path"), fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const fallas = [];
if (/showControlRemitos\(\s*"0"\s*,\s*true\s*\)/.test(src)) fallas.push("openRemitosAdmin vuelve a firmar con legajo \"0\"");
if (!/function gvLegajoSupervisor/.test(src)) fallas.push("falta gvLegajoSupervisor");
if (fallas.length) { console.log("rr-supervisor-legajo: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.log("rr-supervisor-legajo: estático ✓ OK"); process.exit(0); } }
(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext()).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, headers: { "content-type": "application/json" }, body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    window.__authEmail = "Supervisora@Loekemeyer.com"; out.conMail = gvLegajoSupervisor();
    window.__authEmail = ""; __identity = { type: "supervisor", email: "otro@x.com", nombre: "otro@x.com" }; out.conIdentity = gvLegajoSupervisor();
    __identity = null; out.sinNada = gvLegajoSupervisor();
    return out;
  });
  await b.close();
  const mal = [];
  if (r.conMail !== "sup:supervisora@loekemeyer.com") mal.push("con mail autenticado firma «" + r.conMail + "»");
  if (r.conIdentity !== "sup:otro@x.com") mal.push("con __identity firma «" + r.conIdentity + "»");
  if (!r.sinNada || /^(0|1)$/.test(r.sinNada)) mal.push("sin identidad firma «" + r.sinNada + "» (nunca puede ser 0 ni 1)");
  if (errs.length) mal.push("errores de página: " + errs.join(" | "));
  if (mal.length) { console.log("rr-supervisor-legajo: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("rr-supervisor-legajo: ✓ OK (el supervisor firma el CRN con su mail, nunca con legajo 0)");
})().catch((e) => { console.log("rr-supervisor-legajo: ✗ ERROR " + (e && e.message || e)); process.exit(1); });
