import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// send-whatsapp — manda WhatsApp desde el número de la empresa (N8N Loekemeyer).
// Versionada en el repo desde el 2026-09-28 (v55); antes vivía solo en Supabase.
//
// ===== CREDENCIALES =====
// Ya NO van en el codigo. El 15/09/2026 se roto el token de Meta y se revoco el viejo:
// esta funcion quedo rota en silencio porque lo tenia escrito aca, igual que
// send-rendimiento-matrices y reporte-diario-rendimiento (problema 20 de la auditoria).
// Ahora el token y el phone_id salen de lecturacvs.server_secrets, via la RPC
// public.server_secret, que solo puede ejecutar service_role. Rotar = cambiar una fila.
const SUPABASE_URL = "https://hrxfctzncixxqmpfhskv.supabase.co";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const WA_PHONE_ID_FALLBACK = "918089688061759";

// ===== A QUIEN SE LE MANDA =====
// Los destinos viven SOLO aca. Hasta el 15/09/2026 la funcion aceptaba `destinatario` y
// `destinatarios` desde el body, y verify_jwt=true no protege nada porque la clave
// sb_publishable_ esta escrita en todas las paginas del sistema. Resultado: cualquiera
// podia mandar un mensaje con texto arbitrario, desde el numero verificado de la empresa,
// al telefono que quisiera. Un relay abierto.
//
// Si algun dia hace falta un destino nuevo, se agrega un grupo ACA, no se abre el body.
const DESTINATARIOS = ["5491131181594", "5491131181027", "5491162521635"];
const DESTINATARIOS_TEST = ["5491131181027", "5491162521635"];

// Grupos con nombre. Orden de DESTINATARIOS: [0]=Damian, [1]=Logistica, [2]=Thomy.
const GRUPOS: Record<string, string[]> = {
  todos: DESTINATARIOS,
  thomy_damian: ["5491131181594", "5491162521635"], // Damian + Thomy (sin Logistica)
  // Para probar la funcion sin molestar a nadie de produccion. Existe porque el 15/09/2026,
  // al verificar el cierre del relay, la prueba salio por thomy_damian y les llego un
  // "prueba, ignorar" a los dos. Probar contra este grupo, no contra los reales.
  pruebas: ["5491156517686"],                       // Elias
};

// ===== 2026-09-28 (v55, seguridad + arreglo de Planify) =====
// 1) TEXTO LIBRE (`_texto_libre`) y destinatario libre solo desde el servidor: el Bearer
//    tiene que ser la clave de servicio. Con la clave publica cualquiera les mandaba a
//    Damian, Logistica y Thomy texto con links desde el numero de la empresa. Unico
//    llamador real: gv-alta-articulo (servidor, le escribe a Thomas). Las pantallas usan
//    plantillas y no cambian.
// 2) EXCEPCION con destinatario, para el aviso "sugerencia aprobada" del Recorrido de
//    Planify (main.js, IPC rec-notify-wa), que manda el telefono del empleado que sugirio
//    la parada y desde el 15/09 recibia 400 (el aviso no le llegaba a nadie). Se acepta
//    SOLO si: la plantilla es sugerencia_poli_aceptada, el telefono es de un empleado de
//    planify.employees, ese empleado tiene una sugerencia APROBADA en los ultimos 30 min
//    que todavia no se aviso (planify.recorrido_sugerencia_aviso_wa: una por sugerencia) y
//    los parametros no traen links. Asi la clave publica no vuelve a ser un relay.
const PLANTILLA_SUGERENCIA = "sugerencia_poli_aceptada";
const PLANTILLAS_PUBLICAS = [
  "problemas_en_matriz_reducido", // tablet de operarios (default) + botón de prueba de Alertas
  "problema_en_matriz_completo",  // tablet de operarios (si wa_plantilla_activa lo elige)
  "ajuste_stock_inicial",         // Envíos PS
  PLANTILLA_SUGERENCIA,           // Planify, recorrido (con las validaciones de abajo)
];
const VENTANA_SUGERENCIA_MIN = 30;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

async function leerSecret(sb: any, clave: string, fallback?: string): Promise<string> {
  try {
    const { data, error } = await sb.rpc("server_secret", { p_k: clave });
    if (!error && data) return String(data);
    if (error) console.error(`server_secret(${clave}): ${error.message}`);
  } catch (err) {
    console.error(`server_secret(${clave}): ${err}`);
  }
  if (fallback !== undefined) return fallback;
  throw new Error(`falta el secreto ${clave} en lecturacvs.server_secrets`);
}

function esServidor(req: Request): boolean {
  const t = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
  return !!SUPABASE_SERVICE_KEY && t === SUPABASE_SERVICE_KEY;
}

function soloDigitos(v: unknown) { return String(v ?? "").replace(/\D/g, ""); }
function ult10(v: unknown) { return soloDigitos(v).slice(-10); }
function sinLinks(v: unknown, max: number) {
  return String(v ?? "")
    .replace(/(https?:\/\/|www\.)\S*/gi, "")
    .replace(/\S+\.[a-z]{2,}\S*/gi, "")
    .replace(/\s+/g, " ").trim().slice(0, max);
}

// Devuelve {numero, sugerenciaId} si el aviso de Planify es legitimo; si no, un error.
async function validarAvisoSugerencia(sb: any, destinatario: unknown):
  Promise<{ numero: string; sugerenciaId: number } | { error: string }> {
  const d10 = ult10(destinatario);
  if (d10.length !== 10) return { error: "telefono invalido" };
  const { data: emps, error: e1 } = await sb.schema("planify").from("employees").select("id, telefono");
  if (e1) return { error: "no se pudo leer employees" };
  const emp = (emps || []).find((e: any) => ult10(e.telefono) === d10);
  if (!emp) return { error: "el telefono no es de un empleado" };
  const desde = new Date(Date.now() - VENTANA_SUGERENCIA_MIN * 60_000).toISOString();
  const { data: sugs, error: e2 } = await sb.schema("planify").from("recorrido_sugerencias")
    .select("id").eq("employee_id", emp.id).eq("estado", "aprobada").gte("resuelto_at", desde)
    .order("resuelto_at", { ascending: false }).limit(10);
  if (e2) return { error: "no se pudo leer recorrido_sugerencias" };
  const ids = (sugs || []).map((s: any) => s.id);
  if (!ids.length) return { error: "no hay una sugerencia aprobada reciente de ese empleado" };
  const { data: ya } = await sb.schema("planify").from("recorrido_sugerencia_aviso_wa")
    .select("sugerencia_id").in("sugerencia_id", ids);
  const avisadas = new Set((ya || []).map((r: any) => r.sugerencia_id));
  const libre = ids.find((id: number) => !avisadas.has(id));
  if (!libre) return { error: "esa sugerencia ya se aviso" };
  const dig = soloDigitos(emp.telefono);
  const numero = dig.length === 10 ? "549" + dig : dig;
  return { numero, sugerenciaId: libre };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const cuerpo = await req.json();
    const { mensaje, parametros, plantilla, idioma, test, grupo } = cuerpo;
    const templateName = plantilla || "problemas_en_matriz_reducido";
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    if (templateName === "_texto_libre" && !esServidor(req)) {
      return json({ error: "el texto libre solo se acepta desde el servidor" }, 403);
    }

    let nums: string[];
    let sugerenciaId: number | null = null;
    let params = parametros;

    const servidor = esServidor(req);

    // Con la clave publica: solo las plantillas que usan las pantallas (relevadas en los
    // 45 repos el 28/09) y parametros sin links. El servidor no tiene esta restriccion.
    if (!servidor) {
      if (!PLANTILLAS_PUBLICAS.includes(templateName)) {
        return json({ error: "plantilla no permitida", permitidas: PLANTILLAS_PUBLICAS }, 403);
      }
      params = Array.isArray(parametros) ? parametros.slice(0, 8).map((p: unknown) => sinLinks(p, 200)) : parametros;
    }

    if (!servidor && (cuerpo?.destinatarios !== undefined ||
        (cuerpo?.destinatario !== undefined && templateName !== PLANTILLA_SUGERENCIA))) {
      // Se rechaza de forma RUIDOSA en vez de ignorar el campo en silencio.
      return json({
        error: "destinatario/destinatarios ya no se aceptan desde el body",
        detalle: "Los destinos viven en el servidor. Usa 'grupo' o el default.",
        grupos_disponibles: Object.keys(GRUPOS),
      }, 400);
    }

    if (servidor && (cuerpo?.destinatario !== undefined || cuerpo?.destinatarios !== undefined)) {
      // Otra Edge Function (clave de servicio) elige el destino: es codigo propio, no la
      // clave publica. Es el caso de gv-alta-articulo (le escribe a Thomas), que desde el
      // 15/09 tambien recibia 400 y solo avisaba por Telegram.
      const lista = cuerpo.destinatarios !== undefined ? cuerpo.destinatarios : [cuerpo.destinatario];
      nums = (Array.isArray(lista) ? lista : [lista]).map(soloDigitos).filter((n: string) => n.length >= 10);
      if (!nums.length) return json({ error: "destinatario invalido" }, 400);
    } else if (cuerpo?.destinatario !== undefined) {
      // Aviso "sugerencia aprobada" de Planify: ver bloque v55 arriba.
      const v = await validarAvisoSugerencia(sb, cuerpo.destinatario);
      if ("error" in v) return json({ error: "aviso de sugerencia rechazado: " + v.error }, 403);
      nums = [v.numero];
      sugerenciaId = v.sugerenciaId;
      params = Array.isArray(parametros) ? parametros.slice(0, 2).map((p: unknown) => sinLinks(p, 150)) : [];
      // Se anota ANTES de mandar: un segundo pedido igual ya no pasa.
      const { error: eIns } = await sb.schema("planify").from("recorrido_sugerencia_aviso_wa")
        .insert({ sugerencia_id: sugerenciaId, telefono: v.numero });
      if (eIns) return json({ error: "esa sugerencia ya se aviso" }, 409);
    } else {
      // Prioridad: grupo con nombre > default (o test). Todos resueltos en el servidor.
      nums = (grupo && GRUPOS[grupo]) ? GRUPOS[grupo] : (test ? DESTINATARIOS_TEST : DESTINATARIOS);
    }

    const WA_TOKEN = await leerSecret(sb, "REPORTES_WA_TOKEN");
    const WA_PHONE_ID = await leerSecret(sb, "REPORTES_WA_PHONE_ID", WA_PHONE_ID_FALLBACK);
    const lang = idioma || "es_AR";
    const url = `https://graph.facebook.com/v21.0/${WA_PHONE_ID}/messages`;

    const resultados: { numero: string; ok: boolean; error?: string }[] = [];

    for (const num of nums) {
      let body: Record<string, unknown>;

      if (templateName === "_texto_libre") {
        body = {
          messaging_product: "whatsapp",
          to: num,
          type: "text",
          text: { body: mensaje || "" },
        };
      } else {
        let templateParams: { type: string; text: string }[];

        if (Array.isArray(params) && params.length > 0) {
          templateParams = params.map((p: string) => ({ type: "text", text: String(p) }));
        } else {
          templateParams = [{ type: "text", text: servidor ? (mensaje || "") : sinLinks(mensaje, 200) }];
        }

        body = {
          messaging_product: "whatsapp",
          to: num,
          type: "template",
          template: {
            name: templateName,
            language: { code: lang },
            components: [
              {
                type: "body",
                parameters: templateParams,
              },
            ],
          },
        };
      }

      try {
        const res = await fetch(url, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${WA_TOKEN}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(body),
        });

        const data = await res.json();

        if (res.ok) {
          resultados.push({ numero: num, ok: true });
        } else {
          resultados.push({ numero: num, ok: false, error: data?.error?.message || JSON.stringify(data) });
        }
      } catch (err) {
        resultados.push({ numero: num, ok: false, error: String(err) });
      }
    }

    if (sugerenciaId !== null) {
      const r0 = resultados[0];
      await sb.schema("planify").from("recorrido_sugerencia_aviso_wa")
        .update({ ok: !!r0?.ok, error: r0?.error ?? null }).eq("sugerencia_id", sugerenciaId);
    }

    const enviados = resultados.filter((r) => r.ok).length;

    return json({ enviados, total: nums.length, resultados });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
