/* v14.81 — SUBMÓDULO CUARENTENA (idea usuario 8877). El sector aparece SIEMPRE en A Programar
   (paso 1). Un pedido marcado (deuda / suspendido / supera crédito) sale de "Pedidos a
   programar", cae en Cuarentena con badge y NO se puede tildar. Estado inyectado. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    _apr.listo = true; _apr.tandas = []; _apr.items = {}; _apr.salida = {};
    _apr.cal = [{ dia: "2026-09-14", habil: true, m3: 1, tandas: 1, np: 2, cupo: 6, resta: 5, pasado: false }];
    const mk = (o) => Object.assign({ order_id: 100, empresa: "lk", cod: "1000", razon_social: "Cliente Normal", zona: "Zona 1 - CABA Sur", fecha_recep: "2026-09-04", localidad: "Barracas", direccion: "Montes de Oca 1", m3: 0.4, m3_parcial: false, lineas: 5, cajas: 6, np_total: 1, bloques: [] }, o);
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");

    // (1) sin pedidos en cuarentena: el sector existe igual, vacío
    _apr.pedidos = [mk({ order_id: 100 }), mk({ order_id: 101, razon_social: "Cliente Dos" })];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    let html = document.getElementById("pppPreview").innerHTML;
    out.sectorSiempre = /apr-col-cuar/.test(html) && /🚧 Cuarentena/.test(html);
    out.vacioCuenta = /🚧 Cuarentena <b>\(0\)<\/b>/.test(html);
    out.listaNormal2 = /📋 Pedidos a programar <b>\(2\)<\/b>/.test(html);
    out.textoVacio = /Sin pedidos retenidos/.test(html);

    // (2) un pedido marcado por deuda + supera crédito: sale de la lista y cae en cuarentena
    _apr.pedidos = [
      mk({ order_id: 100, razon_social: "Cliente Deudor", cuarentena_motivos: ["deuda", "limite_credito"] }),
      mk({ order_id: 101, razon_social: "Cliente Dos" })
    ];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    html = document.getElementById("pppPreview").innerHTML;
    out.cuentaCuar1 = /🚧 Cuarentena <b>\(1\)<\/b>/.test(html);
    out.listaNormal1 = /📋 Pedidos a programar <b>\(1\)<\/b>/.test(html);
    out.badge = /apr-chip-cuar/.test(html) && /Deuda · Excede crédito/.test(html);
    out.motivo = /El cliente tiene deuda\. El pedido supera el límite de crédito del cliente\./.test(html);
    // el deudor no aparece como tarjeta tildable (sin checkbox de selección en su tarjeta)
    out.deudorCliente = /Cliente Deudor/.test(html);
    const chks = [...document.querySelectorAll(".apr-sel-chk")].length;
    out.soloUnCheckbox = chks === 1;  // solo el pedido normal es tildable

    out.errs = null;
    return out;
  });

  const fallos = [];
  const chk = (cond, msg) => { console.log((cond ? "ok   " : "MAL  ") + msg); if (!cond) fallos.push(msg); };

  chk(r.sectorSiempre, "el sector 🚧 Cuarentena aparece siempre");
  chk(r.vacioCuenta, "sin retenidos: contador (0)");
  chk(r.textoVacio, "sin retenidos: explica deuda/suspendido/crédito");
  chk(r.listaNormal2, "sin retenidos: los 2 pedidos van a la lista normal");
  chk(r.cuentaCuar1, "con 1 retenido: Cuarentena (1)");
  chk(r.listaNormal1, "el retenido sale de la lista normal (queda 1)");
  chk(r.badge, "el retenido lleva badge con la etiqueta del motivo");
  chk(r.motivo, "el retenido muestra el texto del motivo");
  chk(r.deudorCliente, "el cliente deudor se ve en el sector");
  chk(r.soloUnCheckbox, "el retenido NO es tildable (solo el normal tiene checkbox)");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? " (" + errs.join(" | ") + ")" : ""));

  await b.close();
  if (fallos.length) { console.log("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-cuarentena OK");
})();
