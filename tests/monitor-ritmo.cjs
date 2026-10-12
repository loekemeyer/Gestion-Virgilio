/* v29.47 — Monitor → pestaña «Ritmo» (plantel.js, RPC gv_ritmo_picking). Corre la pantalla de verdad
   dentro de index.html con la RPC mockeada y mide:
     (a) la pestaña está en el monitor y setMonitorTab('ritmo') la muestra y llama a la RPC;
     (b) el rendimiento total va en % (esperado ÷ real) y en verde si llegó, rojo si no;
     (c) las horas van en H:MM; la tabla por operario sale como la manda la base;
     (d) tocar un día abre sus operarios;
     (e) sin sesión de supervisor lo DICE (no dibuja ceros);
     (f) en modo kiosko (pared) las pestañas del monitor no se ven.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const DATA = {
  desde: "2026-09-29", hasta: "2026-10-12", hoy: "2026-10-12",
  total: { tandas: 63, est_ini_min: 1958.8, esperado_min: 1878, real_min: 1579.7, real_ini_min: 1579.7, mon_min: 2161.8, indice: 1.189, indice_ini: 1.24, indice_mon: 0.869 },
  operarios: [
    { legajo: "104", nombre: "Jhonny Moncayo", dias: 8, tandas: 49, est_ini_min: 1485.1, esperado_min: 1403.4, real_min: 999.4, mon_min: 1435.2, perdida_min: 435.8, indice: 1.404, indice_mon: 0.978, dias_llego: 7, dias_medidos: 8 },
    { legajo: "94", nombre: "Isidro Tevez", dias: 2, tandas: 4, est_ini_min: 159.8, esperado_min: 164.4, real_min: 286.4, mon_min: 338.4, perdida_min: 52, indice: 0.574, indice_mon: 0.486, dias_llego: 0, dias_medidos: 2 }
  ],
  dias: [{ dia: "2026-10-09", ops: 1, tandas: 6, est_ini_min: 144.6, esperado_min: 133.7, real_min: 100.2, mon_min: 100.2, indice: 1.334 }],
  filas: [{ dia: "2026-10-09", legajo: "277", nombre: "Jhonny Cartaya", tandas: 6, est_ini_min: 144.6, esperado_min: 133.7, real_min: 100.2, mon_min: 100.2, indice: 1.335 }]
};

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1300, height: 900 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const o = await p.evaluate(async (DATA) => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.ritmoCargar !== "function"; i++) await espera(100);
    const r = {};
    let modo = "ok", llamadas = [];
    window.sb = { rpc: async (n, a) => { llamadas.push([n, a]);
      if (modo === "sup") return { data: null, error: { message: "SUPERVISOR: el ritmo por operario es sólo para supervisores" } };
      return n === "gv_ritmo_picking" ? { data: DATA, error: null } : { data: null, error: { message: "?" } }; } };
    r.boton = !!document.getElementById("monTabRitmo");
    setMonitorTab("ritmo");
    for (let i = 0; i < 40 && !(_ritmo.data || _ritmo.err); i++) await espera(50);
    const box = document.getElementById("ritmoContent");
    r.visible = !box.classList.contains("hidden");
    r.llamo = llamadas.some((l) => l[0] === "gv_ritmo_picking" && l[1] && /^\d{4}-\d{2}-\d{2}$/.test(l[1].p_desde));
    r.txt = box.textContent;
    const cards = [...box.querySelectorAll(".rt-card b")];
    r.pct = cards[0] && cards[0].textContent; r.pctCol = cards[0] && cards[0].style.color;
    const filasOp = [...box.querySelectorAll(".rt-tbl")][0].querySelectorAll("tbody tr");
    r.op1 = filasOp[0] && filasOp[0].textContent; r.op2col = filasOp[1] && filasOp[1].children[5].style.color;
    box.querySelector("tr.dia").click(); await espera(30);
    r.sub = [...box.querySelectorAll("tr.sub")].map((x) => x.textContent).join("|");
    modo = "sup"; ritmoCargar();
    for (let i = 0; i < 40 && !_ritmo.err; i++) await espera(50);
    r.err = box.textContent;
    /* openMonitor exige supervisor: se mira que la pestaña viva DENTRO de monTabSwitch y que el kiosko lo oculte */
    r.kiosko = (/__tvKioskMode \? "none"/.test(String(openMonitor)) && !!document.getElementById("monTabRitmo").closest("#monTabSwitch")) ? "none" : "visible";
    return r;
  }, DATA);
  await b.close();
  const f = [];
  const ok = (c, m) => { if (!c) f.push(m); };
  ok(o.boton, "(a) falta la pestaña Ritmo en el monitor");
  ok(o.visible && o.llamo, "(a) setMonitorTab('ritmo') no mostró la pestaña o no llamó a gv_ritmo_picking");
  ok(o.pct === "119 %", "(b) rendimiento total: " + o.pct + " (esperado 119 %)");
  ok(/21, 128, 61|#15803d/.test(o.pctCol || ""), "(b) 119 % tiene que ir en verde: " + o.pctCol);
  ok(/31:18/.test(o.txt) && /26:20/.test(o.txt) && /36:02/.test(o.txt), "(c) horas esperadas 31:18, reales 26:20 y monitor 36:02 en H:MM");
  ok(/Jhonny Moncayo/.test(o.op1 || "") && /140 %/.test(o.op1 || "") && /7 de 8/.test(o.op1 || ""), "(c) fila de Moncayo: " + o.op1);
  ok(/185, 28, 28|#b91c1c/.test(o.op2col || ""), "(c) Isidro 57 % va en rojo: " + o.op2col);
  ok(/Jhonny Cartaya/.test(o.sub) && /134 %/.test(o.sub), "(d) el día abre sus operarios: " + o.sub);
  ok(/sólo para supervisores/.test(o.err) && !/119 %/.test(o.err), "(e) sin sesión de supervisor tiene que decirlo");
  ok(o.kiosko === "none", "(f) en el kiosko las pestañas del monitor se ocultan: " + o.kiosko);
  ok(!errs.length, "errores de página: " + errs.join(" | "));
  if (f.length) { console.log("FALLA monitor-ritmo:\n  " + f.join("\n  ")); process.exit(1); }
  console.log("OK monitor-ritmo");
})().catch((e) => { console.error(e); process.exit(1); });
