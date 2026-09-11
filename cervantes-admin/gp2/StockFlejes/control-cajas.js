"use strict";

/* ============================================================
   CONTROL CAJAS · GP2
   ============================================================
   Recepciones de cajas (GP2.recepcion_insumo donde el componente
   es del sector Caja = sector_id 11) pendientes de control fisico.
   La recepcion es rapida (unidades del remito). El control se hace
   despues aca: se cuenta por base x pisos + sueltas.
     total = base * pisos * uni_x_paq + sueltas   (uni_x_paq = 25)
   Al confirmar, llama al RPC GP2.controlar_recepcion_cajas que:
     - guarda base/pisos/sueltas/paquetes/uni_x_paq
     - marca controlado=true + controlado_en + controlado_por
     - pisa la cantidad con el total real
     - ajusta el movimiento asociado (los triggers recalculan inventario)
   ============================================================ */

// URL y clave anon salen de supabase-config.js (un solo lugar; ver ese archivo).
const SB = window.supabase.createClient(self.SB_URL, self.SB_ANON, { db: { schema: "GP2" } });

const $ = (id) => document.getElementById(id);
const listaEl = $("lista");
const statusMsg = $("statusMsg");
const selEstado = $("selEstado");
const selProv = $("selProv");
const ctaCount = $("ctaCount");
const ov = $("ovCtrl");
const inBase = $("inBase"), inPisos = $("inPisos"), inSueltas = $("inSueltas");
const lblPaq = $("lblPaq"), lblUpp = $("lblUpp"), lblTotal = $("lblTotal"), lblDiff = $("lblDiff");
const ctrlTitle = $("ctrlTitle"), ctrlInfo = $("ctrlInfo"), ctrlMsg = $("ctrlMsg");
const btnCancel = $("btnCancel"), btnConfirm = $("btnConfirm"), btnDesmarcar = $("btnDesmarcar");

const esc = (s) => String(s ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
const fmt = (n) => Number(n||0).toLocaleString("es-AR");
const parseInt0 = (v) => { const n = parseInt(String(v||"").replace(/\D/g,""), 10); return isNaN(n) ? 0 : n; };
const UPP_DEFAULT = 25;

let recepciones = [];  // filas del bundle
let selected = null;

function fmtFechaCorta(iso) {
  if (!iso) return "—";
  const m = String(iso).match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? `${Number(m[3])}-${Number(m[2])}` : String(iso);
}

async function cargar() {
  statusMsg.textContent = "Cargando…"; statusMsg.className = "status";
  try {
    // misma RPC que control-remaches.js (control_recepcion_bundle), sector Caja = 11
    const { data, error } = await SB.rpc("control_recepcion_bundle", { p_sector_id: 11 });
    if (error) throw error;
    recepciones = (data && data.recepciones) || [];
    poblarProveedores();
    render();
    statusMsg.textContent = "";
  } catch (err) {
    console.error(err);
    statusMsg.textContent = "Error: " + (err.message || err);
    statusMsg.className = "status bad";
  }
}

function poblarProveedores() {
  const provs = new Set(recepciones.map(r => String(r.proveedor || "").trim()).filter(Boolean));
  const cur = selProv.value;
  selProv.innerHTML = '<option value="todos">Todos</option>' +
    [...provs].sort().map(p => `<option value="${esc(p)}">${esc(p)}</option>`).join("");
  if (cur && [...selProv.options].some(o => o.value === cur)) selProv.value = cur;
}

function filtrar() {
  const estado = selEstado.value;
  const prov = selProv.value;
  return recepciones.filter(r => {
    if (estado === "pendientes" && r.controlado) return false;
    if (estado === "controladas" && !r.controlado) return false;
    if (prov !== "todos" && String(r.proveedor || "").trim() !== prov) return false;
    return true;
  });
}

function agrupar(rows) {
  // Agrupar por REMITO (regla usuario 2026-09-02: "aparece por día, quiero que
  // aparezca por remito"). Con remito real la key NO lleva fecha, asi cada remito
  // es un grupo aunque cruce dias. Solo las recepciones viejas sin remito ("SR")
  // caen al fallback por fecha para no juntar cargas de dias distintos.
  const map = new Map();
  for (const r of rows) {
    const rem = r.remito ? String(r.remito) : "SR";
    const fecha = String(r.fecha || "").slice(0, 10);
    const key = rem === "SR" ? `SR||${fecha}||${r.proveedor||""}` : `${r.proveedor||""}||${rem}`;
    if (!map.has(key)) map.set(key, { fecha, proveedor: r.proveedor, remito: r.remito, items: [] });
    map.get(key).items.push(r);
  }
  return [...map.values()].sort((a, b) => String(b.fecha).localeCompare(String(a.fecha)));
}

function render() {
  const rows = filtrar();
  const total = rows.length;
  const controladas = rows.filter(r => r.controlado).length;
  const pend = total - controladas;
  ctaCount.textContent = pend > 0 ? `${pend} pendiente(s) · ${controladas} OK` : (total ? `${controladas} controladas` : "sin recepciones");
  ctaCount.classList.toggle("done", pend === 0 && total > 0);

  const grupos = agrupar(rows);
  if (!grupos.length) {
    const est = selEstado.value;
    const txt = est === "pendientes" ? "No hay cajas pendientes de control." :
                est === "controladas" ? "No hay cajas controladas todavía." :
                "No hay recepciones de cajas.";
    listaEl.innerHTML = `<div class="empty">${txt}</div>`;
    return;
  }

  let html = "";
  for (const g of grupos) {
    const totG = g.items.length;
    const okG = g.items.filter(x => x.controlado).length;
    const pendG = totG - okG;
    const badgeCls = pendG === 0 ? "rem-badge done" : "rem-badge";
    const badgeTxt = pendG === 0 ? `${okG}/${totG} OK` : `${pendG} pendiente(s)`;
    html += `<div class="rem-block">
      <div class="rem-hdr">
        <div>
          <div class="rem-title">${esc(g.proveedor || "—")} · Remito ${esc(g.remito || "—")}</div>
          <div class="rem-meta">${esc(fmtFechaCorta(g.fecha))} · ${totG} caja(s)</div>
        </div>
        <div class="${badgeCls}">${badgeTxt}</div>
      </div>
      <div class="items-grid">`;
    for (const it of g.items) {
      const cls = it.controlado ? "item-btn done" : "item-btn";
      const decl = Number(it.cantidad_declarada != null ? it.cantidad_declarada : it.cantidad) || 0;
      let ctrlLine = "";
      if (it.controlado) {
        const real = Number(it.cantidad) || 0;
        const dif = real - decl;
        const b = Number(it.base) || 0, p = Number(it.pisos) || 0, s = Number(it.sueltas) || 0;
        const paq = Number(it.paquetes) || (b * p);
        const desglose = (b && p) ? `${b}×${p} = ${paq} paq` : (paq ? `${paq} paq` : "");
        const sTxt = s ? ` + ${s} sueltas` : "";
        ctrlLine = `<div class="ctrl">Real: ${fmt(real)} uni<small>${esc(desglose)}${esc(sTxt)}</small></div>`;
        ctrlLine += (dif === 0)
          ? `<div class="diff ok">coincide ✓</div>`
          : `<div class="diff dif">${dif > 0 ? "+" : ""}${fmt(dif)} vs declarado</div>`;
      }
      html += `<div class="${cls}" data-id="${it.id}">
        <span class="tilde">✓</span>
        <span class="cod">${esc(it.codigo || "—")}</span>
        <span class="desc">${esc(it.descripcion || "")}</span>
        <span class="decl">Declarado: <b>${fmt(decl)}</b> uni</span>
        ${ctrlLine}
      </div>`;
    }
    html += `</div></div>`;
  }
  listaEl.innerHTML = html;

  listaEl.querySelectorAll(".item-btn").forEach(el => {
    el.addEventListener("click", () => {
      const id = Number(el.dataset.id);
      const it = recepciones.find(x => x.id === id);
      if (it) abrirPopup(it);
    });
  });
}

function calc() {
  const b = parseInt0(inBase.value);
  const p = parseInt0(inPisos.value);
  const s = parseInt0(inSueltas.value);
  const upp = UPP_DEFAULT;
  const paq = b * p;
  const total = paq * upp + s;
  lblPaq.textContent = fmt(paq);
  lblUpp.textContent = fmt(upp);
  lblTotal.textContent = `Total: ${fmt(total)} cajas`;
  if (selected) {
    const decl = Number(selected.cantidad_declarada != null ? selected.cantidad_declarada : selected.cantidad) || 0;
    if (total > 0 && decl > 0) {
      const dif = total - decl;
      lblDiff.style.display = "block";
      if (dif === 0) {
        lblDiff.className = "diff-line ok";
        lblDiff.textContent = `Coincide con lo declarado (${fmt(decl)} uni) ✓`;
      } else {
        lblDiff.className = "diff-line bad";
        const s2 = dif > 0 ? "sobran" : "faltan";
        lblDiff.textContent = `Declarado ${fmt(decl)} · ${s2} ${fmt(Math.abs(dif))} cajas`;
      }
    } else {
      lblDiff.style.display = "none";
    }
  }
  btnConfirm.disabled = !(total > 0);
  return { b, p, s, paq, upp, total };
}

function abrirPopup(it) {
  selected = it;
  ctrlMsg.textContent = ""; ctrlMsg.className = "msg";
  const decl = Number(it.cantidad_declarada != null ? it.cantidad_declarada : it.cantidad) || 0;
  ctrlTitle.textContent = it.controlado
    ? `Revisar control — ${it.codigo || ""}`
    : `Control — ${it.codigo || ""}`;
  ctrlInfo.innerHTML = `
    <b>${esc(it.codigo || "")}</b>${it.descripcion ? " — " + esc(it.descripcion) : ""}
    <br>Proveedor: ${esc(it.proveedor || "—")} · Remito ${esc(it.remito || "—")} · ${esc(fmtFechaCorta(it.fecha))}
    <br>Declarado por proveedor: <b>${fmt(decl)}</b> unidades
  `;
  inBase.value    = it.controlado ? String(it.base    || "") : "";
  inPisos.value   = it.controlado ? String(it.pisos   || "") : "";
  inSueltas.value = it.controlado ? String(it.sueltas || "") : "";
  btnDesmarcar.style.display = it.controlado ? "" : "none";
  calc();
  ov.classList.add("open");
  setTimeout(() => inBase.focus(), 60);
}

function cerrarPopup() { ov.classList.remove("open"); selected = null; }

async function confirmar() {
  if (!selected) return;
  const { b, p, s, upp, total } = calc();
  if (total <= 0) { ctrlMsg.textContent = "Ingresá al menos base×pisos o sueltas."; ctrlMsg.className = "msg bad"; return; }

  const decl = Number(selected.cantidad_declarada != null ? selected.cantidad_declarada : selected.cantidad) || 0;
  if (decl > 0) {
    const dif = total - decl;
    const pct = Math.abs(dif) / decl;
    if (pct > 0.10) {
      const txt = dif > 0 ? `sobran ${fmt(dif)}` : `faltan ${fmt(-dif)}`;
      if (!confirm(`Difiere ±${(pct*100).toFixed(1)}% de lo declarado.\nDeclarado: ${fmt(decl)} · Contado: ${fmt(total)} (${txt}).\n¿Confirmar de todos modos?`)) return;
    }
  }

  const usuario = (sessionStorage.getItem("gp_user") || sessionStorage.getItem("gp_role") || "").toString().slice(0, 80);
  btnConfirm.disabled = true;
  ctrlMsg.textContent = "Guardando…"; ctrlMsg.className = "msg";
  try {
    const { data, error } = await SB.rpc("controlar_recepcion_cajas", {
      p_recepcion_id: selected.id,
      p_base: b, p_pisos: p, p_sueltas: s,
      p_uni_x_paq: upp, p_usuario: usuario || null
    });
    if (error) throw error;
    ctrlMsg.textContent = "OK ✓ · Total " + fmt((data && data.total) || total) + " uni"; ctrlMsg.className = "msg ok";
    setTimeout(async () => { cerrarPopup(); await cargar(); }, 350);
  } catch (err) {
    console.error(err);
    ctrlMsg.textContent = "Error: " + (err.message || err); ctrlMsg.className = "msg bad";
    btnConfirm.disabled = false;
  }
}

async function desmarcar() {
  if (!selected || !selected.controlado) return;
  if (!confirm("¿Desmarcar el control? La cantidad vuelve al valor declarado y se borra el desglose.")) return;
  btnDesmarcar.disabled = true;
  ctrlMsg.textContent = "Deshaciendo…"; ctrlMsg.className = "msg";
  try {
    // Por RPC (2026-09-05): anon no puede escribir tablas GP2 directo desde el 2026-08-31,
    // asi que el UPDATE que habia aca fallaba con "permission denied". La RPC vuelve la
    // cantidad al declarado, borra el desglose y ajusta el movimiento (el trigger recalcula
    // el inventario).
    const { error } = await SB.rpc("descontrolar_recepcion", { p_recepcion_id: selected.id });
    if (error) throw error;
    ctrlMsg.textContent = "Desmarcado ✓"; ctrlMsg.className = "msg ok";
    setTimeout(async () => { cerrarPopup(); await cargar(); }, 300);
  } catch (err) {
    console.error(err);
    ctrlMsg.textContent = "Error: " + (err.message || err); ctrlMsg.className = "msg bad";
    btnDesmarcar.disabled = false;
  }
}

/* ===== Listeners ===== */
[inBase, inPisos, inSueltas].forEach(el => {
  el.addEventListener("input", () => { el.value = el.value.replace(/\D/g, ""); calc(); });
  el.addEventListener("keydown", e => { if (e.key === "Enter") btnConfirm.click(); });
});
btnCancel.addEventListener("click", cerrarPopup);
btnConfirm.addEventListener("click", confirmar);
btnDesmarcar.addEventListener("click", desmarcar);
// NO cerrar al tocar afuera: se sale solo con Cancelar (pedido del usuario,
// evita perder lo tipeado por un toque accidental en el fondo).
selEstado.addEventListener("change", cargar);
selProv.addEventListener("change", render);

/* ===== Init ===== */
cargar();
