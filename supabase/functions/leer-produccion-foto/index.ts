import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// leer-produccion-foto — OCR (gpt-4o) de las planillas manuscritas de producción.
// La llama Maestro Producción (cervantes-admin/*/Produccion/maestro.html).
//
// 2026-09-13: se sacó la clave de OpenAI que estaba pegada como fallback (pedido del dueño).
// Ahora la clave sale SOLO del secret OPENAI_API_KEY del proyecto.
//
// 2026-09-28 (v23.40, seguridad): hasta acá NO pedía nada — con la clave pública, que está
// en el repo público, cualquiera mandaba imágenes en loop a gpt-4o (detail high) a costo de
// la empresa. Ahora:
//   1) exige la SESIÓN de una cuenta habilitada (Google, public.get_role_for_email), la misma
//      que ya pide la pantalla (auth-guard). La clave pública sola -> 401;
//   2) tope diario de lecturas (TOPE_DIA, contado en costos_api por costo_api_usos_hoy) -> 429;
//   3) tope de tamaño de imagen -> 413.
// Versionada en el repo desde esta versión (antes vivía solo en Supabase).

const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");
const SB_URL = Deno.env.get("SUPABASE_URL") || "";
const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const APP = "leer-produccion-foto";
const TOPE_DIA = 100;               // lecturas por día (hoy se usa ~0/día)
const MAX_B64 = 15_000_000;         // ~11 MB de imagen

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function srv(path: string, body: unknown) {
  return fetch(`${SB_URL}/rest/v1/${path}`, {
    method: "POST",
    headers: { apikey: SRK, authorization: `Bearer ${SRK}`, "content-type": "application/json" },
    body: JSON.stringify(body)
  });
}

// Devuelve el email si el Bearer es la sesión de una cuenta habilitada; si no, null.
async function usuarioHabilitado(req: Request): Promise<string | null> {
  const authz = req.headers.get("authorization") || "";
  const jwt = authz.replace(/^Bearer\s+/i, "").trim();
  // La clave pública (sb_publishable_…) no es un usuario: se corta acá.
  if (!jwt || jwt.split(".").length !== 3) return null;
  const u = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: SRK, authorization: `Bearer ${jwt}` } });
  if (!u.ok) return null;
  const email = String((await u.json())?.email || "").trim();
  if (!email) return null;
  const r = await srv("rpc/get_role_for_email", { p_email: email });
  if (!r.ok) return null;
  const rol = await r.json();
  return rol ? email : null;
}

async function usosHoy(): Promise<number> {
  const r = await srv("rpc/costo_api_usos_hoy", { p_app: APP });
  if (!r.ok) throw new Error("no se pudo verificar el tope diario");
  return Number(await r.json()) || 0;
}

// 2026-09-15: reporte de consumo de IA. La RPC public.registrar_costo_api calcula el costo
// desde costos_api.tarifas por (empresa, modelo); desde acá sólo se pasan los tokens que
// devuelve OpenAI en `usage`. Es best-effort: si falla, NO rompe la lectura de la planilla.
// Además es lo que cuenta el tope diario.
async function reportarCosto(usage: Record<string, number> | undefined, email: string): Promise<void> {
  try {
    if (!SB_URL || !SRK) return;
    await srv("rpc/registrar_costo_api", {
      p_empresa: "OpenAI",
      p_cuenta: "Gestion Productiva",
      p_app: APP,
      p_modelo: "gpt-4o",
      p_input_tokens: usage?.prompt_tokens ?? null,
      p_output_tokens: usage?.completion_tokens ?? null,
      p_cantidad: 1,
      p_origen: "auto",
      p_metadata: { tipo: "ocr_planilla_produccion", usuario: email }
    });
  } catch (_e) {
    /* el costo no es crítico para el OCR */
  }
}

const MESES: Record<string, number> = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6,
  julio: 7, agosto: 8, septiembre: 9, octubre: 10, noviembre: 11, diciembre: 12
};

const SYSTEM_PROMPT = `Sos un OCR especializado en planillas manuscritas de produccion de fabrica. La planilla tiene encabezado con \"Leg N\" (legajo del operario), nombre del operario, y mes (en espanol).

La tabla tiene columnas: N Día | N Matriz | Hora Inicio | Hora Final | Unidades Reloj.

Devolves UNICAMENTE un JSON valido (sin markdown) con esta estructura:

{
  \"legajo\": \"95\",
  \"mes\": \"abril\",
  \"anio\": null,
  \"filas\": [
    { \"dia\": 18, \"codigo\": \"9\", \"tipo\": \"matriz\", \"hIni\": \"08:30:00\", \"hFin\": \"11:25:00\", \"uni\": 2500 },
    { \"dia\": 23, \"codigo\": \"FUTBOL\", \"tipo\": \"tm\", \"hIni\": \"08:30:00\", \"hFin\": \"11:30:00\", \"uni\": 0 }
  ]
}

Reglas CRITICAS:
- legajo: del encabezado \"Leg N\". Si no se ve, null.
- mes: nombre en minusculas (enero..diciembre). Si no se ve, null.
- anio: numero si se ve. Sino null.
- filas: una por cada renglon que contenga al menos un dato visible. NO inventes datos.
- dia: entero 1-31. Si no se ve, null.
- codigo: tal como aparece en columna N Matriz. Si es solo digitos (\"9\", \"112\") es matriz numerica (tipo=\"matriz\"). Si tiene letras (\"FUTBOL\", \"MEMBRILLO\", \"PB\", \"PC\", \"MOV\", \"LIMP\", \"AL\", \"PR\", \"BC\") es tiempo muerto (tipo=\"tm\"). Si no se lee, codigo=null y tipo=\"matriz\".
- hIni / hFin: formato HH:MM:SS. Si solo hay HH:MM agregar \":00\". **IMPORTANTE: Si NO podes leer la hora con seguridad, devolve null. NO devuelvas \"00:00:00\" ni \"00:00\" ni adivines.**
- uni: entero. Si no se lee, null. Si es tipo \"tm\" siempre 0. **NO devuelvas 0 cuando no podes leer; devolve null.**
- Filas tachadas o ilegibles completas: omitirlas (no incluirlas).
- Filas parcialmente legibles: incluilas con los campos que pudiste leer y null en los que no.

Devolves SOLO el JSON.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    if (!OPENAI_KEY) {
      return json({ error: "Falta el secret OPENAI_API_KEY en el proyecto (la clave pegada en el código se sacó el 2026-09-13)" }, 500);
    }
    if (!SB_URL || !SRK) return json({ error: "Configuración del servidor incompleta" }, 503);

    const email = await usuarioHabilitado(req);
    if (!email) {
      return json({ error: "Sin permiso: iniciá sesión con una cuenta habilitada para leer planillas." }, 401);
    }

    let usos: number;
    try { usos = await usosHoy(); } catch (_e) {
      return json({ error: "No se pudo verificar el tope diario de lecturas. Probá de nuevo en un rato." }, 503);
    }
    if (usos >= TOPE_DIA) {
      return json({ error: `Se alcanzó el tope de ${TOPE_DIA} lecturas por día. Avisale a Thomas si hace falta más.` }, 429);
    }

    const { image_base64, mime } = await req.json();
    if (!image_base64) return json({ error: "Falta image_base64" }, 400);
    if (String(image_base64).length > MAX_B64) return json({ error: "La foto es demasiado grande (máx. ~11 MB)." }, 413);

    const imageUrl = image_base64.includes(",") ? image_base64 : `data:${mime || "image/jpeg"};base64,${image_base64}`;
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Authorization": `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "gpt-4o",
        max_tokens: 4096,
        temperature: 0,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: [
            { type: "image_url", image_url: { url: imageUrl, detail: "high" } },
            { type: "text", text: "Analiza esta planilla y devuelve el JSON. Recordatorio: si no podes leer un valor, devolve null. NO inventes ni uses 00:00 como fallback." }
          ]}
        ]
      })
    });
    if (!res.ok) {
      const errTxt = await res.text();
      return json({ error: "OpenAI API: " + errTxt }, 500);
    }
    const aiData = await res.json();
    // El gasto se reporta apenas OpenAI contesta: la llamada ya se pagó.
    await reportarCosto(aiData?.usage, email);
    const text = aiData?.choices?.[0]?.message?.content || "";
    let parsed: any;
    try {
      let jsonStr = text;
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (jsonMatch) jsonStr = jsonMatch[0];
      parsed = JSON.parse(jsonStr);
    } catch (_e) {
      return json({ error: "Respuesta no es JSON valido", raw: text }, 500);
    }
    let mesNum: number | null = null;
    if (parsed.mes && typeof parsed.mes === "string") {
      const m = parsed.mes.toLowerCase().trim();
      if (MESES[m]) mesNum = MESES[m];
    }
    return json({
      legajo: parsed.legajo ? String(parsed.legajo).trim() : null,
      mes: mesNum,
      anio: parsed.anio || null,
      filas: Array.isArray(parsed.filas) ? parsed.filas : []
    });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
