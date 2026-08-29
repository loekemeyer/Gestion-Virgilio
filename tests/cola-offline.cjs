/* Regresión idea 4155 — cola offline (enqueueReport / flushQueue): resiliencia.
   Cubre: legajo de prueba NO persiste · encolado normal (localStorage + attempts=0)
   · flush con server OK (saca de la cola) · flush con RED CAÍDA (attempts++, lastErr
   "network", corta el batch — el 2º ítem no se toca — y re-registra Background Sync)
   · flush con RECHAZO del server (attempts++, lastErr server_400, sigue con el próximo)
   · auditoría remota en el intento 1 y cada 5 (no spamea en el 2..4) · navigator.onLine
   false → no intenta mandar nada · flushing re-entrante → segunda llamada no duplica.
   Todo stubbeado (trySendOneReport / logErrorToAudit / registerBackgroundSync). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    localStorage.clear();
    window.updatePendingIndicator = function () {};
    let syncs = 0; window.registerBackgroundSync = async function () { syncs++; };
    let audits = []; window.logErrorToAudit = function (pl, attempts) { audits.push(attempts); };
    window.idbPut = function () { return Promise.resolve(); };
    window.idbDelete = function () { return Promise.resolve(); };
    const mkPayload = function (id) { return { id: id, legajo: "104", opcion: "EP", texto: "D01B", ts: Date.now() }; };

    // ---- legajo de prueba: NO persiste ----
    window.esOperadorPrueba = function () { return true; };
    enqueueReport(mkPayload("t0"));
    out.prueba_noPersiste = readQueue().length === 0;

    // ---- encolado normal ----
    window.esOperadorPrueba = function () { return false; };
    enqueueReport(mkPayload("a1"));
    enqueueReport(mkPayload("a2"));
    let q = readQueue();
    out.encola = q.length === 2 && q[0].id === "a1" && q[0].attempts === 0 && q[0].legajo === "104";

    // ---- flush con server OK: los saca de la cola ----
    window.trySendOneReport = async function () { return { ok: true, status: 201 }; };
    await flushQueue();
    out.flushOk_vacia = readQueue().length === 0;

    // ---- flush con RED CAÍDA: attempts++, lastErr network, corta el batch, re-arma sync ----
    enqueueReport(mkPayload("b1"));
    enqueueReport(mkPayload("b2"));
    let sends = 0;
    window.trySendOneReport = async function () { sends++; return { ok: false, networkFail: true }; };
    syncs = 0; audits = [];
    await flushQueue();
    q = readQueue();
    out.net_quedan = q.length === 2;
    out.net_attempts = q[0].attempts === 1 && q[0].lastErr === "network";
    out.net_cortaBatch = sends === 1 && (q[1].attempts || 0) === 0;   // el 2º ni se intentó
    out.net_rearmaSync = syncs >= 1;
    out.net_audita1 = audits.length === 1 && audits[0] === 1;

    // ---- reintentos 2..4 sin auditar; el 5º audita ----
    audits = [];
    await flushQueue(); await flushQueue(); await flushQueue();   // attempts 2,3,4
    out.audit_2a4_silencio = audits.length === 0;
    await flushQueue();                                            // attempts 5
    out.audit_5_avisa = audits.length === 1 && audits[0] === 5;

    // ---- flush con RECHAZO del server: attempts++, sigue con el próximo ítem ----
    writeQueue([]); enqueueReport(mkPayload("c1")); enqueueReport(mkPayload("c2"));
    sends = 0;
    window.trySendOneReport = async function () { sends++; return { ok: false, networkFail: false, status: 400 }; };
    audits = [];
    await flushQueue();
    q = readQueue();
    out.rechazo_sigueBatch = sends === 2 && q.length === 2;
    out.rechazo_lastErr = q[0].lastErr === "server_400" && q[1].lastErr === "server_400";

    // ---- offline: no intenta mandar ----
    sends = 0;
    Object.defineProperty(navigator, "onLine", { get: function () { return false; }, configurable: true });
    await flushQueue();
    out.offline_noManda = sends === 0;
    Object.defineProperty(navigator, "onLine", { get: function () { return true; }, configurable: true });

    // ---- flushing re-entrante: la 2ª llamada en paralelo no procesa doble ----
    writeQueue([]); enqueueReport(mkPayload("d1"));
    let resolveSend; sends = 0;
    window.trySendOneReport = function () { sends++; return new Promise(function (res) { resolveSend = res; }); };
    const p1 = flushQueue(); const p2 = flushQueue();   // la 2ª ve flushing=true y vuelve
    await new Promise(function (res) { setTimeout(res, 30); });
    resolveSend({ ok: true, status: 201 });
    await p1; await p2;
    out.reentrada_unSolo = sends === 1 && readQueue().length === 0;

    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("cola-offline:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
