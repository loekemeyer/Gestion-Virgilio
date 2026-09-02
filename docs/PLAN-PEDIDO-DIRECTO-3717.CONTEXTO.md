# Contexto verificado — idea 3717 (anexo del plan)

> Hechos relevados el 2026-09-02 (sólo lectura) sobre los repos y las dos bases Supabase, antes de redactar `PLAN-PEDIDO-DIRECTO-3717.md`. Es el punto de partida del plan; si algo de acá cambia, el plan hay que releerlo.


## Repos locales
- Virgilio: /home/user/Produccion-Virgilio (index.html 36k líneas, GUIA-PROYECTO.md 8.5k líneas, sql/, docs/)
- LK:       /home/user/pagina-LK-copia (script.js, admin.js, sql/, docs/, supabase/functions/ solo tiene admin-otp y crear-cliente-auth)
- Supabase Virgilio: hrxfctzncixxqmpfhskv · Supabase LK: kwkclwhmoygunqmlegrg (MCP execute_sql disponible)

## Flujo ACTUAL verificado (LK → ISIS → Virgilio)
1. Pedido entra a `orders` (LK) por `submit_order_fast` (web cliente / admin "Pedir para" / cotizador) y el front guarda `orders.sheets_payload` (jsonb) con: order_number, cod_cliente, vend, condicion_pago (texto), condicion_pago_code, sucursal_entrega (label), cliente_nuevo, observaciones, is_promo, extra_discount, deuda, credit_limit, payment_term, lc, d, pp, order_total, source ('Web'|'Cotizador'), mode ('new'|'edit'), items[{cod_art, cod_original, cajas, uxb}].
   Además el front manda un `entregasPayload` a la Edge Fn `sheets-entregas-proxy` (Sheet "Base Picking") con: order_number, fecha, cod_cliente, cliente (razón social), vendedor, direccion_entrega, barrio_entrega (zonaExpreso), empresa 'LK', items[{cod_art, description, cajas, uxb}].
2. Cron LK `procesar-pedidos-web` = `30 15 * * *` UTC (12:30 ART) → `enviar_pedidos_main()` → `postear_envio_pedidos('main',0)` → net.http_post a la Edge Fn **`procesar-pedidos-db`** (fuente en ./procesar-pedidos-db.ts). Retry: cron `retry-procesar-pedidos` `2-59/6 15,16 * * *` (hasta 10 intentos, sólo si no hubo ok ese día). Log en `procesar_pedidos_log` (hoy 02/09: orders_count=221 líneas → pedidos_generated=16 NP, mail a ventas@loekemeyer.com, asunto "Pedidos Web Lk de 02-09-26").
3. La Edge Fn lee `orders` con `enviado_a_compras_at IS NULL AND sheets_payload NOT NULL`, arma filas por ítem, aplica **processOrders**: los pedidos con ≥18 líneas se parten en grupos de ≤18 (clave N°Pedido|Sucursal), los <18 quedan enteros; **N_Pedido es un correlativo interno del archivo (1..N), NO es la NP de ISIS**. Genera Excel XML 2003 (`Pedidos_Descargado_DD-MM-YY_9Hs.xls`) con hoja 1 = 12 columnas: fecha (dd/MM/yyyy), N_Pedido, cliente (cod), vend, articulo (padStart 3 dígitos + letras), cajas, uni (cajas×uxb), sucursal, leyenda2 ("D x - LC x - PP x"), condPago (CÓDIGO), pctDto ("2% Descuento Web" fijo), numOC; hoja 2 "Resumen" (Pedidos, NP, desglose Cod Clte/Num Ped/Cant Items). Manda por Gmail API y recién si el mail dio 200 sella `enviado_a_compras_at`.
4. La operadora importa ese Excel en ISIS → ISIS asigna la NP real (LK 9xxxx, Chef 4xxxx) → baja 2 reportes → Excel PPP (Google Sheet 1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0: gid 1947169223 "PPP Excel Programacion Diaria", gid 845301421 "PPP Excel Base Datos Pedidos") → Apps Script `handleCargaPPPSync_` / `sync-ppp-supabase.gs` (fuera del repo) empuja a Supabase Virgilio `PPP_Programacion_Diaria` (reemplazo total) y `PPP_Base_Pedidos`. ⚠ `sync_ppp_base_pedidos()`/`sync_ppp_programacion_diaria()` (sql/sync_ppp_pull_server_side.sql) **NO existen en la base** (no hay función ni cron): el pull server-side nunca se desplegó; el push del Apps Script sigue siendo el camino vivo. Único cron PPP vivo: `sync-ppp-entregados-meta` (7,37 * * * *) → `PPP_Entregados_Meta`.
5. Virgilio: PPP (programar tanda/op/fecha_entrega — VERIFICAR si se programa en el Excel o en la app), picking (EP/TP) + armado (AP/TAP/TAL) leen `PPP_Base_Pedidos` por NP; `Entregas_Virgilio` (np, cod_art, cajas_pedidas, cajas_entregadas, cajas_falto, tanda, fecha_salida) se escribe al armar; Facturación (`openFacturacion`/`facRender`/`facTickNP`) inserta `Facturacion_NP` (trigger `validar_np_armada`); la factura se hace A MANO en ISIS.

## Esquemas (Virgilio)
- PPP_Programacion_Diaria: id, np text, tanda, tipo (WEB|KRIKOS|COT|''), fecha_recep, cod, razon_social, m3 numeric, v (cod vendedor), direccion, barrio, op ('SI'|''), fecha_entrega, fecha_fc, zona, observaciones. Hoy 183 filas / 183 NP (44588..98684). Triggers: fn_norm_ppp_prog (np), fn_norm_tanda, ppp_autozona (zona desde barrio), trg_ppp_zona_canonica. RLS: select anon/auth; write sólo 3 mails supervisores (`ppp_prog_write_sup`); `lk_ppp_reader` select.
- PPP_Base_Pedidos: id, pedido text (NP), articulo, cajas numeric, cliente (razón social), fecha. Hoy 9398 filas / 801 NP (ventana ~2 meses por fecha de carga, definida aguas arriba). Triggers: fn_norm_ppp_base_pedidos, trg_corregir_secundario_auto, trg_pedido_secundario_telegram. RLS igual que prog. Máximo de líneas por NP = 19 (98293, 98501: 18 distintos + 1 artículo repetido). NP 98682/98683 (cod 989) y 98680/98681 (cod 1936) son el mismo pedido web partido en 2 NP.
- Facturacion_NP: np, tanda, fecha_salida, m3, razon_social, cod_cliente, facturado_at, cierre_id. Triggers: validar_np_armada (BEFORE INSERT), trg_facturado_notif_wa, wa_np_facturado_trg, trg_revertir_drenaje_facturado (DELETE). RLS: anon insert/update/delete/select abiertos.
- Entregas_Virgilio: id, fecha_salida, cod_cliente, np, cod_art, cajas_pedidas, cajas_entregadas, cajas_falto, tanda, creado. Triggers: canon cod_art, dedup, reconciliar stock, fn_virgilio_entrega_to_formato (→ LK pa/osa entregas).
- NP_Canceladas: np, motivo, legajo, creado.
- PPP_Entregados_Meta: np, cod, rs, updated_at, tanda, m3, fecha_entrega (espejo del Sheet "PPP Pedidos Entregados" cada 30 min).
- lk_pedidos_match (2026-08-28): empresa ('lk'|'chef'), order_id, cod_cliente, status, fecha_pedido, hora_pedido, created_at, sucursal_entrega, metodo_pago, items_string, match_string, ambiguo, orden_en_dia, synced_at. PK (empresa, order_id). 1070 filas. LA ESCRIBE LK cada 15 min por FDW (server `virgilio_db`, rol `lk_ppp_reader`, único permiso de escritura de ese rol), función `sync_pedidos_match_virgilio()` (ventana móvil 14 días delete+insert). Virgilio sólo lee. Todavía NO se muestra en la app (pendiente definir dónde).

## Esquemas (LK)
- orders: id, created_at, auth_user_id, customer_id, status, payment_method, payment_discount, web_discount, subtotal, total, sheets_sent, sheets_payload jsonb, is_promo, extra_discount, enviado_a_compras_at, placed_by_auth_user_id, customer_code.
- order_items: id, order_id, product_id, cajas, uxb, unit_list_price, unit_your_price, line_total, created_at, loke_product_id, is_loke, source.
- Pedidos con más ítems: 120 (id 759), 93, 82, 74... → se parten de a 18.
- Otras entradas de pedidos en LK: bot_submit_order (WhatsApp), milver_submit_order (comisionista), pedidos_ingest (expo chef/tierra → expo_pedidos_externos), edit_order_fast (edición; sheets_payload.mode='edit').
- RPC `get_order_m3(p_order_id)` existe; Edge Fn `sync-product-m3`. LK tiene `sincronizar_ppp()` (cron 10:00 UTC) que TIRA el PPP de Virgilio a tablas `ppp_*` locales.
- Crons LK relevantes: procesar-pedidos-web 30 15 * * *; retry-procesar-pedidos 2-59/6 15,16; sync-pedidos-match-virgilio */15; sincronizar-ppp-diario 0 10; detectar-pedidos-anomalos */5; retry-sheets-cron */5.

## Ideas relacionadas ya registradas
- 5547 (pendiente): Integración ISIS 5 circuitos JSON (P1 facturación automática, P2 JSON faltantes, P3 NP de ISIS → Virgilio, P4 recepción, P5 completado). docs/PLAN-INTEGRACION-ISIS-5547.md, docs/integracion-isis.md, docs/ISIS-Tkt1159666-InformeConsolidado.pdf.
- 4529/9949 (hechas): string identificador de pedido web → lk_pedidos_match (sucursal de entrega).
- 1655 (pendiente): ventana de PPP_Base_Pedidos corta para clientes que piden con 85-90 días.
- 8606 (pendiente): picking siempre con variante/marca correcta (809→809E).

## Extracto fiel de la Edge Function LK `procesar-pedidos-db` (v9)

```ts
// EDGE FUNCTION LK: procesar-pedidos-db (v9) — extracto fiel de la lógica de pedidos/Excel (resto = Gmail/log)
function padCodArt(cod){ const s=String(cod).trim(); const digits=s.match(/\d+/)?.[0]||""; const letters=s.match(/[a-zA-Z]+/)?.[0]||""; return digits.padStart(3,"0")+letters; }
function normalizeDate(val){ if(/^\d{2}\/\d{2}\/\d{4}$/.test(val)) return val; const m=val.match(/^(\d{4})-(\d{2})-(\d{2})/); if(m) return `${m[3]}/${m[2]}/${m[1]}`; return val; }
interface Item { N_Pedido:number; row_number:number; fecha:string; cliente:string; vend:string; articulo:string; cajas:string; uni:string; sucursal:string; leyenda2:string; condPago:string; pctDto:string; numOC:string; }
function toItem(r, nPedido){ return { N_Pedido:nPedido, row_number:0, fecha:normalizeDate(String(r["Fecha Pedido"]||"")), cliente:String(r["Cliente"]||""), vend:String(r["Vend"]||""), articulo:padCodArt(r["Cod Art"]), cajas:String(r["Cajas"]||""), uni:String(r["Uni Pedidas"]||""), sucursal:String(r["Sucursal de Entrega"]||""), leyenda2:String(r["Leyenda 2"]||""), condPago:String(r["Condición de Pago"]||""), pctDto:"2% Descuento Web", numOC:String(r["Numero OC"]||"") }; }
function processOrders(raw){
  const gk = r => `${r["N° Pedido"]}|${r["Sucursal de Entrega"]}|${r["Cliente"]}`;
  const counts = new Map(); for (const r of raw) counts.set(gk(r), (counts.get(gk(r))||0)+1);
  const enriched = raw.map(r => ({...r, _count:counts.get(gk(r)), _ped:String(r["N° Pedido"]), _suc:String(r["Sucursal de Entrega"])}));
  const big = enriched.filter(e => e._count >= 18);
  const small = enriched.filter(e => e._count < 18);
  const out = []; let globalN=0, lastPed=null, lastSuc=null, grpCount=0;
  for (const it of big) { if (it._ped!==lastPed || it._suc!==lastSuc || grpCount>=18) { globalN++; grpCount=0; lastPed=it._ped; lastSuc=it._suc; } grpCount++; out.push(toItem(it, globalN)); }
  const base=globalN; const pedMap=new Map(); let cnt=0;
  for (const it of small) { const key=`${it._ped}|${it._suc}|${it["Cliente"]}`; if(!pedMap.has(key)){ cnt++; pedMap.set(key, base+cnt); } out.push(toItem(it, pedMap.get(key))); }
  return out;
}
// generateExcel: XML Spreadsheet 2003. Hoja 1 (nombre "DD-MM-YY 9Hs"): columnas en este orden
//   ["fecha","N_Pedido","cliente","vend","articulo","cajas","uni","sucursal","leyenda2","condPago","pctDto","numOC"]  (sin fila de encabezado)
// Hoja 2 "Resumen": Pedidos | NP ; luego "Desglose": Cod Clte | Num Ped | Cant Items (una fila por cliente|N_Pedido)
// Archivo: Pedidos_Descargado_${dateStr}_9Hs.xls ; asunto "Pedidos Web ${COMPANY} de ${dateStr}" ; cuerpo "Excel Adjunto"
function rowsFromOrders(orders){
  const raw=[]; for (const o of orders){ const p=o.sheets_payload||{}; const items=Array.isArray(p.items)?p.items:[];
    const codCliente=pick(p,"cod_cliente","codCliente")??""; const vend=pick(p,"vend")??""; const condCode=pick(p,"condicion_pago_code","condicionPagoCode")??"";
    const sucursal=pick(p,"sucursal_entrega","sucursalEntrega")??""; const numOC=pick(p,"numOC","numero_oc","numeroOC")??""; const {d,lc,pp}=statusFields(p);
    for (const it of items) raw.push({ "N° Pedido":String(o.id), "Fecha Pedido":fechaPedido(o.created_at), "Cliente":String(codCliente), "Vend":String(vend), "Cod Art":it.cod_art, "Cajas":String(it.cajas??""), "Uni Pedidas":String((Number(it.cajas)||0)*(Number(it.uxb)||0)), "Sucursal de Entrega":String(sucursal), "Condición de Pago":String(condCode), "Leyenda 2":`D ${d} - LC ${lc} - PP ${pp}`, "Numero OC":String(numOC) }); }
  return raw; }
// statusFields: si el payload trae d/lc/pp los usa; si no: lc = (credit_limit!=null && deuda+order_total>credit_limit)?"X":"OK"; d = deuda>0?"X":"OK"; pp = payment_term==null?"Null":String(Number(payment_term))
// handler: pend = orders?enviado_a_compras_at=is.null&sheets_payload=not.is.null&order=id.asc ; si raw vacío → mail "no hubo nuevos pedidos" + log no_orders ;
//          si no → processOrders → generateExcel → sendEmail → markEnviado(orderIds, now) (sólo si el mail dio 200) → logRun ok. Modo {dry:true} devuelve el Excel base64 sin mandar ni marcar.
```
