// Supabase Edge Function: admin-login-otp
// Login por código OTP al mail SIN necesitar sesión previa. Copia el patrón
// de admin-otp (Resend + tabla admin_otp_codes) pero abre el flujo para
// autenticarse desde cero. Se usa como reemplazo de sb.auth.signInWithOtp
// cuando el SMTP nativo del proyecto está mal configurado (Resend rechaza
// el sender @loekemeyer.com por dominio no verificado).
//
// Acciones:
//   { action: "send" }           → manda código de 6 dígitos al RECIPIENT_EMAIL
//   { action: "verify", code }   → valida código; setea password temporal en
//                                  el user y lo devuelve para que el front haga
//                                  signInWithPassword y quede con sesión.
//   { action: "bridge", vjwt }   → recibe el access_token de la sesión de
//                                  Producción Virgilio (otro proyecto Supabase),
//                                  lo VERIFICA server-side contra el auth de
//                                  Virgilio y, sólo si el mail del token es el
//                                  MISMO que RECIPIENT_EMAIL (mismo dueño, no
//                                  amplía acceso a nadie), setea el password
//                                  temporal igual que "verify". Permite entrar
//                                  directo al admin desde el botón "Panel Web LK"
//                                  sin volver a pedir OTP. (v12.35)
//
// Seguridad: sin JWT, así que el destinatario está HARDCODEADO (loekemeyer.n8n@gmail.com)
// y se chequea que ese user esté en public.admins. Solo un mail posible, no es un
// oráculo de existencia de mails. El "bridge" NO confía en el front: la prueba de
// identidad es el JWT de Virgilio validado contra su propio PostgREST
// (RPC bridge_jwt_email) — valida firma+expiración sin depender de la sesión.
//
// Deploy (una vez): verify_jwt=false y depende de los secrets RESEND_API_KEY /
// RESEND_FROM (opcional; fallback a onboarding@resend.dev, dominio verificado
// por Resend). Ya usados por la Edge Function admin-otp.
//
// ⚠⚠ v26.78 (05/10, Tomás Gonzalez: "No se pudo crear el login (CUIT + PIN): invalid_token").
// Cambiarle la password al usuario con updateUserById CIERRA TODAS SUS SESIONES (GoTrue
// hace Logout del usuario entero al cambiar la password por la API de admin). La cuenta
// loekemeyer.n8n@gmail.com es COMPARTIDA: la usan el Panel Web LK de cada persona y la
// PPP de Gestión (pwebLkToken), que la pedía ~22 veces por día (medido el 05/10). Cada
// entrada mataba la sesión de los demás: la pantalla seguía leyendo (PostgREST no mira
// la sesión) pero todo lo que pasa por Auth —crear-cliente-auth, refrescar el token—
// contestaba "Session not found" → el alta de clientes fallaba con invalid_token.
// Con { modo: "enlace" } la función ya NO toca la password: genera un enlace mágico
// (admin.generateLink, no manda mail), lo canjea acá mismo por una sesión NUEVA y
// devuelve access_token + refresh_token. Las demás sesiones siguen vivas. Si el enlace
// falla por lo que sea, cae al modo password de siempre: el login nunca queda peor que
// antes. Sin "modo" (fronts viejos cacheados) sigue el modo password.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RECIPIENT_EMAIL = "loekemeyer.n8n@gmail.com";

// Proyecto Supabase de Producción Virgilio — usado por la acción "bridge" para
// validar el access_token del supervisor contra SU PostgREST (RPC bridge_jwt_email).
// Se usa la clave PUBLISHABLE (sb_publishable_), no la anon legacy. Es pública por
// diseño, y hace falta que sea la nueva: el día que se apaguen las claves legacy de
// Virgilio, con la vieja acá el login del admin de LK se caía entero (problema 19).
// Medido el 2026-09-13 contra el endpoint real, las dos claves dan lo MISMO:
//   POST /rest/v1/rpc/bridge_jwt_email  → 200 "null" con publishable y con legacy
//   GET  /auth/v1/user                  → 401 no_authorization con publishable
// o sea que PostgREST y auth aceptan el formato nuevo (lo que NO lo acepta es el
// Storage al escribir; ver el bloque de claves en CLAUDE.md).
const VIRGILIO_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
const VIRGILIO_ANON_KEY = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function sha256Hex(text: string): Promise<string> {
  const buf = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function generate6DigitCode(): string {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return String(arr[0] % 1_000_000).padStart(6, "0");
}

function buildEmailHtml(code: string): string {
  return `<!doctype html>
<html><body style="margin:0;padding:24px;background:#f5f5f5;font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#222">
  <div style="max-width:480px;margin:0 auto;background:#fff;border-radius:14px;padding:32px;border:1px solid #e6e6e6">
    <div style="text-align:center;margin-bottom:20px">
      <div style="display:inline-block;background:#212122;color:#fff;width:48px;height:48px;border-radius:12px;line-height:48px;font-weight:800;letter-spacing:1px">LK</div>
    </div>
    <h2 style="margin:0 0 8px;font-size:20px;text-align:center">Código de acceso al panel admin</h2>
    <p style="color:#666;margin:0 0 24px;font-size:13.5px;text-align:center">Loekemeyer SRL — Panel Web LK</p>
    <div style="background:#f5f5f5;border-radius:12px;padding:22px;text-align:center;margin:0 0 18px">
      <div style="font-size:34px;font-weight:700;letter-spacing:10px;font-family:ui-monospace,Menlo,Consolas,monospace;color:#212122">${code}</div>
    </div>
    <p style="color:#666;font-size:13px;margin:0;text-align:center">Válido por 10 minutos. Si no fuiste vos, ignorá este mail.</p>
  </div>
</body></html>`;
}

// v26.78: sesión NUEVA sin tocar la password (las demás sesiones de la cuenta siguen vivas).
// generateLink pisa el token del enlace anterior, así que si otro login genera uno entre
// medio, el canje falla: se reintenta. Devuelve null si no se pudo (el que llama cae al
// modo password).
async function sesionPorEnlace(admin: ReturnType<typeof createClient>): Promise<Record<string, unknown> | null> {
  const canje = createClient(SUPABASE_URL, SUPABASE_ANON_KEY || SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  for (let intento = 0; intento < 3; intento++) {
    try {
      const gl = await admin.auth.admin.generateLink({ type: "magiclink", email: RECIPIENT_EMAIL });
      const props = (gl.data && gl.data.properties) || null;
      const th = props && props.hashed_token;
      if (gl.error || !th) {
        console.error("enlace: generateLink falló:", gl.error ? gl.error.message : "sin hashed_token");
      } else {
        const tipo = (props.verification_type || "magiclink") as "magiclink";
        const vr = await canje.auth.verifyOtp({ token_hash: th, type: tipo });
        const s = vr.data && vr.data.session;
        if (!vr.error && s && s.access_token && s.refresh_token) {
          return {
            ok: true, email: RECIPIENT_EMAIL, modo: "enlace",
            access_token: s.access_token, refresh_token: s.refresh_token,
            expires_in: s.expires_in, expires_at: s.expires_at,
          };
        }
        console.error("enlace: canje falló (intento " + (intento + 1) + "):", vr.error ? vr.error.message : "sin sesión");
      }
    } catch (e) {
      console.error("enlace: excepción (intento " + (intento + 1) + "):", e);
    }
    await new Promise((r) => setTimeout(r, 150 + Math.floor(Math.random() * 250)));
  }
  return null;
}

// Entrar: primero por enlace si el front lo pide; si no se puede, password temporal (modo viejo).
async function entrar(admin: ReturnType<typeof createClient>, userId: string, modo: unknown): Promise<Response> {
  if (modo === "enlace") {
    const ses = await sesionPorEnlace(admin);
    if (ses) return jsonResponse(ses);
    console.error("enlace: cae al modo password (cierra las demás sesiones de la cuenta)");
  }
  // Password temporal aleatorio. 36 chars de UUID (122 bits) alcanzan y sobran; NO usar
  // dos concatenados porque Supabase Auth (bcrypt) tope 72 chars y dos UUID + "-" son 73.
  // ⚠ Cambiar la password CIERRA todas las sesiones de la cuenta (ver la cabecera).
  const tmpPassword = crypto.randomUUID();
  const upd = await admin.auth.admin.updateUserById(userId, { password: tmpPassword });
  if (upd.error) return jsonResponse({ error: "set_password_failed", detail: upd.error.message }, 500);
  return jsonResponse({ ok: true, email: RECIPIENT_EMAIL, tmp_password: tmpPassword, modo: "password" });
}

async function getSecret(sb: ReturnType<typeof createClient>, name: string, fallbackEnv?: string): Promise<string> {
  const { data, error } = await sb.rpc("get_admin_otp_secret", { secret_name: name });
  if (!error && typeof data === "string" && data.length > 0) return data;
  if (fallbackEnv) {
    const v = Deno.env.get(fallbackEnv);
    if (v) return v;
  }
  return "";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return jsonResponse({ error: "server_misconfigured" }, 500);
    }
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Resolver user_id del destinatario hardcodeado por mail, en O(1). NO usar
    // listUsers: LK tiene >1200 usuarios y el recipient quedaba fuera de la
    // primera página → 500. La RPC get_admin_login_user_id() (SECURITY DEFINER,
    // solo service_role) lee auth.users por índice.
    const uidRes = await admin.rpc("get_admin_login_user_id");
    if (uidRes.error) return jsonResponse({ error: "lookup_failed", detail: uidRes.error.message }, 500);
    if (!uidRes.data) return jsonResponse({ error: "recipient_not_registered" }, 500);
    const userId = uidRes.data as string;

    const isAdmin = await admin.from("admins").select("auth_user_id").eq("auth_user_id", userId).maybeSingle();
    if (isAdmin.error || !isAdmin.data) return jsonResponse({ error: "not_admin" }, 403);

    let body: { action?: string; code?: string; vjwt?: string; modo?: string } = {};
    try { body = await req.json(); } catch (_) { return jsonResponse({ error: "invalid_body" }, 400); }
    const action = body.action;

    if (action === "bridge") {
      // Entrar directo desde Producción Virgilio (mismo dueño). La prueba es el
      // access_token de la sesión de Virgilio, validado contra su propio auth.
      const vjwt = String(body.vjwt ?? "").trim();
      if (!vjwt) return jsonResponse({ error: "missing_token" }, 400);

      // Verificar vía PostgREST de Virgilio (RPC bridge_jwt_email): valida SOLO
      // firma+expiración del JWT, sin mirar la sesión. GoTrue /auth/v1/user sí
      // miraba la sesión y devolvía 403 session_not_found aunque el token fuera
      // legítimo. La RPC devuelve el email del propio token.
      let vres: Response;
      try {
        vres = await fetch(`${VIRGILIO_URL}/rest/v1/rpc/bridge_jwt_email`, {
          method: "POST",
          headers: { apikey: VIRGILIO_ANON_KEY, Authorization: `Bearer ${vjwt}`, "Content-Type": "application/json" },
          body: "{}",
        });
      } catch (_) {
        return jsonResponse({ error: "verify_unreachable" }, 502);
      }
      if (!vres.ok) {
        const vtxt = await vres.text().catch(() => "");
        console.error("bridge verify failed:", vres.status, vtxt);
        return jsonResponse({ error: "invalid_token", detail: "virgilio " + vres.status + ": " + vtxt.slice(0, 200) }, 401);
      }
      const vemail = String((await vres.json().catch(() => "")) ?? "").toLowerCase();
      // Gate estricto: sólo el MISMO mail que el admin LK. No amplía acceso.
      if (!vemail || vemail !== RECIPIENT_EMAIL) return jsonResponse({ error: "not_authorized", detail: "email=" + vemail }, 403);

      return await entrar(admin, userId, body.modo);
    }

    if (action === "send") {
      const resendKey = await getSecret(admin, "RESEND_API_KEY", "RESEND_API_KEY");
      const resendFrom = (await getSecret(admin, "RESEND_FROM", "RESEND_FROM")) || "onboarding@resend.dev";
      if (!resendKey) return jsonResponse({ error: "mail_not_configured" }, 500);

      // Rate limit: 5 códigos en los últimos 10 minutos.
      const sinceIso = new Date(Date.now() - 10 * 60 * 1000).toISOString();
      const countRes = await admin.from("admin_otp_codes")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .gte("created_at", sinceIso);
      if ((countRes.count ?? 0) >= 5) return jsonResponse({ error: "rate_limited" }, 429);

      const code = generate6DigitCode();
      const codeHash = await sha256Hex(code);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

      const ins = await admin.from("admin_otp_codes").insert({
        user_id: userId, code_hash: codeHash, expires_at: expiresAt, used: false,
      });
      if (ins.error) return jsonResponse({ error: "db_error", detail: ins.error.message }, 500);

      const mailRes = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: resendFrom,
          to: [RECIPIENT_EMAIL],
          subject: "Código de acceso - Panel Web LK",
          html: buildEmailHtml(code),
        }),
      });
      if (!mailRes.ok) {
        const txt = await mailRes.text();
        console.error("Resend error:", mailRes.status, txt);
        return jsonResponse({ error: "mail_failed", detail: txt }, 500);
      }
      return jsonResponse({ ok: true });
    }

    if (action === "verify") {
      const inputCode = String(body.code ?? "").replace(/\s+/g, "");
      if (!/^\d{6}$/.test(inputCode)) return jsonResponse({ error: "invalid_format" }, 400);
      const codeHash = await sha256Hex(inputCode);
      const nowIso = new Date().toISOString();

      const found = await admin.from("admin_otp_codes")
        .select("id")
        .eq("user_id", userId)
        .eq("code_hash", codeHash)
        .eq("used", false)
        .gte("expires_at", nowIso)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (found.error || !found.data) return jsonResponse({ error: "invalid_code" }, 401);

      const upd = await admin.from("admin_otp_codes").update({ used: true }).eq("id", found.data.id);
      if (upd.error) return jsonResponse({ error: "db_error", detail: upd.error.message }, 500);

      return await entrar(admin, userId, body.modo);
    }

    return jsonResponse({ error: "unknown_action" }, 400);
  } catch (e) {
    console.error("admin-login-otp exception:", e);
    return jsonResponse({ error: "exception", detail: String(e) }, 500);
  }
});
