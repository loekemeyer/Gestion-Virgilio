import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/* =============================================================================
   gv-alta-articulo — v15.37
   Recepción: cuando un operario va a dar de alta un artículo NUEVO que no figura
   en la planimetría, acá se pide el OK de Thomas por WhatsApp y la recepción
   queda trabada hasta que él confirme.

   Pedido del dueño (2026-09-11): "si están por recibir un artículo nuevo que no
   figuraba en la planimetría, me mandan un mensaje directo a WhatsApp a mi
   teléfono, para que antes de dejarlos cargar me tengan que decir 'hola Thomy,
   estoy creando un artículo nuevo, que es el tanto, ¿me confirmás que está bien?'
   y que no puedan cerrar la recepción sin que yo dé ese ok".

   La FUENTE DE VERDAD es la tabla GV_Alta_Articulo_Aprobacion. El front sólo la
   lee (anon tiene SELECT y nada más), así que desde el celular no se puede
   auto-aprobar: las escrituras las hace esta función con service_role.

   POST {accion:"pedir", cod, remito, legajo, tall, linea}
        -> crea/reusa el pedido, manda el WhatsApp y devuelve { token, estado }.
   GET  ?token=…&r=ok|no        -> página de confirmación con un botón.
   GET  ?token=…&r=ok|no&c=1    -> recién acá se resuelve.

   El doble paso del GET es a propósito: WhatsApp (y cualquier cliente que haga
   preview del link) pega un GET al abrir el mensaje. Si el primer GET resolviera,
   el preview aprobaría solo. Por eso el primer GET sólo muestra el botón.
   ============================================================================= */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TABLA = "GV_Alta_Articulo_Aprobacion";
const FN_BASE = `${SUPABASE_URL}/functions/v1/gv-alta-articulo`;

// Thomas Loekemeyer (planify.employees id 3). Mismo número que ya conoce la
// Edge Function send-whatsapp.
const TEL_THOMAS = "5491162521635";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function rest(path: string, init: RequestInit = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function html(body: string, status = 200) {
  return new Response(
    `<!doctype html><meta charset="utf-8">
     <meta name="viewport" content="width=device-width,initial-scale=1">
     <title>Alta de artículo</title>
     <style>
       body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;
            background:#0f1115;color:#e8eaed;display:flex;min-height:100vh;
            align-items:center;justify-content:center;padding:24px}
       .card{background:#171a21;border:1px solid #262b36;border-radius:16px;
             padding:28px;max-width:420px;width:100%;text-align:center}
       h1{font-size:19px;margin:0 0 14px}
       p{font-size:15px;line-height:1.5;color:#b9bfc9;margin:0 0 10px}
       b{color:#e8eaed}
       .cod{font-size:30px;font-weight:700;letter-spacing:1px;margin:14px 0}
       a.btn{display:block;margin-top:18px;padding:15px;border-radius:12px;
             font-size:17px;font-weight:600;text-decoration:none}
       .si{background:#1f7a3f;color:#fff}
       .no{background:#8c2b2b;color:#fff}
       .ok{color:#5fd08a;font-size:20px;font-weight:700}
       .bad{color:#ff8a8a;font-size:20px;font-weight:700}
     </style>
     <div class="card">${body}</div>`,
    { status, headers: { ...CORS, "Content-Type": "text/html; charset=utf-8" } },
  );
}

async function mandarWhatsapp(texto: string) {
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/send-whatsapp`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${SERVICE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        destinatario: TEL_THOMAS,
        plantilla: "_texto_libre",
        mensaje: texto,
      }),
    });
    const data = await res.json();
    if (res.ok && data?.enviados > 0) return { ok: true, error: null as string | null };
    const err = data?.resultados?.[0]?.error || data?.error || JSON.stringify(data);
    return { ok: false, error: String(err).slice(0, 500) };
  } catch (e) {
    return { ok: false, error: String(e).slice(0, 500) };
  }
}

/* Respaldo: si Meta rechaza el texto libre (la ventana de 24 h de WhatsApp está
   cerrada), el aviso igual tiene que llegar. Telegram ya es confiable acá. */
async function avisarTelegram(texto: string, dedup: string) {
  try {
    await rest("rpc/tg_enqueue", {
      method: "POST",
      body: JSON.stringify({ p_text: texto, p_dedup: dedup }),
    });
  } catch { /* best-effort */ }
}

function nuevoToken() {
  return crypto.randomUUID().replace(/-/g, "").slice(0, 24);
}

function norm(c: string) {
  return String(c || "").toUpperCase().trim().replace(/^0+(?=.)/, "");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const url = new URL(req.url);

  /* ---------- GET: Thomas abre el link del WhatsApp ---------- */
  if (req.method === "GET") {
    const token = url.searchParams.get("token") || "";
    const r = url.searchParams.get("r") || "";
    const confirmado = url.searchParams.get("c") === "1";
    if (!token || (r !== "ok" && r !== "no")) {
      return html(`<h1>Link inválido</h1><p>Falta el token o la respuesta.</p>`, 400);
    }

    const q = await rest(
      `${TABLA}?token=eq.${encodeURIComponent(token)}&select=*`,
    );
    const filas = await q.json();
    const fila = Array.isArray(filas) ? filas[0] : null;
    if (!fila) return html(`<h1>No encontrado</h1><p>Ese pedido ya no existe.</p>`, 404);

    if (fila.estado !== "pendiente") {
      const ya = fila.estado === "ok" ? "APROBADO" : "RECHAZADO";
      return html(
        `<h1>Ya estaba resuelto</h1><div class="cod">${fila.cod}</div>
         <p>Quedó <b>${ya}</b>. No hace falta hacer nada más.</p>`,
      );
    }

    // Primer GET (incluido el preview del link): sólo muestro el botón.
    if (!confirmado) {
      const cls = r === "ok" ? "si" : "no";
      const txt = r === "ok" ? "✅ Sí, que lo cree" : "❌ No, que no lo cree";
      const link = `${FN_BASE}?token=${encodeURIComponent(token)}&r=${r}&c=1`;
      return html(
        `<h1>Alta de artículo nuevo</h1>
         <div class="cod">${fila.cod}</div>
         <p>Remito <b>${fila.remito || "—"}</b> · ${fila.tallerista || "—"} · línea ${fila.linea || "—"}<br>
            Legajo <b>${fila.legajo || "—"}</b></p>
         <p>Tocá el botón para confirmar.</p>
         <a class="btn ${cls}" href="${link}">${txt}</a>`,
      );
    }

    const estado = r === "ok" ? "ok" : "rechazado";
    await rest(`${TABLA}?token=eq.${encodeURIComponent(token)}&estado=eq.pendiente`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        estado,
        resuelto_at: new Date().toISOString(),
        resuelto_por: "Thomas (WhatsApp)",
      }),
    });

    return estado === "ok"
      ? html(`<h1>Listo</h1><div class="cod">${fila.cod}</div>
              <p class="ok">✅ Aprobado</p>
              <p>Ya pueden terminar la recepción.</p>`)
      : html(`<h1>Listo</h1><div class="cod">${fila.cod}</div>
              <p class="bad">❌ Rechazado</p>
              <p>No van a poder cargar ese código.</p>`);
  }

  /* ---------- POST: la recepción pide el OK ---------- */
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let body: Record<string, string> = {};
  try { body = await req.json(); } catch { /* vacío */ }

  const cod = norm(body.cod || "");
  if (!cod) return json({ error: "falta cod" }, 400);

  const remito = String(body.remito || "").slice(0, 40);
  const legajo = String(body.legajo || "").slice(0, 20);
  const tall = String(body.tall || "").slice(0, 80);
  const linea = String(body.linea || "").slice(0, 10);

  // ¿Ya hay algo para este código? Si ya está aprobado, no molesto a Thomas de nuevo.
  const prevRes = await rest(
    `${TABLA}?cod=eq.${encodeURIComponent(cod)}&select=*&order=pedido_at.desc&limit=1`,
  );
  const prev = (await prevRes.json())?.[0];
  if (prev && (prev.estado === "pendiente" || prev.estado === "ok")) {
    return json({ token: prev.token, estado: prev.estado, reusado: true });
  }

  const token = nuevoToken();
  const ins = await rest(TABLA, {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({ token, cod, remito, legajo, tallerista: tall, linea }),
  });
  if (!ins.ok) {
    // Carrera: otro dispositivo acaba de crear el pendiente. Devuelvo ese.
    const otra = await rest(
      `${TABLA}?cod=eq.${encodeURIComponent(cod)}&estado=eq.pendiente&select=*&limit=1`,
    );
    const f = (await otra.json())?.[0];
    if (f) return json({ token: f.token, estado: f.estado, reusado: true });
    return json({ error: "no se pudo registrar el pedido" }, 500);
  }

  const linkOk = `${FN_BASE}?token=${token}&r=ok`;
  const linkNo = `${FN_BASE}?token=${token}&r=no`;
  const texto =
    `Hola Thomy 👋\n` +
    `Estoy creando un artículo NUEVO, que es el *${cod}*, y no figura en la planimetría.\n` +
    `¿Me confirmás que está bien?\n\n` +
    `Remito ${remito || "—"} · ${tall || "—"} · línea ${linea || "—"}\n` +
    `Legajo ${legajo || "—"}\n\n` +
    `✅ Sí, que lo cree:\n${linkOk}\n\n` +
    `❌ No:\n${linkNo}\n\n` +
    `(Hasta que contestes no pueden cerrar la recepción.)`;

  const wa = await mandarWhatsapp(texto);
  await rest(`${TABLA}?token=eq.${token}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ wa_ok: wa.ok, wa_error: wa.error }),
  });

  await avisarTelegram(
    `🆕 ALTA DE ARTÍCULO EN RECEPCIÓN — ${cod}\n` +
    `Remito ${remito || "—"} · ${tall || "—"} · línea ${linea || "—"} · legajo ${legajo || "—"}\n` +
    (wa.ok ? "WhatsApp enviado a Thomas." : `⚠ WhatsApp FALLÓ (${wa.error}). Aprobá por acá:`) +
    `\n✅ ${linkOk}\n❌ ${linkNo}`,
    `altaart_${token}`,
  );

  return json({ token, estado: "pendiente", wa_ok: wa.ok, wa_error: wa.error });
});
