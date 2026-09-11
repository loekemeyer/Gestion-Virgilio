// =============================================================================
// krikos-auto-import.js — el importador automático de las OC de súper
// =============================================================================
// Lo corre la Edge Function `krikos-auto-import` del Supabase de LK, que es un
// entrypoint de 3 líneas: importa este archivo desde el repo (público) de
// Gestión Virgilio, clavado al commit, y le pasa el request.
//
// QUÉ HACE: baja el PDF de la OC que ya guardó `krikos-ingest`, lo parsea con
// LOS MISMOS parsers del panel de LK (krikos-parsers.js, copiado textual de
// admin-supercot.js), matchea los códigos contra el catálogo y crea el pedido
// en `orders` + `order_items`. De ahí sigue el camino de siempre:
// v_pedidos_match → lk_pedidos_match → la PPP de Gestión.
//
// REGLA DEL DUEÑO (2026-09-11), textual: "Siempre quiero que se cargue directo
// a PPP y si la lógica del importe (ya explicado y hecho en paginaLK) NO DA,
// QUE LO ACLARE MUY GRANDE EN PPP".
//   → Una OC con renglones sin match, o con el total distinto al del PDF, IGUAL
//     se carga (auto_estado='parcial') y deja escrito en auto_aviso qué fue lo
//     que no dio; ese texto es el que la PPP pone en rojo arriba de A Programar.
//     Lo que NO se puede cargar (cadena desconocida, sin ítems, sin cliente)
//     queda pendiente, también con el motivo escrito.
//
// POR QUÉ EN EL SERVIDOR Y NO EN EL NAVEGADOR: tiene que correr solo, sin que
// nadie abra el panel. La extracción de texto con pdf.js corre igual en Deno
// (lo probó `krikos-pdf-text` contra OC reales: Coto 9/9, Carrefour 14/14,
// Diarco 10/10 idénticos a lo cargado a mano), así que lo único nuevo es la
// orquestación: los parsers son los mismos bytes que usa el panel.
//
//   POST {}                         → importa lo pendiente (uso del cron)
//   POST { dry_run: true }          → no escribe nada, devuelve el diagnóstico
//   POST { ids: [10], force: true } → esas OC, salteando el guarda de vencidas
//   header  x-krikos-secret: <KRIKOS_INGEST_SECRET>
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { getDocumentProxy } from "https://esm.sh/unpdf@0.12.1";
import { detectSuper, PARSERS, extractPdfTotal, codVariants, findInPool } from "./krikos-parsers.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
// Para pegarle a las otras Edge Functions alcanza con la anon: sheets-proxy sólo
// exige que venga UN bearer. La service_role no sale de esta función.
const ANON = Deno.env.get("SUPABASE_ANON_KEY") || "";
const BUCKET = "krikos-oc";
const SHEETS_PROXY_URL = SUPABASE_URL + "/functions/v1/sheets-proxy";
const SHEETS_ENTREGAS_URL = SUPABASE_URL + "/functions/v1/sheets-entregas-proxy";
// Coto pide el 505 como 505I. Igual que SUPER_COD_MAP de admin-supercot.js.
const SUPER_COD_MAP = { coto: { "505": "505I" } };
// Tolerancia del total contra el PDF: 1%, la misma con la que avisa la card.
const TOTAL_TOL = 0.01;

const sb = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function getSecret(name) {
  const env = Deno.env.get(name);
  if (env) return env;
  const { data } = await sb.rpc("krikos_secret", { p_name: name });
  return typeof data === "string" ? data : "";
}

// --- extracción de texto: calcada de extractPdfText() de admin-supercot.js ---
async function extractPdfText(buf) {
  const pdf = await getDocumentProxy(buf);
  const allLines = [];
  for (let p = 1; p <= pdf.numPages; p++) {
    const page = await pdf.getPage(p);
    const content = await page.getTextContent();
    const rows = {};
    for (const it of content.items) {
      const y = Math.round(it.transform[5]);
      let key = null;
      for (const k of Object.keys(rows)) {
        if (key == null && Math.abs(Number(k) - y) <= 1) key = k;
      }
      if (key == null) { rows[String(y)] = []; key = String(y); }
      rows[key].push({ x: it.transform[4], str: it.str });
    }
    const keys = Object.keys(rows).map(Number).sort((a, b) => b - a);
    for (const k of keys) {
      const line = rows[String(k)].sort((a, b) => a.x - b.x).map((r) => r.str).join(" ")
        .replace(/\s+/g, " ").trim();
      if (line) allLines.push(line);
    }
  }
  return allLines.join("\n");
}

// --- hoy en AR (UTC-3 fijo), para el guarda de vencidas ---
function hoyAr() {
  return new Date(Date.now() - 3 * 3600 * 1000).toISOString().slice(0, 10);
}
function fechaEntregaIso(raw) {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})/.exec(String(raw || ""));
  return m ? m[3] + "-" + m[2] + "-" + m[1] : null;
}

let cadenasCache = null;
async function loadCadenas() {
  if (cadenasCache) return cadenasCache;
  const { data, error } = await sb.rpc("krikos_auto_cadenas");
  if (error) throw new Error("cadenas: " + error.message);
  const out = {};
  for (const c of data || []) out[c.super_key] = c;
  cadenasCache = out;
  return out;
}

let productsCache = null;
let lokeCache = null;
async function loadPool(tabla) {
  const PAGE = 1000;
  let all = [];
  let offset = 0;
  for (;;) {
    const r = await sb.from(tabla).select("id,cod,description,list_price,uxb").range(offset, offset + PAGE - 1);
    if (r.error) throw new Error(tabla + ": " + r.error.message);
    const batch = r.data || [];
    all = all.concat(batch);
    if (batch.length < PAGE) break;
    offset += PAGE;
  }
  return all;
}
async function loadProducts() {
  if (!productsCache) productsCache = await loadPool("products");
  if (!lokeCache) lokeCache = await loadPool("loke_products");
}

let preciosCache = null;
async function loadPrecios() {
  if (preciosCache) return preciosCache;
  const { data, error } = await sb.rpc("krikos_auto_precios");
  if (error) throw new Error("precios: " + error.message);
  const out = {};
  for (const row of data || []) {
    const sk = row.super_key;
    const cod = String(row.cod || "").trim().toUpperCase();
    if (!sk || !cod) continue;
    if (!out[sk]) out[sk] = {};
    if (out[sk][cod] == null) out[sk][cod] = Number(row.price);   // first-wins, igual que el panel
  }
  preciosCache = out;
  return out;
}
function superListPrice(precios, sk, cod) {
  const dict = precios[sk];
  if (!dict) return null;
  for (const v of codVariants(cod)) if (dict[v] != null) return dict[v];
  return null;
}

async function procesar(fila, opts) {
  const base = { id: fila.id, cadena: fila.cadena, nro: fila.nro_documento };
  if (!fila.storage_path) return { ...base, resultado: "no_importada", aviso: "la OC no tiene PDF guardado" };

  // Guarda de vencidas: una OC cuya fecha de entrega ya pasó no se carga sola —
  // un pedido viejo metido en la PPP mueve stock y confunde la programación.
  const fe = fechaEntregaIso(fila.fecha_entrega);
  if (!opts.force && fe && fe < hoyAr()) {
    return { ...base, resultado: "salteada",
      aviso: "fecha de entrega vencida (" + fila.fecha_entrega + ") — se carga a mano si todavía va" };
  }

  const dl = await sb.storage.from(BUCKET).download(fila.storage_path);
  if (dl.error) return { ...base, resultado: "no_importada", aviso: "no se pudo bajar el PDF: " + dl.error.message };
  const text = await extractPdfText(new Uint8Array(await dl.data.arrayBuffer()));

  const key = detectSuper(text);
  if (!key) return { ...base, resultado: "no_importada", aviso: "no se reconoció la cadena en el PDF" };
  const parser = PARSERS[key];
  if (typeof parser !== "function") {
    return { ...base, super_key: key, resultado: "no_importada", aviso: "todavía no hay parser para " + key };
  }

  const cadenas = await loadCadenas();
  const cad = cadenas[key];
  if (!cad) {
    return { ...base, super_key: key, resultado: "no_importada",
      aviso: "la cadena " + key + " no está configurada en precios_super.cadena" };
  }
  if (cad.empresa === "chef") {
    // El pedido iría al Supabase de Chef (otro proyecto, otras credenciales).
    // Fuera del alcance de esta versión: se avisa y se carga a mano.
    return { ...base, super_key: key, resultado: "no_importada",
      aviso: cad.label + " factura por Chef: todavía se carga a mano desde el panel" };
  }

  const parsed = parser(text);
  const crudos = parsed.items || [];
  if (!crudos.length) {
    return { ...base, super_key: key, resultado: "no_importada",
      aviso: "se reconoció la cadena pero no se pudo leer ningún renglón" };
  }

  if (!cad.cod_cliente_lk) {
    return { ...base, super_key: key, resultado: "no_importada",
      aviso: cad.label + " no tiene cod de cliente LK configurado" };
  }
  const cli = await sb.from("customers").select("*").eq("cod_cliente", cad.cod_cliente_lk).limit(1);
  if (cli.error) return { ...base, super_key: key, resultado: "no_importada", aviso: "customers: " + cli.error.message };
  const customer = cli.data && cli.data[0];
  if (!customer) {
    return { ...base, super_key: key, resultado: "no_importada",
      aviso: "no existe el cliente LK " + cad.cod_cliente_lk + " de " + cad.label };
  }

  await loadProducts();
  const precios = await loadPrecios();

  const ok = [];
  const sinMatch = [];
  for (const it of crudos) {
    const variants = codVariants(it.codLk);
    let p = findInPool(productsCache, variants);
    let isLoke = false;
    if (!p) { p = findInPool(lokeCache, variants); isLoke = !!p; }
    if (!p) { sinMatch.push(it); continue; }
    const codReal = String(p.cod || "").trim();
    let pSuper = superListPrice(precios, key, codReal);
    if (pSuper == null) pSuper = superListPrice(precios, key, it.codLk);
    const listPrice = pSuper != null ? pSuper : Number(p.list_price || 0);
    const uxb = it.uxb || Number(p.uxb || 0);
    ok.push({
      product_id: p.id, cod: codReal, description: p.description, cajas: it.cajas, uxb,
      is_loke: isLoke, unit_list_price: listPrice, unit_your_price: Number(it.unitPrice || 0),
      line_total: Number(it.unitPrice || 0) * (it.cajas || 0) * (uxb || 0),
    });
  }
  if (!ok.length) {
    return { ...base, super_key: key, resultado: "no_importada", items_sin_match: sinMatch.length,
      aviso: "ninguno de los " + crudos.length + " renglones matcheó con el catálogo" };
  }

  const subtotal = ok.reduce((a, x) => a + x.line_total, 0);
  const pdfTotal = extractPdfTotal(text, key);
  const ratio = Number(cad.pdf_ratio) || 1;
  const difTotal = pdfTotal != null && pdfTotal > 0 ? Math.abs(subtotal / ratio - pdfTotal) / pdfTotal : null;

  // "Si el importe NO DA, que lo aclare MUY GRANDE en PPP": el aviso se arma acá
  // y lo muestra la PPP. Dos cosas lo disparan — renglones que no entraron, y el
  // total que no cierra contra el del PDF.
  const motivos = [];
  if (sinMatch.length) {
    motivos.push(sinMatch.length + " de " + crudos.length + " renglones NO entraron (código sin match en el catálogo: " +
      sinMatch.map((x) => x.codLk + " × " + x.cajas + " caj").join(", ") + ")");
  }
  if (difTotal != null && difTotal > TOTAL_TOL) {
    motivos.push("el total no cierra: calculado $ " + (subtotal / ratio).toFixed(2) +
      " vs PDF $ " + pdfTotal.toFixed(2) + " (" + (difTotal * 100).toFixed(1) + "% de diferencia)");
  }
  const parcial = motivos.length > 0;
  const aviso = parcial ? motivos.join(" · ") : ok.length + " renglones, total $ " + subtotal.toFixed(2);

  if (opts.dryRun) {
    return { ...base, super_key: key, resultado: parcial ? "parcial" : "importada", aviso,
      items_ok: ok.length, items_sin_match: sinMatch.length, total_calc: subtotal, total_pdf: pdfTotal };
  }

  // --- dirección de entrega de la sucursal (misma consulta que la card) ---
  let dirEntrega = "";
  let zona = "";
  let etiqueta = "";
  if (parsed.branchId) {
    const da = await sb.from("customer_delivery_addresses")
      .select("slot,label,direccion_entrega,zona_expreso,super_branch_id")
      .eq("customer_id", customer.id).eq("super_branch_id", String(parsed.branchId)).limit(1);
    const row = !da.error && da.data && da.data[0];
    if (row) { dirEntrega = row.direccion_entrega || ""; zona = row.zona_expreso || ""; etiqueta = row.label || ""; }
  }
  const sucursalTxt = (parsed.branchId || "") + (parsed.branchName ? " - " + parsed.branchName : "");
  if (!dirEntrega) dirEntrega = sucursalTxt;

  function outCod(cod) {
    const map = SUPER_COD_MAP[key];
    return map && map[String(cod)] ? map[String(cod)] : String(cod);
  }
  const pago = parsed.paymentTermRaw || "Sin especificar";
  const sheetsPayload = {
    order_number: "", pdf_oc: String(parsed.orderNumber || ""),
    cod_cliente: String(customer.cod_cliente || ""), vend: String(customer.vend || ""),
    condicion_pago: pago, condicion_pago_code: cad.payment_code || 1,
    sucursal_entrega: etiqueta || (sucursalTxt + " [" + cad.label + "]"),
    cliente_nuevo: "", is_promo: false, is_chef: false, target_sheet: "Pedidos Web", empresa: "LK",
    extra_discount: 0, deuda: Number(customer.debt || 0),
    payment_term: customer.payment_term == null ? null : Number(customer.payment_term),
    credit_limit: customer.credit_limit == null ? null : Number(customer.credit_limit),
    due_date: String(parsed.dueDate || ""),
    // La fecha del mail de Krikos manda (es la fuente estructurada), igual que en la card.
    fecha_entrega: String(fila.fecha_entrega || ""), fecha_entrega_origen: "Krikos",
    source: "Krikos",
    items: ok.map((x) => ({ cod_art: outCod(x.cod), cajas: x.cajas, uxb: x.uxb })),
  };

  const res = await sb.rpc("krikos_auto_crear_pedido", {
    p_inbox_id: fila.id, p_customer_id: customer.id, p_payment_method: pago,
    p_subtotal: subtotal, p_total: subtotal,
    p_items: ok.map((x) => ({
      product_id: x.product_id, cajas: x.cajas, uxb: x.uxb, is_loke: x.is_loke,
      unit_list_price: x.unit_list_price, unit_your_price: x.unit_your_price, line_total: x.line_total,
    })),
    p_sheets_payload: sheetsPayload,
    p_auto_estado: parcial ? "parcial" : "ok", p_auto_aviso: aviso,
  });
  if (res.error) {
    return { ...base, super_key: key, resultado: "no_importada", aviso: "no se pudo crear el pedido: " + res.error.message };
  }
  const orderId = res.data;

  // Sheets y entregas: best-effort, igual que en el panel (el pedido ya existe).
  sheetsPayload.order_number = String(orderId);
  const H = { "Content-Type": "application/json", Authorization: "Bearer " + ANON, apikey: ANON };
  try {
    const r = await fetch(SHEETS_PROXY_URL, { method: "POST", headers: H, body: JSON.stringify(sheetsPayload) });
    if (r.ok) await sb.from("orders").update({ sheets_sent: true }).eq("id", orderId);
  } catch (_e) { /* queda sheets_sent=false; lo levanta retry-sheets */ }
  try {
    await fetch(SHEETS_ENTREGAS_URL, { method: "POST", headers: H, body: JSON.stringify({
      order_number: orderId, fecha: hoyAr().split("-").reverse().join("/"),
      cod_cliente: customer.cod_cliente, cliente: customer.business_name, vendedor: customer.vend || "",
      direccion_entrega: dirEntrega, barrio_entrega: zona, fecha_entrega: String(fila.fecha_entrega || ""),
      empresa: "LK", is_promo: false, extra_discount: 0,
      items: ok.map((x) => ({ cod_art: outCod(x.cod), description: x.description || "", cajas: x.cajas, uxb: x.uxb })),
    }) });
  } catch (_e) { /* idem */ }

  return { ...base, super_key: key, resultado: parcial ? "parcial" : "importada", aviso,
    order_id: Number(orderId), items_ok: ok.length, items_sin_match: sinMatch.length,
    total_calc: subtotal, total_pdf: pdfTotal };
}

export async function handler(req) {
  try {
    const secret = await getSecret("KRIKOS_INGEST_SECRET");
    if (!secret) return json({ ok: false, error: "sin KRIKOS_INGEST_SECRET" }, 503);
    if (req.headers.get("x-krikos-secret") !== secret) return json({ ok: false, error: "no autorizado" }, 401);

    const body = await req.json().catch(() => ({}));
    const ids = Array.isArray(body.ids) ? body.ids.map(Number) : [];
    const dryRun = body.dry_run === true;
    const force = body.force === true;
    const limite = Number(body.limit) > 0 ? Number(body.limit) : 10;

    let q = sb.from("krikos_oc_inbox")
      .select("id, cadena, nro_documento, sucursal, fecha_entrega, storage_path, estado, mail_fecha, auto_estado")
      .not("storage_path", "is", null).order("id", { ascending: true }).limit(limite);
    // Sólo lo que está esperando y todavía no tiene pedido: lo ya cargado no se
    // vuelve a tocar NUNCA (además del candado de la RPC, que es el que manda).
    if (ids.length) q = q.in("id", ids);
    else q = q.eq("estado", "pendiente").is("order_id", null);
    const { data: filas, error } = await q;
    if (error) return json({ ok: false, error: error.message }, 500);

    const out = [];
    for (const f of filas || []) {
      try {
        const r = await procesar(f, { dryRun, force });
        out.push(r);
        // El motivo se guarda SIEMPRE, se haya podido cargar o no: es lo que la
        // PPP muestra para que se sepa por qué esa OC sigue esperando.
        if (!dryRun && (r.resultado === "no_importada" || r.resultado === "salteada")) {
          await sb.rpc("krikos_auto_marcar", {
            p_id: f.id, p_auto_estado: r.resultado === "salteada" ? "salteada" : "no", p_auto_aviso: r.aviso,
          });
        }
      } catch (e) {
        const aviso = "error inesperado: " + String((e && e.message) || e);
        out.push({ id: f.id, cadena: f.cadena, nro: f.nro_documento, resultado: "no_importada", aviso });
        if (!dryRun) await sb.rpc("krikos_auto_marcar", { p_id: f.id, p_auto_estado: "no", p_auto_aviso: aviso });
      }
    }
    return json({ ok: true, dry_run: dryRun, revisadas: out.length, docs: out });
  } catch (e) {
    return json({ ok: false, error: String((e && e.message) || e) }, 500);
  }
}
