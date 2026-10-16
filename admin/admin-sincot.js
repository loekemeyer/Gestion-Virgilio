// =====================================================================
// PEDIDOS SIN COTIZADOR (v2, Luis 16/10/2026) — data-page="pedidos-sin-cot"
// Carga manual de un pedido por el admin, paso a paso, sin poder mandar
// un dato erroneo: cliente valido -> sucursal REGISTRADA -> (Retira: dia
// habil + franja) -> condicion de pago -> articulos de a un renglon (solo
// cajas) -> revision -> envio.
// Mismo pipeline que el checkout: submit_order_fast + sheets-proxy +
// entregas-proxy. Condicion de pago FIJA «Sin Cotizador» (codigo 1): la
// define la forma de carga, no se elige (Luis, 16/10/2026).
// COTIZA IGUAL QUE LA PPP de Gestion Virgilio (gv_ppp_web_valor_items), con
// los datos de Gestion leidos por FDW (RPC admin_cotiza_cliente):
//   precio unit = lista del super del cliente -> lista LK -> lista Chef
//   por caja    = precio unit x uxb (de Gestion) x (1 - dto_vol de Gestion)
//   sin dto web ni dto por pago: «Sin Cotizador» no los lleva (factor 1).
// ⚠ Este archivo es IGUAL en pagina-LK-copia y paginach salvo SC_CFG.
// =====================================================================
var SC_CFG = {
  empresa: "LK",
  isChef: false,
  targetSheet: "Pedidos Web",
  // La ficha viaja dentro de la RPC (misma transaccion que el pedido).
  fichaEnRpc: true,
  // Marca quien cargo el pedido (columna orders.placed_by_auth_user_id).
  placedBy: true,
  // Condicion de pago fija de este modulo.
  pago: { code: 1, text: "Sin Cotizador" },
  // Clientes que compran por UNIDAD (articulos con uxb = 1). Ver pedido 1450.
  clientesUnidades: ["4263"],
  // Codigos de reenvase (active=false) que solo se ofrecen aca. Hoy vacio.
  codsExtra: [],
};
// ---- fin de SC_CFG ----

var SC_FRANJAS = ["9:00 a 12:00", "13:00 a 16:30"];
var SC_RETIRO_HABILES = 3;
// cod_cliente que no son clientes: 1 y 5000 (lista), >= 10000 (vendedores).
function scClienteValido(c) {
  var n = Number(c && c.cod_cliente);
  return !!n && n !== 1 && n !== 5000 && n < 10000;
}

var sc = {
  wired: false,
  catalogo: [],
  bloqueados: {}, // product_id -> "SIN STOCK" | "PROXIMAMENTE"
  feriados: {},
  // Cotizacion de Gestion del cliente elegido: { dto_vol, super_key, listas: {lista: {cod: {precio_unit, uxb}}} }
  cotiza: null,
  customer: null,
  addrs: [],
  addrIdx: -1,
  retiroFecha: "",
  retiroFranja: "",
  lines: [], // { p: product, cajas: int }
  pick: null, // producto elegido en el renglon de carga
  obs: "",
  review: false,
  submitting: false,
  lastOrder: null,
};

function scEsc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
function scMoney(n) {
  return (
    "$ " +
    Number(n || 0).toLocaleString("es-AR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  );
}
function scPct(r) {
  return (
    (Number(r || 0) * 100).toLocaleString("es-AR", { maximumFractionDigits: 2 }) + " %"
  );
}
function scIso(d) {
  var p = function (n) {
    return String(n).padStart(2, "0");
  };
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}
function scDdMm(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
  return m ? m[3] + "/" + m[2] : iso;
}
function scEsHabil(d) {
  return d.getDay() !== 0 && d.getDay() !== 6 && !sc.feriados[scIso(d)];
}
function scRetiroMin() {
  var r = new Date();
  r = new Date(r.getFullYear(), r.getMonth(), r.getDate());
  var k = 0;
  while (k < SC_RETIRO_HABILES) {
    r.setDate(r.getDate() + 1);
    if (scEsHabil(r)) k++;
  }
  return scIso(r);
}
function scRetiroFechaError(iso) {
  if (!iso) return "Elegí el día de retiro.";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return "Fecha inválida.";
  if (iso < scRetiroMin())
    return "Retira desde " + scDdMm(scRetiroMin()) + " (3 días hábiles).";
  var d = new Date(iso + "T12:00:00");
  if (d.getDay() === 0 || d.getDay() === 6) return "Sábado y domingo no se retira.";
  if (sc.feriados[iso]) return "Es feriado: elegí otro día.";
  return "";
}

function scEsUnidades() {
  return (
    !!sc.customer &&
    SC_CFG.clientesUnidades.indexOf(String(sc.customer.cod_cliente)) >= 0
  );
}
function scUnidad(plural) {
  return scEsUnidades() ? (plural ? "Unidades" : "Unidad") : plural ? "Cajas" : "Caja";
}
function scAddr() {
  return sc.addrIdx >= 0 ? sc.addrs[sc.addrIdx] || null : null;
}
function scEsRetira() {
  var a = scAddr();
  return !!a && String(a.zona_expreso || "").trim().toLowerCase() === "retira";
}
function scDtoVol() {
  var v = Number((sc.cotiza && sc.cotiza.dto_vol) || 0);
  return v > 0 && v < 1 ? v : 0;
}
// norm_cod de Gestion: mayusculas, sin espacios ni ceros a la izquierda.
function scNormCod(c) {
  return String(c || "").trim().toUpperCase().replace(/^0+(?=.)/, "");
}
// Precio de Gestion para un articulo, mismo orden que gv_ppp_web_valor_items:
// lista del super -> lista LK (en Chef solo codigos con L) -> lista Chef (solo Chef).
function scPrecio(p) {
  var L = (sc.cotiza && sc.cotiza.listas) || {};
  var cod = scNormCod(p.cod);
  var esL = /^[0-9]+E?L$/.test(cod);
  var codPrecio = SC_CFG.empresa === "CH" && esL ? cod.replace(/L$/, "") : cod;
  var sk = sc.cotiza && sc.cotiza.super_key;
  var propia = SC_CFG.empresa === "CH" && !esL ? "chef" : "lk";
  if (sk && L[sk] && L[sk][cod]) {
    var s = L[sk][cod];
    if (s.uxb) return s;
    // Precio de super sin UxB propia: la de su empresa (gv_uxb_de), si no 1. Igual que la PPP.
    var u = L[propia] && L[propia][codPrecio];
    return { precio_unit: s.precio_unit, uxb: (u && u.uxb) || 1 };
  }
  if ((SC_CFG.empresa !== "CH" || esL) && L.lk && L.lk[codPrecio]) return L.lk[codPrecio];
  if (SC_CFG.empresa === "CH" && L.chef && L.chef[codPrecio]) return L.chef[codPrecio];
  return null;
}
function scPrecioListaCaja(p) {
  var x = scPrecio(p);
  return x ? Number(x.precio_unit) * Number(x.uxb) : 0;
}
function scPrecioCaja(p) {
  return scPrecioListaCaja(p) * (1 - scDtoVol());
}
function scTotales() {
  var r2 = function (n) {
    return Math.round(n * 100) / 100;
  };
  var lista = 0;
  sc.lines.forEach(function (l) {
    lista += scPrecioListaCaja(l.p) * l.cajas;
  });
  lista = r2(lista);
  var total = r2(lista * (1 - scDtoVol()));
  return {
    sub: lista,
    vol: r2(lista - total),
    total: total,
    cajas: sc.lines.reduce(function (a, l) {
      return a + l.cajas;
    }, 0),
  };
}
// Bloqueo de un articulo: sin stock / proximamente, o caja cerrada para un
// cliente que compra por unidad.
function scMotivoBloqueo(p) {
  if (sc.bloqueados[p.id]) return sc.bloqueados[p.id];
  if (!(Number(p.uxb) > 0)) return "sin UxB";
  var x = scPrecio(p);
  if (!x || !(Number(x.precio_unit) > 0)) return "sin precio en lista";
  if (scEsUnidades() && Number(p.uxb) !== 1) return "caja cerrada";
  return "";
}

// Lo que falta para poder enviar, en orden.
function scFaltantes() {
  var f = [];
  if (!sc.customer) {
    f.push("Elegí el cliente");
    return f;
  }
  if (sc.customer._bloqueo) {
    f.push(sc.customer._bloqueo);
    return f;
  }
  var a = scAddr();
  if (!sc.addrs.length) f.push("El cliente no tiene sucursales registradas");
  else if (!a) f.push("Elegí la sucursal de entrega");
  else if (!String(a.zona_expreso || "").trim())
    f.push("La sucursal no tiene zona cargada");
  if (scEsRetira()) {
    var e = scRetiroFechaError(sc.retiroFecha);
    if (e) f.push(e);
    if (SC_FRANJAS.indexOf(sc.retiroFranja) < 0) f.push("Elegí la franja de retiro");
  }
  if (!sc.lines.length) f.push("Agregá al menos un artículo");
  return f;
}

// ---------------------------------------------------------------------
// Carga de datos
// ---------------------------------------------------------------------
async function scLoadBase() {
  if (!cpAllProducts || !cpAllProducts.length) {
    try {
      await cpLoadProducts();
    } catch (e) {
      console.error("sc productos:", e);
      toast("No se pudieron cargar los artículos", "error");
    }
  }
  var cat = (cpAllProducts || []).slice();
  if (SC_CFG.codsExtra.length) {
    try {
      var rx = await sb
        .from("products")
        .select("id,cod,description,category,list_price,uxb,active,ranking")
        .in("cod", SC_CFG.codsExtra);
      if (!rx.error && rx.data) {
        var ids = {};
        cat.forEach(function (p) {
          ids[p.id] = 1;
        });
        rx.data.forEach(function (p) {
          if (!ids[p.id]) cat.push(p);
        });
      }
    } catch (e) {
      console.warn("sc extra:", e);
    }
  }
  sc.catalogo = cat;
  // Sin stock / proximamente: el guard del backend NO aplica al admin, asi
  // que se frena aca.
  try {
    var rb = await sb.from("products").select("id,badge_status").eq("active", true);
    if (!rb.error) {
      sc.bloqueados = {};
      (rb.data || []).forEach(function (r) {
        var b = String(r.badge_status || "").trim().toUpperCase();
        if (b === "SIN STOCK") sc.bloqueados[r.id] = "SIN STOCK";
        else if (b === "PROXIMAMENTE" || b === "PRÓXIMAMENTE")
          sc.bloqueados[r.id] = "PRÓXIMAMENTE";
      });
    }
  } catch (e) {
    console.warn("sc badge:", e);
  }
  try {
    var rf = await sb.from("feriados").select("fecha");
    if (!rf.error) {
      sc.feriados = {};
      (rf.data || []).forEach(function (r) {
        sc.feriados[String(r.fecha).slice(0, 10)] = 1;
      });
    }
  } catch (e) {
    console.warn("sc feriados:", e);
  }
}

// Columnas del cliente: escalera (si una columna no existe en este proyecto,
// PostgREST da 400 y se reintenta con menos).
var SC_CUST_COLS = [
  "id,cod_cliente,business_name,dto_vol,vend,payment_term,localidad,escala_activa,modo_presupuesto",
  "id,cod_cliente,business_name,dto_vol,vend,payment_term,escala_activa,modo_presupuesto",
  "id,cod_cliente,business_name,dto_vol,vend,payment_term",
];
async function scQueryCustomers(build) {
  var last = null;
  for (var i = 0; i < SC_CUST_COLS.length; i++) {
    var r = await build(sb.from("customers").select(SC_CUST_COLS[i]));
    if (!r.error) return r.data || [];
    last = r.error;
  }
  throw new Error((last && last.message) || "customers");
}
var SC_ADDR_COLS = [
  "slot,label,direccion_entrega,zona_expreso,localidad,provincia,nombre_expreso",
  "slot,label,direccion_entrega,zona_expreso",
];
async function scLoadAddrs(customerId) {
  for (var i = 0; i < SC_ADDR_COLS.length; i++) {
    var r = await sb
      .from("customer_delivery_addresses")
      .select(SC_ADDR_COLS[i])
      .eq("customer_id", customerId)
      .order("slot", { ascending: true });
    if (!r.error) return r.data || [];
    if (i === SC_ADDR_COLS.length - 1) throw new Error(r.error.message);
  }
  return [];
}

// Cotizacion de Gestion Virgilio (RPC admin_cotiza_cliente, lee por FDW).
async function scLoadCotiza(cod) {
  var r = await sb.rpc("admin_cotiza_cliente", { p_cod_cliente: String(cod) });
  if (r.error) throw new Error(r.error.message);
  var d = r.data || {};
  var listas = {};
  (d.precios || []).forEach(function (x) {
    var l = (listas[x.lista] = listas[x.lista] || {});
    // uxb null = el super no tiene UxB propia (se resuelve en scPrecio).
    l[scNormCod(x.cod)] = { precio_unit: Number(x.precio_unit), uxb: x.uxb == null ? null : Number(x.uxb) || 1 };
  });
  if (!Object.keys(listas).length) throw new Error("Gestión no devolvió listas de precios");
  return { dto_vol: Number(d.dto_vol) || 0, super_key: d.super_key || null, listas: listas };
}

// ---------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------
// Redibujar una tarjeta sin perder el foco del campo donde estaba el operador.
function scKeepFocus(fn) {
  var id = document.activeElement && document.activeElement.id;
  fn();
  var n = id && document.getElementById(id);
  if (n) n.focus();
}
// Lleva el foco al primer dato que falta (para cargar todo sin mouse).
function scFocoSiguiente() {
  ["scAddrSel", "scRetFecha", "scRetFranja", "scArtInput"].some(function (id) {
    var e = document.getElementById(id);
    if (e && !e.disabled && !e.value) {
      e.focus();
      return true;
    }
    return false;
  });
}

function scRoot() {
  return document.getElementById("scRoot");
}

function scRenderAll() {
  var root = scRoot();
  if (!root) return;
  root.innerHTML =
    '<div class="sc-form">' +
    '<div class="sc-card" id="scStepCliente"></div>' +
    '<div class="sc-card" id="scStepEntrega"></div>' +
    '<div class="sc-card" id="scStepPago"></div>' +
    '<div class="sc-card" id="scStepArts"></div>' +
    '<div class="sc-card" id="scStepObs"></div>' +
    "</div>" +
    '<aside class="sc-side" id="scSide"></aside>' +
    '<div class="sc-review" id="scReview" hidden></div>';
  scRenderCliente();
  scRenderEntrega();
  scRenderPago();
  scRenderArts();
  scRenderObs();
  scRenderSide();
}

function scStepHead(n, title, ok) {
  return (
    '<div class="sc-step-head"><span class="sc-step-n' +
    (ok ? " ok" : "") +
    '">' +
    (ok ? "✓" : n) +
    "</span><h3>" +
    title +
    "</h3></div>"
  );
}

function scRenderCliente() {
  var el = document.getElementById("scStepCliente");
  if (!el) return;
  var c = sc.customer;
  if (!c) {
    el.innerHTML =
      scStepHead(1, "Cliente", false) +
      '<div class="sc-combo">' +
      '<input type="text" id="scCustInput" class="field-input" placeholder="Código o razón social" autocomplete="off" />' +
      '<div class="sc-dd" id="scCustDD" hidden></div>' +
      "</div>";
    scWireCombo(
      document.getElementById("scCustInput"),
      document.getElementById("scCustDD"),
      scBuscarClientes,
      scElegirCliente,
    );
    return;
  }
  var meta = [];
  if (sc.cotiza && sc.cotiza.super_key) meta.push("Lista " + scEsc(sc.cotiza.super_key.toUpperCase()));
  meta.push("Dto vol " + scPct(scDtoVol()));
  if (c.vend) meta.push("Vend " + scEsc(c.vend));
  if (c.payment_term != null && c.payment_term !== "") meta.push("Plazo " + scEsc(c.payment_term) + " d");
  if (c.localidad) meta.push(scEsc(c.localidad));
  if (scEsUnidades()) meta.push("<b>Compra por UNIDAD</b>");
  el.innerHTML =
    scStepHead(1, "Cliente", !c._bloqueo) +
    '<div class="sc-chosen">' +
    '<div><div class="sc-chosen-main">' +
    scEsc(c.cod_cliente) +
    " · " +
    scEsc(c.business_name) +
    '</div><div class="sc-chosen-meta">' +
    meta.join(" · ") +
    "</div></div>" +
    '<button type="button" class="sc-link" id="scCustChange">Cambiar</button>' +
    "</div>" +
    (c._bloqueo ? '<div class="sc-msg err">' + scEsc(c._bloqueo) + "</div>" : "");
  document.getElementById("scCustChange").addEventListener("click", function () {
    if (sc.lines.length && !confirm("Cambiar de cliente borra los artículos cargados. ¿Seguís?")) return;
    scReset();
  });
}

function scRenderEntrega() {
  var el = document.getElementById("scStepEntrega");
  if (!el) return;
  var c = sc.customer;
  if (!c || c._bloqueo) {
    el.innerHTML = scStepHead(2, "Entrega", false) + '<div class="sc-hint">Primero elegí el cliente.</div>';
    el.classList.add("sc-off");
    return;
  }
  el.classList.remove("sc-off");
  if (!sc.addrs.length) {
    el.innerHTML =
      scStepHead(2, "Entrega", false) +
      '<div class="sc-msg err">Este cliente no tiene sucursales registradas. Cargala en la ficha del cliente y volvé a elegirlo.</div>';
    return;
  }
  var a = scAddr();
  var opts =
    (sc.addrs.length > 1 ? '<option value="">— Elegí la sucursal —</option>' : "") +
    sc.addrs
      .map(function (x, i) {
        var lbl = x.label || x.direccion_entrega || "Sucursal " + (x.slot != null ? x.slot : i + 1);
        return (
          '<option value="' + i + '"' + (i === sc.addrIdx ? " selected" : "") + ">" + scEsc(lbl) + "</option>"
        );
      })
      .join("");
  var info = "";
  if (a) {
    var partes = [a.direccion_entrega, a.localidad, a.provincia].filter(Boolean).map(scEsc);
    var zona = String(a.zona_expreso || "").trim();
    info =
      '<div class="sc-addr-info">' +
      (partes.length ? partes.join(" · ") : '<span class="sc-hint">Sin dirección</span>') +
      (zona
        ? ' <span class="sc-tag">' + scEsc(zona) + "</span>"
        : ' <span class="sc-tag err">sin zona</span>') +
      (a.nombre_expreso ? ' <span class="sc-tag">Expreso ' + scEsc(a.nombre_expreso) + "</span>" : "") +
      "</div>" +
      (zona ? "" : '<div class="sc-msg err">La sucursal no tiene zona: cargala en la ficha del cliente antes de pedir.</div>');
  }
  var retira = "";
  if (scEsRetira()) {
    var err = sc.retiroFecha ? scRetiroFechaError(sc.retiroFecha) : "";
    retira =
      '<div class="sc-retira">' +
      '<label class="sc-lbl">Día de retiro<input type="date" id="scRetFecha" class="field-input" min="' +
      scRetiroMin() +
      '" value="' +
      scEsc(sc.retiroFecha) +
      '" /></label>' +
      '<label class="sc-lbl">Franja<select id="scRetFranja" class="field-input">' +
      '<option value="">— Elegí —</option>' +
      SC_FRANJAS.map(function (f) {
        return '<option value="' + f + '"' + (sc.retiroFranja === f ? " selected" : "") + ">" + f + "</option>";
      }).join("") +
      "</select></label>" +
      '<div class="sc-hint">Desde ' +
      scDdMm(scRetiroMin()) +
      ", lunes a viernes, sin feriados.</div>" +
      (err ? '<div class="sc-msg err">' + scEsc(err) + "</div>" : "") +
      "</div>";
  }
  var ok = !!a && !!String(a.zona_expreso || "").trim() &&
    (!scEsRetira() || (!scRetiroFechaError(sc.retiroFecha) && SC_FRANJAS.indexOf(sc.retiroFranja) >= 0));
  el.innerHTML =
    scStepHead(2, "Entrega", ok) +
    '<label class="sc-lbl">Sucursal<select id="scAddrSel" class="field-input">' +
    opts +
    "</select></label>" +
    info +
    retira;
  document.getElementById("scAddrSel").addEventListener("change", function () {
    sc.addrIdx = this.value === "" ? -1 : Number(this.value);
    sc.retiroFecha = "";
    sc.retiroFranja = "";
    scKeepFocus(function () {
      scRenderEntrega();
      scRenderSide();
    });
  });
  var f = document.getElementById("scRetFecha");
  if (f)
    f.addEventListener("change", function () {
      sc.retiroFecha = this.value;
      scKeepFocus(function () {
        scRenderEntrega();
        scRenderSide();
      });
    });
  var fr = document.getElementById("scRetFranja");
  if (fr)
    fr.addEventListener("change", function () {
      sc.retiroFranja = this.value;
      scKeepFocus(function () {
        scRenderEntrega();
        scRenderSide();
      });
    });
}

function scRenderPago() {
  var el = document.getElementById("scStepPago");
  if (!el) return;
  var off = !sc.customer || sc.customer._bloqueo;
  el.classList.toggle("sc-off", !!off);
  el.innerHTML =
    scStepHead(3, "Condición de pago", !off) +
    '<div class="sc-fija"><b>' + scEsc(SC_CFG.pago.text) + "</b> " +
    '<span class="sc-hint">Fija para los pedidos cargados acá: sin dto web ni dto por pago.</span></div>';
}

function scRenderArts() {
  var el = document.getElementById("scStepArts");
  if (!el) return;
  var off = !sc.customer || sc.customer._bloqueo;
  el.classList.toggle("sc-off", !!off);
  var unidad = scUnidad(true);
  var p = sc.pick;
  var pickInfo = p
    ? '<span class="sc-pick-info">UxB <b>' +
      scEsc(p.uxb) +
      "</b>" +
      scUxbAviso(p) +
      " · " +
      scMoney(scPrecioCaja(p)) +
      " x " +
      scUnidad(false).toLowerCase() +
      "</span>"
    : '<span class="sc-pick-info"></span>';
  var rows = sc.lines
    .map(function (l, i) {
      return (
        '<tr data-i="' + i + '">' +
        "<td>" + scEsc(l.p.cod) + "</td>" +
        '<td class="sc-desc">' + scEsc(l.p.description || "") + "</td>" +
        "<td>" + scEsc(l.p.uxb) + scUxbAviso(l.p) + "</td>" +
        '<td><input type="text" class="sc-qty" inputmode="numeric" pattern="[0-9]*" maxlength="5" value="' + l.cajas + '" aria-label="' + unidad + '" /></td>' +
        "<td>" + scMoney(scPrecioCaja(l.p)) + "</td>" +
        "<td>" + scMoney(scPrecioCaja(l.p) * l.cajas) + "</td>" +
        '<td><button type="button" class="sc-x" title="Quitar">✕</button></td>' +
        "</tr>"
      );
    })
    .join("");
  el.innerHTML =
    scStepHead(4, "Artículos", sc.lines.length > 0) +
    '<div class="sc-entry">' +
    '<div class="sc-combo sc-entry-art"><input type="text" id="scArtInput" class="field-input" placeholder="Código o descripción" autocomplete="off"' +
    (off ? " disabled" : "") +
    ' value="' + (p ? scEsc(p.cod + " · " + (p.description || "")) : "") + '" /><div class="sc-dd" id="scArtDD" hidden></div></div>' +
    pickInfo +
    '<input type="text" id="scArtQty" class="field-input sc-entry-qty" inputmode="numeric" pattern="[0-9]*" maxlength="5" placeholder="' + unidad + '"' +
    (off || !p ? " disabled" : "") +
    " />" +
    '<button type="button" class="btn-primary" id="scArtAdd"' + (off || !p ? " disabled" : "") + ">Agregar</button>" +
    "</div>" +
    (sc.lines.length
      ? '<div class="sc-table-wrap"><table class="sc-table"><thead><tr><th>Cód</th><th>Artículo</th><th>UxB</th><th>' +
        unidad +
        "</th><th>$ x " +
        scUnidad(false).toLowerCase() +
        "</th><th>Subtotal</th><th></th></tr></thead><tbody>" +
        rows +
        "</tbody></table></div>"
      : '<div class="sc-hint">Todavía no hay artículos.</div>');
  if (off) return;
  var inp = document.getElementById("scArtInput");
  scWireCombo(inp, document.getElementById("scArtDD"), scBuscarArts, function (prod) {
    sc.pick = prod;
    scRenderArts();
    var q = document.getElementById("scArtQty");
    if (q) q.focus();
  });
  inp.addEventListener("input", function () {
    if (sc.pick) {
      sc.pick = null;
      var q = document.getElementById("scArtQty");
      var b = document.getElementById("scArtAdd");
      if (q) q.disabled = true;
      if (b) b.disabled = true;
      var info = el.querySelector(".sc-pick-info");
      if (info) {
        info.textContent = "";
      }
    }
  });
  var qty = document.getElementById("scArtQty");
  var add = document.getElementById("scArtAdd");
  if (qty)
    qty.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        e.preventDefault();
        scAgregar();
      }
    });
  if (add) add.addEventListener("click", scAgregar);
  el.querySelectorAll("tr[data-i]").forEach(function (tr) {
    var i = Number(tr.dataset.i);
    tr.querySelector(".sc-qty").addEventListener("change", function () {
      var v = this.value.trim();
      if (!/^\d+$/.test(v) || Number(v) < 1) {
        toast("Las " + unidad.toLowerCase() + " son un número entero desde 1", "warning");
        this.value = sc.lines[i].cajas;
        return;
      }
      sc.lines[i].cajas = Number(v);
      scRenderArts();
      scRenderSide();
      var nx =
        document.querySelector('tr[data-i="' + (i + 1) + '"] .sc-qty') ||
        document.getElementById("scArtInput");
      if (nx) nx.focus();
    });
    tr.querySelector(".sc-x").addEventListener("click", function () {
      sc.lines.splice(i, 1);
      scRenderArts();
      scRenderSide();
    });
  });
}

// La PPP cotiza con la UxB de Gestion; si no coincide con la del catalogo web, se avisa.
function scUxbAviso(p) {
  var x = scPrecio(p);
  return x && Number(x.uxb) !== Number(p.uxb)
    ? ' <span class="sc-tag err" title="Gestión cotiza con ' + scEsc(x.uxb) + ' u/caja">UxB Gestión ' + scEsc(x.uxb) + "</span>"
    : "";
}

function scAgregar() {
  var p = sc.pick;
  var q = document.getElementById("scArtQty");
  var unidad = scUnidad(true).toLowerCase();
  if (!p) return;
  var v = String((q && q.value) || "").trim();
  if (!/^\d+$/.test(v) || Number(v) < 1) {
    toast("Ingresá las " + unidad + ": número entero desde 1", "warning");
    if (q) q.focus();
    return;
  }
  var n = Number(v);
  var ya = sc.lines.filter(function (l) {
    return l.p.id === p.id;
  })[0];
  if (ya) {
    // No se suma solo: una doble carga por error (3 + 3) no puede quedar en 6.
    toast(p.cod + " ya está cargado: corregí la cantidad en su renglón", "warning");
    sc.pick = null;
    scRenderArts();
    var fila = document.querySelector('tr[data-i="' + sc.lines.indexOf(ya) + '"] .sc-qty');
    if (fila) {
      fila.focus();
      fila.select();
    }
    return;
  }
  sc.lines.push({ p: p, cajas: n });
  sc.pick = null;
  scRenderArts();
  scRenderSide();
  var inp = document.getElementById("scArtInput");
  if (inp) inp.focus();
}

function scRenderObs() {
  var el = document.getElementById("scStepObs");
  if (!el) return;
  var off = !sc.customer || sc.customer._bloqueo;
  el.classList.toggle("sc-off", !!off);
  el.innerHTML =
    scStepHead(5, "Observaciones <small>(opcional)</small>", false) +
    '<div class="sc-obs">' +
    '<label class="sc-lbl sc-obs-txt">Observaciones<textarea id="scObs" class="field-input" rows="2" maxlength="500"' + (off ? " disabled" : "") + ">" + scEsc(sc.obs) + "</textarea></label>" +
    "</div>";
  document.getElementById("scObs").addEventListener("input", function () {
    sc.obs = this.value;
  });
}

function scRenderSide() {
  var el = document.getElementById("scSide");
  if (!el) return;
  var t = scTotales();
  var falta = scFaltantes();
  el.innerHTML =
    '<div class="sc-card sc-sum">' +
    "<h3>Resumen</h3>" +
    '<div class="sc-sum-row"><span>' + scEsc(scUnidad(true)) + "</span><b>" + t.cajas.toLocaleString("es-AR") + "</b></div>" +
    '<div class="sc-sum-row"><span>Subtotal lista</span><b>' + scMoney(t.sub) + "</b></div>" +
    '<div class="sc-sum-row"><span>Dto vol ' + scPct(scDtoVol()) + "</span><b>− " + scMoney(t.vol) + "</b></div>" +
    '<div class="sc-sum-row sc-sum-total"><span>Total</span><b>' + scMoney(t.total) + "</b></div>" +
    (falta.length
      ? '<ul class="sc-falta">' + falta.map(function (x) { return "<li>" + scEsc(x) + "</li>"; }).join("") + "</ul>"
      : '<div class="sc-msg ok">Listo para revisar.</div>') +
    '<button type="button" class="btn-primary sc-go" id="scGo"' + (falta.length || sc.submitting ? " disabled" : "") + ">Revisar pedido</button>" +
    (sc.lastOrder ? '<div class="sc-hint">Último enviado: pedido ' + scEsc(sc.lastOrder) + "</div>" : "") +
    "</div>";
  document.getElementById("scGo").addEventListener("click", scAbrirRevision);
}

function scAbrirRevision() {
  if (scFaltantes().length) return;
  var el = document.getElementById("scReview");
  var c = sc.customer;
  var a = scAddr();
  var t = scTotales();
  var unidad = scUnidad(true);
  el.innerHTML =
    '<div class="sc-review-box" role="dialog" aria-modal="true">' +
    "<h3>Revisá el pedido</h3>" +
    '<dl class="sc-rev-dl">' +
    "<dt>Cliente</dt><dd>" + scEsc(c.cod_cliente + " · " + c.business_name) + "</dd>" +
    "<dt>Sucursal</dt><dd>" + scEsc(a.label || a.direccion_entrega || "") + " <span class=\"sc-tag\">" + scEsc(a.zona_expreso) + "</span></dd>" +
    (scEsRetira() ? "<dt>Retira</dt><dd>" + scDdMm(sc.retiroFecha) + " · " + scEsc(sc.retiroFranja) + "</dd>" : "") +
    "<dt>Pago</dt><dd>" + scEsc(SC_CFG.pago.text) + "</dd>" +
    (sc.obs.trim() ? "<dt>Obs.</dt><dd>" + scEsc(sc.obs.trim()) + "</dd>" : "") +
    "</dl>" +
    '<table class="sc-table"><thead><tr><th>Cód</th><th>Artículo</th><th>UxB</th><th>' + unidad + "</th><th>Subtotal</th></tr></thead><tbody>" +
    sc.lines
      .map(function (l) {
        return "<tr><td>" + scEsc(l.p.cod) + '</td><td class="sc-desc">' + scEsc(l.p.description || "") + "</td><td>" + scEsc(l.p.uxb) + "</td><td><b>" + l.cajas + "</b></td><td>" + scMoney(scPrecioCaja(l.p) * l.cajas) + "</td></tr>";
      })
      .join("") +
    "</tbody></table>" +
    '<div class="sc-rev-total">' + t.cajas.toLocaleString("es-AR") + " " + unidad.toLowerCase() + " · Total <b>" + scMoney(t.total) + "</b></div>" +
    '<div class="sc-rev-actions"><button type="button" class="btn-ghost" id="scRevBack">Volver a editar</button>' +
    '<button type="button" class="btn-primary" id="scRevSend">Confirmar y enviar</button></div>' +
    "</div>";
  el.hidden = false;
  scInert(true);
  el.onkeydown = function (e) {
    if (e.key === "Escape" && !sc.submitting) scCerrarRevision();
  };
  document.getElementById("scRevBack").addEventListener("click", scCerrarRevision);
  document.getElementById("scRevSend").addEventListener("click", scEnviar);
  // El foco arranca en "Volver": dos Enter seguidos no envian el pedido.
  document.getElementById("scRevBack").focus();
}
function scInert(on) {
  var root = scRoot();
  var form = root && root.querySelector(".sc-form");
  var side = document.getElementById("scSide");
  if (form) form.inert = on;
  if (side) side.inert = on;
}
function scCerrarRevision() {
  var el = document.getElementById("scReview");
  if (el) el.hidden = true;
  scInert(false);
  var go = document.getElementById("scGo");
  if (go) go.focus();
}

// ---------------------------------------------------------------------
// Combo (input + lista desplegable con teclado)
// ---------------------------------------------------------------------
function scWireCombo(input, dd, buscar, elegir) {
  if (!input || !dd) return;
  var items = [];
  var act = -1;
  var seq = 0;
  var timer = null;
  function pintar() {
    if (!items || !items.length) {
      var msg =
        items === null
          ? "Escribí 2 letras o el código"
          : !sc.catalogo.length && input.id === "scArtInput"
            ? "Cargando artículos…"
            : "Sin resultados";
      dd.innerHTML = '<div class="sc-dd-empty">' + msg + "</div>";
      dd.hidden = false;
      return;
    }
    dd.innerHTML = items
      .map(function (it, i) {
        return (
          '<div class="sc-dd-row' + (i === act ? " act" : "") + (it.disabled ? " dis" : "") + '" data-i="' + i + '">' +
          it.html +
          "</div>"
        );
      })
      .join("");
    dd.hidden = false;
  }
  function cerrar() {
    dd.hidden = true;
    act = -1;
  }
  function tomar(i) {
    var it = items && items[i];
    if (!it) return;
    if (it.disabled) {
      toast(it.why || "No se puede elegir", "warning");
      return;
    }
    cerrar();
    elegir(it.value);
  }
  input.addEventListener("input", function () {
    clearTimeout(timer);
    var q = input.value.trim();
    if (q.length < 1) {
      cerrar();
      return;
    }
    timer = setTimeout(async function () {
      var my = ++seq;
      var res = await buscar(q);
      if (my !== seq) return;
      items = res === null ? null : res || [];
      act = items
        ? items.findIndex(function (x) {
            return !x.disabled;
          })
        : -1;
      pintar();
    }, 160);
  });
  input.addEventListener("keydown", function (e) {
    if (dd.hidden || !items || !items.length) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      var d = e.key === "ArrowDown" ? 1 : -1;
      act = (act + d + items.length) % items.length;
      pintar();
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (act >= 0) tomar(act);
    } else if (e.key === "Tab" && !e.shiftKey && act >= 0) {
      e.preventDefault();
      tomar(act);
    } else if (e.key === "Escape") {
      cerrar();
    }
  });
  dd.addEventListener("pointerdown", function (e) {
    var row = e.target.closest(".sc-dd-row");
    if (!row) return;
    e.preventDefault();
    tomar(Number(row.dataset.i));
  });
  input.addEventListener("blur", function () {
    setTimeout(cerrar, 120);
  });
}

async function scBuscarClientes(q) {
  var isNum = /^\d+$/.test(q);
  if (!isNum && q.length < 2) return null;
  try {
    var porNombre = scQueryCustomers(function (b) {
      return b.ilike("business_name", "%" + q + "%").order("business_name", { ascending: true }).limit(15);
    });
    var porCod = isNum
      ? scQueryCustomers(function (b) {
          return b.eq("cod_cliente", q).limit(3);
        })
      : Promise.resolve([]);
    var r = await Promise.all([porCod, porNombre]);
    var seen = {};
    var out = [];
    r[0].concat(r[1]).forEach(function (c) {
      if (seen[c.id] || !scClienteValido(c)) return;
      seen[c.id] = 1;
      out.push({
        value: c,
        html: "<b>" + scEsc(c.cod_cliente) + "</b> " + scEsc(c.business_name) + (c.localidad ? ' <span class="sc-hint">' + scEsc(c.localidad) + "</span>" : ""),
      });
    });
    return out.slice(0, 10);
  } catch (e) {
    console.error("sc clientes:", e);
    toast("No se pudo buscar clientes: " + (e.message || e), "error");
    return [];
  }
}

function scNorm(s) {
  return String(s || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");
}
function scBuscarArts(q) {
  var nq = scNorm(q).trim();
  var cq = nq.replace(/\s+/g, "");
  var words = nq.split(/\s+/).filter(Boolean);
  var res = [];
  sc.catalogo.forEach(function (p) {
    var cod = scNorm(p.cod);
    var desc = scNorm(p.description);
    var score = -1;
    if (cod === cq) score = 0;
    else if (cod.indexOf(cq) === 0) score = 1;
    else if (words.every(function (w) { return desc.indexOf(w) >= 0 || cod.indexOf(w) >= 0; })) score = 2;
    if (score < 0) return;
    res.push({ p: p, s: score });
  });
  res.sort(function (a, b) {
    return a.s - b.s || String(a.p.cod).localeCompare(String(b.p.cod), undefined, { numeric: true });
  });
  return res.slice(0, 12).map(function (r) {
    var p = r.p;
    var why = scMotivoBloqueo(p);
    return {
      value: p,
      disabled: !!why,
      why: p.cod + ": " + why,
      html:
        '<b class="sc-dd-cod">' + scEsc(p.cod) + "</b> " + scEsc(p.description || "") +
        ' <span class="sc-dd-uxb">UxB ' + scEsc(p.uxb) + "</span>" +
        (why ? ' <span class="sc-tag err">' + scEsc(why) + "</span>" : ""),
    };
  });
}

async function scElegirCliente(c) {
  sc.customer = c;
  c._bloqueo = "";
  if (c.modo_presupuesto)
    c._bloqueo = "Cliente en modo presupuesto: se carga desde la web como presupuesto, no acá.";
  else if (c.escala_activa)
    c._bloqueo = "Cliente con escala de descuentos: cargalo desde la web para que tome su escala.";
  sc.addrs = [];
  sc.addrIdx = -1;
  sc.retiroFecha = "";
  sc.retiroFranja = "";
  sc.lines = [];
  sc.pick = null;
  if (!c._bloqueo) {
    try {
      sc.addrs = await scLoadAddrs(c.id);
    } catch (e) {
      console.error("sc sucursales:", e);
      c._bloqueo = "No se pudieron leer las sucursales del cliente. Probá de nuevo.";
    }
    if (sc.addrs.length === 1) sc.addrIdx = 0;
  }
  sc.cotiza = null;
  if (!c._bloqueo) {
    try {
      sc.cotiza = await scLoadCotiza(c.cod_cliente);
    } catch (e) {
      console.error("sc cotizacion:", e);
      c._bloqueo = "No se pudo traer la cotización de Gestión (" + (e.message || e) + "). Probá de nuevo.";
    }
  }
  scRenderAll();
  scFocoSiguiente();
}

function scReset() {
  sc.customer = null;
  sc.addrs = [];
  sc.addrIdx = -1;
  sc.retiroFecha = "";
  sc.retiroFranja = "";
  sc.lines = [];
  sc.pick = null;
  sc.obs = "";
  scRenderAll();
  var i = document.getElementById("scCustInput");
  if (i) i.focus();
}

// ---------------------------------------------------------------------
// Envio
// ---------------------------------------------------------------------
async function scEnviar() {
  if (sc.submitting) return;
  var falta = scFaltantes();
  if (falta.length) {
    toast(falta[0], "warning");
    return;
  }
  var btn = document.getElementById("scRevSend");
  sc.submitting = true;
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Enviando...";
  }
  var c = sc.customer;
  var a = scAddr();
  var pago = SC_CFG.pago;
  var t = scTotales();
  var inicio = new Date(Date.now() - 60000).toISOString();
  var token = null;
  var orderId = null;
  try {
    var ses = await sb.auth.getSession();
    if (ses.error || !ses.data || !ses.data.session) throw new Error("Sesión expirada. Recargá la página.");
    var session = ses.data.session;
    token = session.access_token;

    var items = sc.lines.map(function (l) {
      return {
        product_id: l.p.id,
        cod_art: String(l.p.cod || "").trim(),
        description: String(l.p.description || ""),
        cajas: l.cajas,
        uxb: Number(l.p.uxb),
      };
    });
    var retiroTxt = scEsRetira() ? ("RETIRA " + scDdMm(sc.retiroFecha) + " " + sc.retiroFranja).trim() : "";
    var observaciones = [retiroTxt, sc.obs.trim()].filter(Boolean).join(" — ");
    var sucursal = a.label || String(a.slot || "");
    var ficha = {
      cod_cliente: String(c.cod_cliente || "").trim(),
      vend: String(c.vend || "").trim(),
      condicion_pago: pago.text,
      condicion_pago_code: pago.code,
      sucursal_entrega: sucursal,
      cliente_nuevo: "",
      observaciones: observaciones,
      retiro_fecha: scEsRetira() ? sc.retiroFecha : null,
      retiro_franja: scEsRetira() ? sc.retiroFranja : null,
      is_promo: false,
      is_chef: SC_CFG.isChef,
      tipo_documento: "pedido",
      target_sheet: SC_CFG.targetSheet,
      empresa: SC_CFG.empresa,
      extra_discount: 0,
      deuda: null,
      credit_limit: null,
      payment_term: c.payment_term == null || c.payment_term === "" ? null : Number(c.payment_term),
      lc: null,
      d: null,
      pp: null,
      order_total: t.total,
      source: "Sin Cotizador",
      mode: "new",
      items: items.map(function (it) {
        return { cod_art: it.cod_art, cod_original: null, cajas: it.cajas, uxb: it.uxb };
      }),
    };
    var args = {
      p_auth_user_id: session.user.id,
      p_customer_id: c.id,
      p_status: "pendiente",
      p_payment_method: pago.text,
      p_payment_discount: 0,
      p_web_discount: 0,
      p_subtotal: t.sub,
      p_total: t.total,
      p_items: items.map(function (it) {
        return { product_id: it.product_id, cajas: it.cajas, uxb: it.uxb, is_loke: false, source: "sin_cotizador" };
      }),
    };
    if (SC_CFG.fichaEnRpc) args.p_sheets_payload = ficha;
    var rpc = await cpWithTimeout(sb.rpc("submit_order_fast", args), 20000, "submit_order_fast");
    if (rpc.error || !rpc.data) throw new Error((rpc.error && (rpc.error.message || rpc.error.details)) || "No se creó el pedido");
    orderId = rpc.data;
    ficha.order_number = String(orderId);

    var upd = { is_promo: false, extra_discount: 0 };
    if (!SC_CFG.fichaEnRpc) upd.sheets_payload = ficha;
    if (SC_CFG.placedBy) upd.placed_by_auth_user_id = session.user.id;
    var ru = await sb.from("orders").update(upd).eq("id", orderId);
    if (ru.error) {
      console.error("sc update orden " + orderId + ":", ru.error);
      if (!SC_CFG.fichaEnRpc)
        toast("Pedido " + orderId + " creado pero SIN ficha: avisá a sistemas (" + ru.error.message + ")", "error");
    }
  } catch (e) {
    console.error("sc enviar:", e);
    // Timeout: la RPC puede haber terminado igual. Se busca antes de dejar reintentar.
    if (!orderId && /timeout/i.test(String(e.message || e))) {
      try {
        var rr = await sb
          .from("orders")
          .select("id")
          .eq("customer_id", c.id)
          .gte("created_at", inicio)
          .order("id", { ascending: false })
          .limit(1);
        if (!rr.error && rr.data && rr.data.length) orderId = rr.data[0].id;
      } catch (e2) {
        console.warn("sc verificar timeout:", e2);
      }
    }
    if (!orderId) {
      toast("No se pudo enviar: " + (e.message || e), "error");
      sc.submitting = false;
      if (btn) {
        btn.disabled = false;
        btn.textContent = "Confirmar y enviar";
      }
      return;
    }
    toast("La red tardó, pero el pedido " + orderId + " entró. No lo vuelvas a cargar.", "warning");
  }

  // Sheet y Base Picking: no frenan el pedido (la ficha ya esta en la base).
  if (token) {
    var fichaSheet = Object.assign({}, ficha, { order_number: String(orderId) });
    cpSendToSheetsWithRetry(fichaSheet, token, 3)
      .then(function () {
        sb.from("orders").update({ sheets_sent: true }).eq("id", orderId).then(function () {});
      })
      .catch(function (err) {
        console.warn("sc sheets (pedido " + orderId + "):", err);
      });
    cpSendToEntregas(
      {
        order_number: orderId,
        fecha: new Date().toLocaleDateString("es-AR"),
        cod_cliente: c.cod_cliente,
        cliente: c.business_name,
        vendedor: c.vend || "",
        direccion_entrega: a.direccion_entrega || sucursal,
        barrio_entrega: a.zona_expreso || "",
        empresa: SC_CFG.empresa,
        is_promo: false,
        extra_discount: 0,
        items: items.map(function (it) {
          return { cod_art: it.cod_art, description: it.description, cajas: it.cajas, uxb: it.uxb };
        }),
      },
      token,
    );
  }
  toast("Pedido " + orderId + " enviado", "success");
  sc.lastOrder = orderId;
  sc.submitting = false;
  var rv = document.getElementById("scReview");
  if (rv) rv.hidden = true;
  scInert(false);
  scReset();
}

// Entrada desde la navegacion del admin (admin.js llama a cargarPedidosSinCot).
async function cargarPedidosSinCot() {
  if (!sc.wired) {
    sc.wired = true;
    scRenderAll();
    await scLoadBase();
  }
  scRenderAll();
}
window.cargarPedidosSinCot = cargarPedidosSinCot;
