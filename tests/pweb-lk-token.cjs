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

    // ── 4) v26.78: modo enlace → la sesión viene armada, SIN login con password ──
    _pwebTok = null; _pwebTokExp = 0; _pwebRef = null;
    let cuerpoPuente = null, loginPw = 0;
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (u.indexOf("admin-login-otp") >= 0) {
        cuerpoPuente = JSON.parse((opt && opt.body) || "{}");
        return { ok: true, json: async () => ({ ok: true, modo: "enlace", email: "a@b.c",
          access_token: "TOK_ENLACE", refresh_token: "REF1", expires_in: 3600 }) };
      }
      if (u.indexOf("grant_type=password") >= 0) loginPw++;
      return { ok: false, status: 404, json: async () => ({}) };
    };
    out.tokEnlace = await pwebLkToken();
    out.modoPedido = cuerpoPuente && cuerpoPuente.modo;
    out.loginPw = loginPw;

    // ── 5) vencido con refresh token → renueva la MISMA sesión, sin puente ──────
    _pwebTokExp = 0;
    let puente5 = 0, refresh5 = 0;
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (u.indexOf("admin-login-otp") >= 0) { puente5++; return { ok: false, status: 500, json: async () => ({}) }; }
      if (u.indexOf("grant_type=refresh_token") >= 0) {
        refresh5++;
        const bd = JSON.parse((opt && opt.body) || "{}");
        if (bd.refresh_token !== "REF1") return { ok: false, status: 400, json: async () => ({}) };
        return { ok: true, json: async () => ({ access_token: "TOK_REFRESCADO", refresh_token: "REF2", expires_in: 3600 }) };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    };
    out.tokRefresh = await pwebLkToken();
    out.puente5 = puente5; out.refresh5 = refresh5;

    // ── 6) refresh rechazado → cae al puente y sigue andando ────────────────────
    _pwebTokExp = 0; _pwebRef = "REF_MUERTO";
    let puente6 = 0;
    window.fetch = async (url) => {
      const u = String(url);
      if (u.indexOf("grant_type=refresh_token") >= 0) return { ok: false, status: 400, json: async () => ({ error_code: "refresh_token_not_found" }) };
      if (u.indexOf("admin-login-otp") >= 0) { puente6++;
        return { ok: true, json: async () => ({ ok: true, access_token: "TOK_6", refresh_token: "REF6", expires_in: 3600 }) }; }
      return { ok: false, status: 404, json: async () => ({}) };
    };
    out.tok6 = await pwebLkToken(); out.puente6 = puente6;

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
  chk(r.modoPedido === "enlace",  "v26.78: el puente se pide en modo enlace (no cambia la clave del usuario compartido)");
  chk(r.tokEnlace === "TOK_ENLACE" && r.loginPw === 0, "modo enlace: usa la sesión que viene, sin login con password");
  chk(r.tokRefresh === "TOK_REFRESCADO" && r.puente5 === 0 && r.refresh5 === 1,
      "token vencido con refresh token: renueva la misma sesión sin abrir el puente");
  chk(r.tok6 === "TOK_6" && r.puente6 === 1, "refresh rechazado: cae al puente y entra igual");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\npweb-lk-token OK");
})();
