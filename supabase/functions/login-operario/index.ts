import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/* =============================================================================
   login-operario — etapa 1 del plan docs/PLAN-LOGIN-OPERARIOS-RED.md (2026-09-28).

   El operario entra con su LEGAJO, pero solo desde la RED DE LA EMPRESA:
     1. la IP real del pedido (la pone el gateway; medido 28/09: no se falsifica con
        cabeceras) tiene que estar en public.red_empresa (IP o rango) → si no, 403;
     2. el legajo tiene que existir y estar activo en public."Empleados";
     3. se devuelve una SESIÓN de Supabase del usuario op<legajo>@operarios.interno
        (se crea la primera vez) con app_metadata {rol:'operario', legajo}. La base lee
        ese rol con public.jwt_rol() / public.jwt_legajo().
   Ese usuario no tiene contraseña para nadie: la única puerta es esta función.
   Las sesiones de operario se borran todas las noches (cron cerrar-sesiones-operarios).

   Todo intento queda en public.seg_login_operario_log. El primer rechazo POR IP del día
   de un legajo válido avisa por Telegram (puede ser que el proveedor cambió la IP).

   POST {legajo, app?}  →  200 {access_token, refresh_token, expires_at, legajo, nombre}
                          403 {error}   (fuera de la red / legajo inválido)
   ============================================================================= */

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const DOMINIO = "operarios.interno";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

function ipReal(req: Request) {
  const xff = req.headers.get("x-forwarded-for") || "";
  return (xff.split(",")[0] || req.headers.get("x-real-ip") || "").trim();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const admin = createClient(SB_URL, SRK, { auth: { persistSession: false, autoRefreshToken: false } });
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* vacío */ }
  const legajo = String(body.legajo ?? "").trim();
  const app = String(body.app ?? "").slice(0, 40);
  const ip = ipReal(req);

  const log = (ok: boolean, motivo: string | null) =>
    admin.from("seg_login_operario_log").insert({ ip, legajo: legajo.slice(0, 20), app, ok, motivo });

  // 1) Red de la empresa
  const { data: sede, error: eIp } = await admin.rpc("ip_en_red_empresa", { p_ip: ip });
  if (eIp) return json({ error: "no se pudo verificar la red" }, 503);

  // 2) Legajo activo
  let nombre: string | null = null;
  if (/^\d{1,6}$/.test(legajo)) {
    const { data: emp } = await admin.from("Empleados")
      .select("Legajo, Empleado, Activo").eq("Legajo", legajo).maybeSingle();
    if (emp && String(emp.Activo || "").toUpperCase() === "SI") nombre = emp.Empleado || null;
  }

  if (!sede) {
    await log(false, "fuera de la red");
    if (nombre) {
      // Un legajo válido rechazado por IP: puede que el proveedor haya cambiado la IP.
      const hoy = new Date().toISOString().slice(0, 10);
      await admin.rpc("tg_enqueue", {
        p_text: `⚠ Login de operario rechazado por red: legajo ${legajo} desde IP ${ip}. ` +
          `Si es de la empresa, cargala en public.red_empresa (¿cambió la IP?).`,
        p_dedup: `login_op_ip_${hoy}_${ip}`,
      });
    }
    return json({ error: "Solo se puede entrar desde la red de la empresa." }, 403);
  }
  if (!nombre) {
    await log(false, "legajo inexistente o inactivo");
    return json({ error: "Legajo inexistente o inactivo." }, 403);
  }

  // 3) Sesión del usuario op<legajo>
  const email = `op${legajo}@${DOMINIO}`;
  const meta = { rol: "operario", legajo };
  // Primero el usuario, confirmado y con su rol (si ya existe, createUser falla y se sigue).
  // Ojo: generateLink sobre un usuario inexistente lo crea SIN confirmar y ese enlace no
  // sirve ("Email link is invalid"): por eso se confirma antes de generar el definitivo.
  await admin.auth.admin.createUser({ email, email_confirm: true, app_metadata: meta, user_metadata: { nombre } });
  let link = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (link.error || !link.data.user) {
    await log(false, "generateLink: " + (link.error?.message || "sin usuario"));
    return json({ error: "No se pudo iniciar la sesión." }, 500);
  }
  const u = link.data.user;
  if (!u.email_confirmed_at || u.app_metadata?.rol !== "operario" || u.app_metadata?.legajo !== legajo) {
    await admin.auth.admin.updateUserById(u.id, { email_confirm: true, app_metadata: meta });
    link = await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (link.error) { await log(false, "generateLink: " + link.error.message); return json({ error: "No se pudo iniciar la sesión." }, 500); }
  }

  const pub = createClient(SB_URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const ver = await pub.auth.verifyOtp({ type: "email", token_hash: link.data.properties!.hashed_token });
  if (ver.error || !ver.data.session) {
    await log(false, "verifyOtp: " + (ver.error?.message || "sin sesión"));
    return json({ error: "No se pudo iniciar la sesión." }, 500);
  }

  await log(true, sede);
  const s = ver.data.session;
  return json({
    access_token: s.access_token, refresh_token: s.refresh_token, expires_at: s.expires_at,
    legajo, nombre, sede,
  });
});
