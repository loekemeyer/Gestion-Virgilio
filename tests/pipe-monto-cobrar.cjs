/* v21.98 (Vivi, 23/09) — LA CELDA MONTO Y EL SPEECH 1 MUESTRAN LO QUE HAY QUE COBRAR.

   Medido sobre LK 1448: la celda decia `c/IVA $2.052.219` y el pedido, del lado de LK, guarda
   subtotal 1.696.048,96 · payment_discount 0,25 · total 1.272.036,72. O sea que el numero que se
   le reclamaba al cliente estaba 25 % ARRIBA de lo que tiene que pagar.

   ⚠ Muerde por los DOS lados: con el plazo de pago leido tiene que aplicar el descuento, y sin
     leerlo NO puede inventarlo (regla: una lectura ROTA no es un CERO). Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { try { ({ chromium } = require("playwright")); }
  catch (e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage();
  const errs = []; pg.on("pageerror", e => errs.push(String(e)));
  await pg.goto("file://" + path.join(__dirname, "..", "index.html"));
  await pg.waitForTimeout(900);
  const r = await pg.evaluate(async () => {
    const out = {};
    const NETO = 1696049;              // el neto por lista, como LK 1448
    const A_COBRAR = NETO * 0.75;      // 1.272.036,75 con el 25 % de contado
    const CON_IVA  = A_COBRAR * 1.21;  // lo que se le reclama al cliente
    const VIEJO_IVA = NETO * 1.21;     // lo que decia antes, 25 % de mas
    // lo que se VE: los title= llevan el precio por lista a proposito, para comparar
    const visible = function (h) { return String(h).replace(/title="[^"]*"/g, ""); };
    const enMsg = function (n) { return Number(n).toLocaleString("es-AR", { maximumFractionDigits: 0 }); };

    let dtoResp = [{ empresa: "lk", order_id: "9001", metodo_pago: "Contado",
                     escalon_label: "Contado (0-14 dias)", dto: 0.25 }];
    let dtoFalla = false;
    window.aprRpc = async function (fn) {
      if (fn === "gv_clin_dto_pago_lote") { if (dtoFalla) throw new Error("boom"); return dtoResp; }
      return [];
    };
    let waURL = "";
    window.open = function (u) { waURL = String(u); return null; };

    const ped = { order_id: "9001", empresa: "lk", cod: "4282", razon_social: "SILVANO LUCAS MARTIN",
                  zona: "Retira", m3: 0.428, np_total: 3, cond: "8",
                  bloques: [{ items: [{ art: "505", cajas: 5 }] }],
                  cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 2 } };
    _apr.listo = true; _apr.pedidos = [ped]; _apr.pedidosTodos = _apr.pedidos;
    _apr.cliValor = { "lk:9001": { valor: NETO, valorIva: NETO * 1.21, valorImp: 0, itemsImp: 0 } };
    _apr.cliWpp = { "lk:9001": "1122334455" };

    const plata = function (n) { return cuarPlata(n); };

    // (a) CON el plazo de pago leido: manda el A COBRAR, no el precio por lista
    _apr.cliDtoPago = { "lk:9001": { dto: 0.25, label: "Contado (0-14 dias)", metodo: "Contado" } };
    const celda = clinNuevosValorFmt(ped);
    out.muestraACobrar   = visible(celda).indexOf(plata(A_COBRAR)) >= 0;
    out.muestraConIva    = visible(celda).indexOf(plata(CON_IVA)) >= 0;
    out.noMuestraElViejo = visible(celda).indexOf(plata(VIEJO_IVA)) < 0;
    out.chipDelDto       = /25\s*%/.test(celda) && celda.indexOf("Contado") >= 0;

    // (b) el Speech 1 lleva ESE numero
    const msg = clinSpeechMsg1(ped);
    out.speechACobrar  = msg.indexOf(enMsg(CON_IVA)) >= 0;
    out.speechSinViejo = msg.indexOf(enMsg(VIEJO_IVA)) < 0;

    // (c) SIN el dato: NO se inventa el 25 % — vuelve el total por lista y lo avisa
    _apr.cliDtoPago = {};
    const celda2 = clinNuevosValorFmt(ped);
    out.sinDatoNoAsume = visible(celda2).indexOf(plata(A_COBRAR)) < 0 &&
                         visible(celda2).indexOf(plata(VIEJO_IVA)) >= 0;
    out.sinDatoAvisa   = celda2.indexOf("sin plazo de pago") >= 0;
    const msg2 = clinSpeechMsg1(ped);
    out.speechSinDato  = msg2.indexOf(enMsg(VIEJO_IVA)) >= 0;

    // (d) la RPC rota no rompe la celda (su propio catch)
    _apr.cliDtoPago = null; _apr.cliDtoPagoLoading = false; dtoFalla = true;
    try { await clinDtoPagoCargar(); } catch (_e) { out.cargarTiro = true; }
    out.rotaNoRompe = !out.cargarTiro && !!_apr.cliDtoPago && clinNuevosValorFmt(ped).length > 0;

    // (e) y con la RPC sana carga el mapa
    _apr.cliDtoPago = null; _apr.cliDtoPagoLoading = false; dtoFalla = false;
    await clinDtoPagoCargar();
    out.cargaElMapa = !!(_apr.cliDtoPago && _apr.cliDtoPago["lk:9001"] &&
                         _apr.cliDtoPago["lk:9001"].dto === 0.25);
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  console.log("pageerrors:", errs.length ? errs.join(" | ") : "none");
  await b.close();
  const mal = Object.keys(r).filter(k => k !== "cargarTiro" && !r[k]);
  if (mal.length || errs.length || r.cargarTiro) {
    console.error("pipe-monto-cobrar FALLA:", mal.join(", ") || "pageerror"); process.exit(1);
  }
  console.log("pipe-monto-cobrar: OK");
})();
