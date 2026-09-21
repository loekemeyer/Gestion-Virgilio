/* v20.81 — EL NUMERO DE PEDIDO VA DENTRO DEL BADGE DE «CLIENTE NUEVO».

   Luis lo pidio asi desde el principio: *"un badge que indica, ADEMAS de su condicion de ser
   clientes nuevos, el pedido por el que van (1er pedido, 2do pedido, 3er pedido)"*, y estaba
   como badge aparte al lado de la NP — dos pastillas donde iba una.

   El badge es el MISMO de A Programar, Clientes nuevos y Cuarentena, asi que el dato aparece en
   las tres pantallas.

   ⚠ `nuevo_pedidos` son los pedidos FACTURADOS de toda su historia: el que esta en la pantalla
     es el SIGUIENTE, o sea +1. Sin el dato no se inventa un numero.
   Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage();
  const errs = []; pg.on("pageerror", e => errs.push(String(e)));
  await pg.goto("file:///home/user/Gestion-Virgilio/index.html");
  await pg.waitForTimeout(900);
  const r = await pg.evaluate(() => {
    const out = {};
    const badge = n => aprCuarBadgesHtml({ cuarentena_motivos:["cliente_nuevo"],
                                           cuarentena_detalle:{ nuevo_pedidos:n } });
    out.sinCompras = /🆕 Cliente nuevo.*1\.º pedido/.test(badge(0));
    out.conUna     = /🆕 Cliente nuevo.*2\.º pedido/.test(badge(1));
    out.conDos     = /🆕 Cliente nuevo.*3\.º pedido/.test(badge(2));
    // el badge va TODO junto, no en dos pastillas
    out.unSoloBadge = (badge(1).match(/cuar-badge b-nuevo/g) || []).length === 1;
    out.numeroAdentro = /b-nuevo[^>]*>[^<]*🆕 Cliente nuevo<b class="cuar-badge-nro">· 2\.º pedido<\/b><\/span>/.test(badge(1));
    // y sin el dato no inventa un numero
    out.sinDato = !/pedido<\/b>/.test(aprCuarBadgesHtml({ cuarentena_motivos:["cliente_nuevo"], cuarentena_detalle:{} }));
    // el ejemplo del pipeline es un cliente que recien llega
    out.ejemploEsPrimero = (pipeDemoPedido().cuarentena_detalle || {}).nuevo_pedidos === 0;
    // y ya no queda el badge suelto al lado de la NP
    _apr.listo = true; _apr.pedidos = []; _apr.pedidosTodos = []; _apr.pipeDemo = true;
    _apr.pipe = {}; _apr.cliValor = {}; _apr.cliCuit = {}; _apr.cliWpp = {}; _apr.cuarComN = {};
    const h = pipeHtml();
    out.sinBadgeSuelto = !/class="pipe-nro"/.test(h);
    out.badgeEnLaFila = /cuar-badge-nro/.test(h);
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  console.log("pageerrors:", errs.length ? errs.slice(0,2) : "none");
  await b.close();
  process.exit(Object.values(r).every(Boolean) && !errs.length ? 0 : 1);
})();
