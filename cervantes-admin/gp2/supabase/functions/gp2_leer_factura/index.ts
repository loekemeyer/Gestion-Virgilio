import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/* =========================================================
   gp2_leer_factura — lee una factura o remito (PDF o foto) y devuelve JSON.

   Es el paso 1 de la lectura de facturas de GP2 (idea 7338). SOLO LEE: no toca
   la base salvo para contar la llamada. Lo que sale de aca va a GP2.factura_match(),
   que decide que componente es cada renglon, y recien despues la persona confirma.

   La clave va SOLO como secret (ANTHROPIC_API_KEY_GP2). NUNCA hardcodeada como
   fallback: eso es lo que tiene la vieja leer-factura del programa viejo y por lo
   que quedo un problema abierto en la auditoria (2026-09-13).

   TOPE DIARIO (idea 7339): esta funcion CUESTA PLATA POR LLAMADA y su puerta es la
   clave publicable, que es publica. Antes de pegarle a la API suma la llamada del dia
   con GP2.factura_lectura_permitida(); pasado el tope (parametro.facturas_lecturas_x_dia)
   devuelve 429 y no gasta un peso mas.

   v18 (2026-09-28) — reenvia el JWT de la sesion al pedir el tope (fase B: solo usuarios habilitados).
   v17 (2026-09-28) — EL TOPE YA NO SE SALTEA (auditoria de seguridad, punto 2).
   Hasta la v16 la puerta aceptaba CUALQUIER texto que empezara con "sb_publishable_",
   y si la consulta del tope fallaba el codigo seguia de largo ("el tope no puede romper
   la recepcion"). Juntas, las dos cosas dejaban llamar a la IA sin limite con una clave
   inventada: PostgREST rechazaba la clave falsa, el tope "fallaba" y se pagaba igual.
   Ahora:
     1. La clave la valida la BASE: el tope se consulta con la clave que trajo el
        llamador, y PostgREST solo contesta 200 a una clave real del proyecto. No hace
        falta escribir la publicable en esta funcion.
     2. El tope es OBLIGATORIO (fail-closed): si no se pudo verificar, no se llama a la
        API. Una lectura que no sale se carga a mano; una API sin tope se paga sin fondo.
     3. Tope de tamano del archivo, para que una sola llamada no pueda ser gigante.

   REPORTE DE CONSUMO (2026-09-15): ademas del tope, cada llamada se registra en
   public.registrar_costo_api, que calcula el costo desde costos_api.tarifas por
   (empresa, modelo). OJO: la tarifa de 'claude-opus-5' NO esta cargada en
   costos_api.tarifas, asi que hasta que se cargue quedan registrados los tokens y la
   llamada, pero el costo sale en null.
   ========================================================= */

const MODELO = "claude-opus-5";

// ~15 MB de archivo real (el base64 pesa 4/3). Una factura escaneada anda muy por debajo.
const MAX_B64 = 20_000_000;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

/* Reporte de consumo. Best-effort y con service_role, porque registrar_costo_api es
   SECURITY DEFINER y anon no la puede ejecutar. Si falla, NO rompe la lectura: la
   llamada a Anthropic ya se pago igual. */
async function reportarCosto(usage: { input_tokens?: number; output_tokens?: number } | undefined, modelo: string | undefined): Promise<void> {
  try {
    const SB_URL = Deno.env.get("SUPABASE_URL") || "";
    const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    if (!SB_URL || !SRK) return;
    await fetch(`${SB_URL}/rest/v1/rpc/registrar_costo_api`, {
      method: "POST",
      headers: {
        apikey: SRK,
        authorization: `Bearer ${SRK}`,
        "content-type": "application/json",
        "content-profile": "public",
      },
      body: JSON.stringify({
        p_empresa: "Claude",
        p_cuenta: "GP2",
        p_app: "gp2_leer_factura",
        p_modelo: modelo || MODELO,
        p_input_tokens: usage?.input_tokens ?? null,
        p_output_tokens: usage?.output_tokens ?? null,
        p_cantidad: 1,
        p_origen: "auto",
        p_metadata: { tipo: "lectura_factura" },
      }),
    });
  } catch (_e) { /* el costo no puede romper la recepcion */ }
}

/* Las trampas de la factura argentina (ARCA/AFIP). Esta parte viene peleada del
   prompt de la funcion vieja: el punto de miles, la coma decimal, el CUIT con
   guiones, razon social legal vs nombre de fantasia, y el codigo de articulo. */
const SYSTEM = `Sos un lector de facturas y remitos argentinos (ARCA/AFIP) para una fabrica metalurgica.
Lee el comprobante con EXTREMO cuidado y devolve los datos tal cual figuran.

REGLAS QUE NO SE NEGOCIAN:
1. Lee TODOS los renglones. No omitas ninguno y no combines dos en uno.
2. "codigo" es el codigo de articulo del PROVEEDOR tal cual aparece en el renglon (puede ser numerico largo, alfanumerico o vacio). Si no hay codigo visible, null. NO lo inventes ni lo deduzcas de la descripcion.
3. "descripcion" es el texto del renglon tal cual, sin traducir ni acortar.
4. Numeros argentinos: el PUNTO es separador de miles y la COMA es decimal. "1.000" es mil; "128,26" es ciento veintiocho con veintiseis. Devolve todo como number con punto decimal: 1000 y 128.26.
5. Cantidades: respeta la unidad del renglon (kg, unidades, metros, bolsas...). Si el remito dice kg, la unidad es kg.
6. CUIT completo con guiones tal cual aparece.
7. Razon social: usa el nombre LEGAL del emisor en razon_social_emisor; si ademas hay nombre de fantasia, ponelo en nombre_fantasia.
8. Si un dato no esta visible, devolve null. NUNCA completes con un valor probable.
9. Si el papel es un REMITO y no una factura, igual devolve los renglones y poni tipo_comprobante: "Remito".`;

const SCHEMA = {
  type: "object",
  properties: {
    razon_social_emisor: { type: ["string", "null"] },
    nombre_fantasia: { type: ["string", "null"] },
    cuit_emisor: { type: ["string", "null"] },
    fecha_emision: { type: ["string", "null"], description: "DD/MM/YYYY tal cual figura" },
    tipo_comprobante: { type: ["string", "null"] },
    punto_venta: { type: ["string", "null"] },
    numero_comprobante: { type: ["string", "null"] },
    remito: { type: ["string", "null"], description: "numero de remito si el comprobante lo menciona" },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          codigo: { type: ["string", "null"] },
          descripcion: { type: "string" },
          cantidad: { type: ["number", "null"] },
          unidad_medida: { type: ["string", "null"] },
          precio_unitario: { type: ["number", "null"] },
          subtotal: { type: ["number", "null"] },
        },
        required: ["codigo", "descripcion", "cantidad", "unidad_medida", "precio_unitario", "subtotal"],
        additionalProperties: false,
      },
    },
    importe_total: { type: ["number", "null"] },
  },
  required: [
    "razon_social_emisor", "nombre_fantasia", "cuit_emisor", "fecha_emision", "tipo_comprobante",
    "punto_venta", "numero_comprobante", "remito", "items", "importe_total",
  ],
  additionalProperties: false,
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "Solo POST" }, 405);

  /* Puerta de entrada: la funcion corre sin verify_jwt (la app usa la clave
     publicable, que no es un JWT). Aca solo se exige que venga UNA clave; si es
     real o no lo decide la base en el paso del tope (ver v17 arriba).
     v18 (fase B, 2026-09-28): el tope se pide reenviando el Authorization TAL CUAL
     vino (el JWT de la sesion del usuario) + la apikey. Desde la fase B la base solo
     deja pedir el tope a un usuario logueado de la whitelist, asi que sin sesion no
     hay lectura. */
  const apikey = (req.headers.get("apikey") || "").trim();
  const authz = (req.headers.get("authorization") || "").trim();
  const traida = apikey || authz.replace(/^Bearer\s+/i, "");
  if (!traida) return json({ error: "Falta la clave del proyecto" }, 401);

  const API_KEY = Deno.env.get("ANTHROPIC_API_KEY_GP2");
  if (!API_KEY) {
    // A proposito NO hay clave de fallback en el codigo: si falta el secret, se avisa.
    return json({ error: "Falta el secret ANTHROPIC_API_KEY_GP2 en el proyecto" }, 500);
  }
  const SB_URL = Deno.env.get("SUPABASE_URL");
  if (!SB_URL) return json({ error: "Falta SUPABASE_URL en el entorno de la funcion" }, 500);

  let body: { archivo_b64?: string; mime?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body invalido" }, 400);
  }

  const mime = (body.mime || "").toLowerCase();
  let b64 = body.archivo_b64 || "";
  if (!b64) return json({ error: "No llego el archivo (archivo_b64)" }, 400);
  if (b64.includes(",")) b64 = b64.split(",").pop() as string;   // por si viene como data: URL
  b64 = b64.replace(/\s/g, "");
  if (b64.length > MAX_B64) return json({ error: "El archivo es demasiado grande (maximo ~15 MB)" }, 413);

  /* Tope diario, OBLIGATORIO. Se pide DESPUES de validar el archivo (para no gastar
     cupo con llamadas rotas) y ANTES de la API (para no gastar plata). Va con la clave
     del llamador: si PostgREST no la acepta, no es una clave del proyecto y se corta
     aca. Si la base no contesta, tambien se corta: sin tope verificado no hay IA. */
  let t: Response;
  try {
    t = await fetch(`${SB_URL}/rest/v1/rpc/factura_lectura_permitida`, {
      method: "POST",
      headers: {
        "apikey": apikey || traida, "Authorization": authz || `Bearer ${traida}`,
        "Content-Type": "application/json", "Accept-Profile": "GP2", "Content-Profile": "GP2",
      },
      body: "{}",
    });
  } catch {
    return json({ error: "No se pudo verificar el tope diario (la base no contesta). Proba de nuevo o cargala a mano." }, 503);
  }
  if (t.status === 401 || t.status === 403) return json({ error: "Sin permiso: inicia sesion con una cuenta habilitada (o la clave no es del proyecto)" }, 401);
  if (!t.ok) return json({ error: "No se pudo verificar el tope diario (HTTP " + t.status + "). Proba de nuevo o cargala a mano." }, 503);
  const cupo = await t.json().catch(() => null);
  if (!cupo || cupo.ok !== true) {
    if (cupo && cupo.ok === false) {
      return json({
        error: `Se llego al tope de ${cupo.tope} lecturas por dia (van ${cupo.usadas}). ` +
               `Si hace falta mas, subir GP2.parametro.facturas_lecturas_x_dia.`,
        tope: cupo.tope, usadas: cupo.usadas,
      }, 429);
    }
    return json({ error: "El tope diario devolvio una respuesta inesperada. No se llamo a la IA." }, 503);
  }

  const esPdf = mime.includes("pdf");
  const bloque = esPdf
    ? { type: "document", source: { type: "base64", media_type: "application/pdf", data: b64 } }
    : { type: "image", source: { type: "base64", media_type: mime || "image/jpeg", data: b64 } };

  let r: Response;
  try {
    r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODELO,
        max_tokens: 16000,
        // extraccion, no razonamiento largo: alcanza con effort medio y sale mas barato
        output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
        system: SYSTEM,
        messages: [{
          role: "user",
          content: [bloque, { type: "text", text: "Leé este comprobante y devolvé los datos. Prestá especial atención a los códigos de artículo y a las cantidades." }],
        }],
      }),
    });
  } catch (e) {
    return json({ error: "No se pudo llamar a la API: " + String(e) }, 502);
  }

  const data = await r.json().catch(() => null);
  if (!r.ok) return json({ error: "La API respondio " + r.status, detalle: data }, 502);

  /* Se reporta apenas contesta la API y antes de cualquier return posterior: la
     llamada ya se pago, haya salido bien el parseo o no. */
  await reportarCosto(data?.usage, data?.model);

  if (data?.stop_reason === "refusal") {
    return json({ error: "La lectura fue rechazada por seguridad del modelo", detalle: data?.stop_details }, 422);
  }

  const texto = (data?.content || []).filter((b: { type: string }) => b.type === "text")
    .map((b: { text: string }) => b.text).join("");
  let parsed: unknown = null;
  try {
    parsed = JSON.parse(texto);
  } catch {
    const m = texto.match(/\{[\s\S]*\}/);
    if (m) { try { parsed = JSON.parse(m[0]); } catch { /* queda null */ } }
  }
  if (!parsed) return json({ error: "El modelo no devolvio JSON legible", crudo: texto.slice(0, 2000) }, 502);

  return json({
    ok: true,
    factura: parsed,
    uso: { entrada: data?.usage?.input_tokens, salida: data?.usage?.output_tokens, modelo: data?.model },
  });
});
