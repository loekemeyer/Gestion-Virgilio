/* v25.43-44 (Luis): «⏰ N sin respuesta» en Clientes nuevos tiene que MOSTRAR los vencidos, no plegar
   el cuadro (el chip vive adentro del título plegable). Se CORRE: click real con Playwright sobre el
   chip y se mira que el cuadro siga abierto y que la tabla quede sólo con el vencido. Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { try { ({ chromium } = require("playwright")); } catch (e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage(); const errs = [];
  pg.on("pageerror", e => errs.push(String(e)));
  await pg.goto("file://" + path.join(__dirname, "..", "index.html")); await pg.waitForTimeout(900);
  await pg.evaluate(() => {
    window.aprRpc = async () => [];
    const mk = (id, n) => ({ order_id: id, empresa: "lk", cod: "49" + id, razon_social: n, zona: "Zona 3", m3: 0.4, np_total: 1,
      bloques: [], cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 1 } });
    _apr.listo = true; _apr.pedidos = [mk("9001", "AAA VENCIDO"), mk("9002", "BBB AL DIA")]; _apr.pedidosTodos = _apr.pedidos;
    _apr.pipe = { "lk:9001": { empresa: "lk", order_id: "9001", etapa: "speech1", vencido: true, reloj_desde: new Date(Date.now() - 9e7).toISOString() },
                  "lk:9002": { empresa: "lk", order_id: "9002", etapa: "ingresado" } };
    _apr.cliValor = {}; _apr.cliWpp = {}; _apr.cuarComN = {}; _apr.cliCuit = {}; _apr.pipeDemo = false; _apr.pipeCfg = {};
    try { localStorage.setItem("vir_cli_colapsado", "0"); } catch (_e) {}
    const c = document.createElement("div"); c.id = "__t"; document.body.prepend(c);
    window.aprRender = function () { c.innerHTML = pipeHtml(); }; aprRender();
  });
  const st = () => pg.evaluate(() => { const t = document.getElementById("__t").innerText, bd = document.querySelector(".pipe-badge-venc");
    return { col: localStorage.getItem("vir_cli_colapsado"), a: t.includes("AAA"), b: t.includes("BBB"), w: bd ? bd.getBoundingClientRect().width : 0 }; });
  const f = []; const s0 = await st();
  if (!(s0.a && s0.b)) f.push("al inicio no se ven los dos pedidos");
  if (!(s0.w > 0 && s0.w < 300)) f.push("el chip no es un botón chico (ancho " + s0.w + ")");
  await pg.click(".pipe-badge-venc"); const s1 = await st();
  if (s1.col !== "0") f.push("tocar el chip plegó el cuadro");
  if (!(s1.a && !s1.b)) f.push("tocar el chip no filtró a los vencidos");
  await pg.click(".pipe-badge-venc"); const s2 = await st();
  if (!(s2.col === "0" && s2.a && s2.b)) f.push("segundo toque no vuelve a mostrar todos");
  await pg.click(".apr-col-t-clic .apr-col-caret"); const s3 = await st();
  if (s3.col !== "1") f.push("el título ya no pliega");
  if (errs.length) f.push("pageerror: " + errs[0]);
  await b.close();
  if (f.length) { console.error("FALLA:\n - " + f.join("\n - ")); process.exit(1); }
  console.log("OK — el chip «sin respuesta» filtra los vencidos y el título sigue plegando");
})();
