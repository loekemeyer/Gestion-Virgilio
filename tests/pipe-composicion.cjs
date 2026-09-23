/* v21.82 — EL BOTON DE COMPOSICION DEL PEDIDO, en la celda Monto del pipeline.

   Pedido del chat (23/09): "un boton donde se pueda ver la composicion del pedido con el monto
   total de los articulos importados (E) que tienen stock, con el dto por volumen aplicado, el
   dto del 2% por web y el 25% por volumen" y, sobre el total, "que aclare que incluye IVA
   porque es lo que tengo que reclamar al cliente que pague".

   ⚠ Se CORRE, no se lee. Un candado de texto sobre el onclick no dice si el pop-up sale con los
     numeros bien: lo que importa es que el TOTAL diga IVA incluido y que la suma de las lineas
     coincida con el monto que ya esta en pantalla. Sale 1 si falla. */
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
    // el cliente del caso real: 25 % por volumen + 2 % web
    const FILAS = [
      { art: "438E", cajas: 10, cajas_ok: 10, cajas_falta: 0, importado: true,  uxb: 6,  unidades: 60,
        precio_unit: 1000, bruto: 60000, dto_vol: 0.25, dto_web: 0.02, importe: 44100, sin_precio: false },
      { art: "501",  cajas: 5,  cajas_ok: 5,  cajas_falta: 0, importado: false, uxb: 12, unidades: 60,
        precio_unit: 500,  bruto: 30000, dto_vol: 0.25, dto_web: 0.02, importe: 22050, sin_precio: false },
      { art: "865E", cajas: 4,  cajas_ok: 0,  cajas_falta: 4, importado: true,  uxb: 6,  unidades: 0,
        precio_unit: 800,  bruto: 0,     dto_vol: 0.25, dto_web: 0.02, importe: 0,     sin_precio: false }
    ];
    const NETO = 66150, TOTAL = Math.round(NETO * 1.21);   // 80.042 — el numero que se le reclama
    let ultimoBody = null, respuesta = FILAS;
    window.aprRpc = async function (fn, body) {
      if (fn === "gv_clin_composicion") { ultimoBody = body; return respuesta; }
      return [];
    };
    window.pppRenderProg = function () {};   // el pop-up se lee de pipeCompHtml(), sin DOM

    const ped = { order_id: "9001", empresa: "lk", cod: "4282", razon_social: "SILVANO LUCAS MARTIN",
                  zona: "Retira", m3: 0.428, np_total: 3, cond: "8",
                  bloques: [{ items: [{ art: "438E", cajas: 10 }, { art: "501", cajas: 5 },
                                      { art: "865E", cajas: 4 }] }],
                  cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 2 } };
    _apr.listo = true; _apr.pedidos = [ped]; _apr.pedidosTodos = _apr.pedidos;
    _apr.pipe = {}; _apr.cliWpp = {}; _apr.cuarComN = {}; _apr.cliCuit = {};
    _apr.pipeDemo = false; _apr.pipeCfg = {}; _apr.pipeStale = false; _apr.pipeComp = null;
    _apr.cliValor = { "lk:9001": { valor: NETO, valorIva: NETO * 1.21, valorImp: 0, itemsImp: 0 } };
    try { localStorage.setItem("vir_cli_colapsado", "0"); } catch (_e) {}

    // (a) el boton esta en la celda Monto y el pop-up esta montado en la pantalla
    const pipe = pipeHtml();
    out.hayBoton   = /pipeCompAbrir\('lk','9001'\)/.test(pipe);
    out.hayCaja    = pipe.indexOf('id="pipeCompBox"') >= 0;
    out.cajaCerrada = /id="pipeCompBox" class="pipe-modal-off"/.test(pipe);

    // (b) se abre y trae el detalle
    pipeCompAbrir("lk", "9001");
    await new Promise(function (r) { setTimeout(r, 60); });
    const m = pipeCompHtml();
    out.abierto     = /id="pipeCompBox" class="pipe-modal"/.test(m);
    // ⚠ la RPC recibe el LOTE, no el pedido solo: el reparto de importados es greedy
    out.mandaElLote = !!(ultimoBody && Array.isArray(ultimoBody.p_pedidos) &&
                         ultimoBody.p_pedidos.length === 1 &&
                         (ultimoBody.p_pedidos[0].items || []).length === 3 &&
                         ultimoBody.p_order_id === "9001");
    out.lineas      = m.indexOf("438E") >= 0 && m.indexOf("501") >= 0 && m.indexOf("865E") >= 0;
    out.marcaE      = /pipe-comp-e"[^>]*>E</.test(m);

    // (c) los tres numeros del pedido: bruto, 25 % volumen, 2 % web
    out.bruto       = m.indexOf("$90.000") >= 0;                     // 60.000 + 30.000
    out.dtoVol      = /volumen \(25 %\)/.test(m) && m.indexOf("$22.500") >= 0;
    out.dtoWeb      = /web \(2 %\)/.test(m)     && m.indexOf("$1.350") >= 0;
    out.neto        = m.indexOf("$66.150") >= 0;

    // (d) EL TOTAL DICE IVA INCLUIDO — es lo que se le reclama al cliente
    out.totalConIva = m.indexOf("TOTAL A COBRAR — IVA INCLUIDO") >= 0;
    out.numeroTotal = m.indexOf("$" + TOTAL.toLocaleString("es-AR")) >= 0;
    out.diceReclamar = /IVA incluida?<\/b> es lo que hay que/.test(m) ||
                       /IVA incluido<\/b> es lo que hay que/.test(m);

    // (e) los importados (E) CON stock, y los que quedaron afuera
    out.impConStock = /importados \(E\) que tienen stock<\/b> son <b>1<\/b>/.test(m) &&
                      m.indexOf("$44.100") >= 0;
    out.impSinStock = /NO tienen <b>?stock/.test(m) || /NO tienen ?<b>stock<\/b>/.test(m) ||
                      m.indexOf("stock</b> para cubrir lo pedido") >= 0;
    out.sinAviso    = m.indexOf("no coincide con el") >= 0;          // tiene que ser FALSE

    // (f) si la suma no da el monto de la pantalla, el pop-up lo grita
    _apr.cliValor["lk:9001"].valor = 99999;
    const m2 = pipeCompHtml();
    out.avisaDesfasaje = m2.indexOf("no coincide con el") >= 0;
    _apr.cliValor["lk:9001"].valor = NETO;

    // (g) CERO FILAS ES UN ERROR, NO UN PEDIDO DE $0
    respuesta = [];
    pipeCompAbrir("lk", "9001");
    await new Promise(function (r) { setTimeout(r, 60); });
    const m3 = pipeCompHtml();
    out.vacioEsError = /pipe-modal-err/.test(m3) && m3.indexOf("No se pudo traer") >= 0;
    out.vacioNoDice0 = m3.indexOf("TOTAL A COBRAR") < 0;
    pipeCompCerrar();
    out.cierra = /class="pipe-modal-off"/.test(pipeCompHtml());
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  console.log("pageerrors:", errs.length ? errs.slice(0, 2) : "none");
  await b.close();
  const fallos = [];
  const ok = (c, m) => { if (!c) fallos.push(m); };
  ok(r.hayBoton,      "no esta el boton de composicion en la celda Monto");
  ok(r.hayCaja,       "el pop-up de composicion no esta montado en la pantalla");
  ok(r.cajaCerrada,   "el pop-up arranca abierto");
  ok(r.abierto,       "el pop-up no se abre");
  ok(r.mandaElLote,   "la RPC no recibe el lote entero con sus items: el reparto de importados sale mal");
  ok(r.lineas,        "faltan lineas del pedido en la composicion");
  ok(r.marcaE,        "los importados no se marcan con la E");
  ok(r.bruto,         "no esta el subtotal por lista (bruto)");
  ok(r.dtoVol,        "no esta el descuento por volumen (25 %) con su importe");
  ok(r.dtoWeb,        "no esta el descuento web (2 %) con su importe");
  ok(r.neto,          "no esta el neto sin IVA");
  ok(r.totalConIva,   "el total NO aclara que incluye IVA");
  ok(r.numeroTotal,   "el total con IVA no da el numero esperado");
  ok(r.diceReclamar,  "no dice que ese numero es el que hay que reclamarle al cliente");
  ok(r.impConStock,   "no esta el monto de los importados (E) que tienen stock");
  ok(r.impSinStock,   "no avisa que hay importados sin stock que quedan afuera");
  ok(!r.sinAviso,     "avisa desfasaje cuando la suma SI coincide");
  ok(r.avisaDesfasaje,"la suma de las lineas no se compara contra el monto de la pantalla");
  ok(r.vacioEsError,  "una respuesta vacia no se reporta como error");
  ok(r.vacioNoDice0,  "una respuesta vacia se muestra como un pedido de $0");
  ok(r.cierra,        "el pop-up no cierra");
  if (fallos.length) { console.error("FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("pipe-composicion: OK");
})();
