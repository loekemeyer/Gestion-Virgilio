/* Regresión (v12.82) — el token de LK se pide UNA SOLA VEZ aunque lo pidan varios.

   El puente `bridge` de `admin-login-otp` le SETEA al usuario de LK una password
   temporal nueva en cada llamada, y recién después se entra con ésa. Si dos
   partes de la app piden el token a la vez, la segunda le pisa la password a la
   primera y la primera cae con "Login LK falló (HTTP 400)".

   Pasó de verdad el 2026-09-04: al abrir la PPP corren juntos el cargador de
   siempre (`pppTraerPedidosWeb`) y la solapa A Programar (`aprTraerPedidos`).
   Como es una carrera, gana una y falla la otra sin patrón fijo.

   Acá se piden 3 tokens en paralelo y se exige que el puente se haya abierto UNA
   vez. También se comprueba que un fallo no deje la promesa pegada (se puede
   reintentar) y que el mensaje de error diga lo que contestó LK y no un
   "HTTP 400" pelado. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.sbAuth = { getAccessToken: async () => "jwt-de-virgilio" };
    const real = window.fetch;

    // ── 1) tres pedidos en paralelo → UN solo puente ────────────────────────
    let puente = 0, login = 0;
    window.fetch = async (url) => {
      const u = String(url);
      if (u.indexOf("admin-login-otp") >= 0) {
        puente++;
        await new Promise((res) => setTimeout(res, 40));   // el puente tarda
        return { ok: true, json: async () => ({ tmp_password: "tmp" + puente, email: "a@b.c" }) };
      }
      if (u.indexOf("/auth/v1/token") >= 0) {
        login++;
        return { ok: true, json: async () => ({ access_token: "TOKEN", expires_in: 3600 }) };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    };
    _pwebTok = null; _pwebTokExp = 0;
    const tres = await Promise.all([pwebLkToken(), pwebLkToken(), pwebLkToken()]);
    out.puente = puente; out.login = login;
    out.todosIguales = tres[0] === "TOKEN" && tres[1] === "TOKEN" && tres[2] === "TOKEN";

    // ── 2) con el token cacheado no vuelve a abrir el puente ────────────────
    await pwebLkToken();
    out.puenteTrasCache = puente;

    // ── 3) si LK rechaza, el mensaje dice POR QUÉ y se puede reintentar ─────
    _pwebTok = null; _pwebTokExp = 0;
    window.fetch = async (url) => {
      const u = String(url);
      if (u.indexOf("admin-login-otp") >= 0) return { ok: true, json: async () => ({ tmp_password: "x", email: "a@b.c" }) };
      // GoTrue nuevo: {code, error_code, msg} — sin error_description
      return { ok: false, status: 400, json: async () => ({ code: 400, error_code: "invalid_credentials", msg: "Invalid login credentials" }) };
    };
    try { await pwebLkToken(); out.msg = "(no falló)"; }
    catch (e) { out.msg = e.message; }
    // la promesa no puede quedar pegada: un segundo intento tiene que volver a probar
    try { await pwebLkToken(); out.reintento = "(no falló)"; }
    catch (e) { out.reintento = e.message; }

    window.fetch = real;
    return out;
  });

  const fallos = [];
  const chk = (cond, msg) => { console.log((cond ? "ok   " : "MAL  ") + msg); if (!cond) fallos.push(msg); };
  chk(r.puente === 1,            "3 pedidos en paralelo → 1 sola llamada al puente (fueron " + r.puente + ")");
  chk(r.login === 1,             "→ 1 solo login (fueron " + r.login + ")");
  chk(r.todosIguales,            "los tres reciben el mismo token");
  chk(r.puenteTrasCache === 1,   "con el token cacheado no reabre el puente");
  chk(/Invalid login credentials/.test(r.msg), "el error dice lo que contestó LK: " + r.msg);
  chk(/Invalid login credentials/.test(r.reintento), "se puede reintentar (la promesa no queda pegada)");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\npweb-lk-token OK");
})();
