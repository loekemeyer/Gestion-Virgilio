/* v25.16 (Marianela, 30/09) — dos cosas que hacían que un movimiento de stock "no impacte":
   A) la cola offline (vir_stock_pend) se reintentaba en UN solo POST: una fila rechazada por el
      server trababa todo lo de atrás para siempre (celular del 104: un guardado del 599E que ya
      había entrado tapaba la salida a Cervantes del 328E, 48 cj). Ahora va fila por fila.
   B) «Fijar» calculaba el saldo con _stk.movs, que se carga en segundo plano: antes de que
      llegara veía 0 y decía "ya es 0" sin grabar (566E). Ahora pregunta el saldo al servidor. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const A = await p.evaluate(async () => {
    const cola = [
      { cod_art: "599E", deposito: "a_guardar", delta: -1, tipo: "guardado", client_id: "mst_a" },
      { cod_art: "328E", deposito: "terminado", delta: -48, tipo: "salida_cervantes", client_id: "mst_b" },
      { cod_art: "DUP", deposito: "terminado", delta: 1, tipo: "ajuste", client_id: "mst_c" },
      { cod_art: "NET", deposito: "terminado", delta: 1, tipo: "ajuste", client_id: "mst_d" },
      { cod_art: "DESPUES", deposito: "terminado", delta: 1, tipo: "ajuste", client_id: "mst_e" }
    ];
    localStorage.setItem("vir_stock_pend", JSON.stringify(cola));
    localStorage.removeItem("vir_stock_rech");
    const insertadas = [];
    const resp = (ok, status, body) => Promise.resolve({ ok: ok, status: status, text: () => Promise.resolve(body) });
    window.fetch = function (url, opts) {
      const rows = JSON.parse((opts && opts.body) || "[]");
      const c = rows[0] && rows[0].cod_art;
      if (c === "599E") return resp(false, 400, '{"code":"P0001","message":"En A guardar del 599E hay 0 caja(s) y se quisieron guardar 1."}');
      if (c === "328E") {
        // mientras se vacía la cola, stockMove encola otra fila: no se tiene que perder
        const q = JSON.parse(localStorage.getItem("vir_stock_pend") || "[]");
        q.push({ cod_art: "NUEVA", deposito: "terminado", delta: 2, tipo: "ajuste", client_id: "mst_z" });
        localStorage.setItem("vir_stock_pend", JSON.stringify(q));
        rows.forEach((r) => insertadas.push(r.cod_art));
        return resp(true, 201, "");
      }
      if (c === "DUP") return resp(false, 409, '{"code":"23505","message":"duplicate key value violates unique constraint \\"mov_stock_clientid_dedup\\""}');
      if (c === "NET") return Promise.reject(new Error("net"));
      rows.forEach((r) => insertadas.push(r.cod_art));
      return resp(true, 201, "");
    };
    await stockFlushPend();
    const pend = JSON.parse(localStorage.getItem("vir_stock_pend") || "[]").map((r) => r.cod_art);
    const rech = JSON.parse(localStorage.getItem("vir_stock_rech") || "[]").map((r) => r.row.cod_art + ":" + r.status);
    return { insertadas, pend, rech };
  });

  const B = await p.evaluate(async () => {
    window.alert = function () {};
    window.openStockAdmin = function () {};
    window._stk = { movs: [], cutoff: null };
    try { _stk = window._stk; } catch (_e) {}
    ["stkAjCod2", "stkAjFijar", "stkAjComent"].forEach(function (id) { const i = document.createElement("input"); i.id = id; document.body.appendChild(i); });
    const sel = document.createElement("select"); sel.id = "stkAjDep"; sel.innerHTML = '<option value="terminado">t</option>'; document.body.appendChild(sel);
    document.getElementById("stkAjCod2").value = "566E";
    document.getElementById("stkAjFijar").value = "0";
    const posts = [];
    let leer = "ok";
    window.fetch = function (url, opts) {
      if (/gv_saldos_por_clave/.test(url)) {
        if (leer === "falla") return Promise.resolve({ ok: false, status: 500, json: () => Promise.resolve({}) });
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve([{ clave: "566E", terminado: "2.0", excedente: "0" }]) });
      }
      if (/Movimientos_Stock/.test(url)) { posts.push(JSON.parse(opts.body)); return Promise.resolve({ ok: true, status: 201 }); }
      return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve([]) });
    };
    await stockFijar();
    const conSaldo = posts.map((x) => x[0] && x[0].delta);
    posts.length = 0; leer = "falla";
    await stockFijar();
    return { conSaldo, sinLecturaPosts: posts.length };
  });

  const okA = A.insertadas.join(",") === "328E" &&
    A.pend.join(",") === "NET,DESPUES,NUEVA" &&
    A.rech.join(",") === "599E:400";
  const okB = B.conSaldo.length === 1 && Number(B.conSaldo[0]) === -2 && B.sinLecturaPosts === 0;
  const ok = okA && okB && !errs.length;
  console.log("stock-cola-por-fila:", JSON.stringify({ A, B }), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", ok ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
