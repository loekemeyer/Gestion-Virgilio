/*
 * MÓDULO: Conteo de Planillas Cajas
 * Integración en Virgilio para operarios y operadora
 */

(function () {
  const APP_SCRIPT_URL =
    "https://script.google.com/macros/s/AKfycbwdWP__nIbto7po9xOmSToAsb6PIyiqbxDZ1etmpejKrE7gwnz4asVEcVsmgumzHiE4/exec";

  const MAP = window.PLANIMETRIA_MAP || {};
  const $ = (id) => document.getElementById(id);

  function normalizeCode(v) {
    return String(v ?? "")
      .trim()
      .toUpperCase()
      .replace(/\s+/g, "");
  }
  function onlyDigits(v) {
    return String(v ?? "").replace(/[^\d]/g, "");
  }

  function showOverlay(on, title = "Enviando…", sub = "Guardando en Google Sheet") {
    const ov = $("pcmOverlay");
    if (!ov) return;
    const t = $("pcmOverlayTitle");
    const s = $("pcmOverlaySub");
    if (t) t.textContent = title;
    if (s) s.textContent = sub;
    ov.style.display = on ? "flex" : "none";
  }

  function switchTab(n) {
    const tab1 = $("pcmTab1");
    const tab2 = $("pcmTab2");
    const tab3 = $("pcmTab3");
    if (tab1) tab1.style.display = n === 1 ? "" : "none";
    if (tab2) tab2.style.display = n === 2 ? "" : "none";
    if (tab3) tab3.style.display = n === 3 ? "" : "none";
  }

  function setStatus() {
    const leg = onlyDigits($("pcmLegajo").value).slice(0, 3);
    const c1 = normalizeCode($("pcmCod1").value).slice(0, 4);
    const c2 = normalizeCode($("pcmCod2").value).slice(0, 4);
    const cnt = [c1, c2].filter(Boolean).length;
    const pill = $("pcmStatusPill");
    if (pill) pill.textContent = leg ? `Legajo ${leg} · ${cnt} código(s)` : "Sin datos";
  }

  const STATE = { legajo: "", codes: [], rows: [], fills: {}, resumen: {} };

  function rowKey(r) {
    return `${r.orden}|${r.sector}|${r.codArt}`;
  }

  function buildSelect(min, max, selectedValue) {
    const sel = document.createElement("select");
    const opt0 = document.createElement("option");
    opt0.value = "";
    opt0.textContent = "—";
    sel.appendChild(opt0);

    for (let i = min; i <= max; i++) {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = String(i);
      if (String(i) === String(selectedValue)) opt.selected = true;
      sel.appendChild(opt);
    }
    return sel;
  }

  function calcTotal(pilas, cxp, sueltas) {
    const P = parseInt(pilas || "0", 10);
    const C = parseInt(cxp || "0", 10);
    const S = parseInt(sueltas || "0", 10);
    return P * C + S;
  }

  function parseTab1() {
    const legajo = onlyDigits($("pcmLegajo").value).slice(0, 3);
    const cod1 = normalizeCode($("pcmCod1").value).slice(0, 4);
    const cod2 = normalizeCode($("pcmCod2").value).slice(0, 4);

    const msg1 = $("pcmMsg1");
    const msg1b = $("pcmMsg1b");
    if (msg1) { msg1.textContent = ""; msg1.className = "msg"; }
    if (msg1b) { msg1b.textContent = ""; msg1b.className = "msg"; }

    if (!legajo) {
      if (msg1) { msg1.textContent = "Ingresá el número de legajo."; msg1.classList.add("error"); }
      return null;
    }
    const codes = [cod1, cod2].filter(Boolean);
    if (codes.length === 0) {
      if (msg1b) { msg1b.textContent = "Ingresá al menos 1 código."; msg1b.classList.add("error"); }
      return null;
    }

    const uniq = Array.from(new Set(codes));
    const rows = [];

    for (const code of uniq) {
      const locs = MAP[code];
      if (Array.isArray(locs) && locs.length) {
        for (const loc of locs) {
          rows.push({
            orden: Number(loc.orden),
            sector: String(loc.sector),
            codArt: String(loc.codArt ?? code),
          });
        }
      } else {
        rows.push({ orden: 999999, sector: "SIN MAPEO", codArt: code });
      }
    }

    rows.sort(
      (a, b) =>
        a.orden - b.orden ||
        a.sector.localeCompare(b.sector) ||
        a.codArt.localeCompare(b.codArt)
    );

    return { legajo, codes: uniq, rows };
  }

  function renderTab2() {
    const legajoLine = $("pcmLegajoLine");
    const countPill = $("pcmCountPill");
    if (legajoLine) legajoLine.textContent = `Legajo: ${STATE.legajo}`;
    if (countPill) countPill.textContent = `${STATE.rows.length} filas`;

    const tbody = $("pcmTbody");
    if (!tbody) return;
    tbody.innerHTML = "";

    for (const r of STATE.rows) {
      const key = rowKey(r);
      if (!STATE.fills[key]) STATE.fills[key] = { pilas: "", cjasXPila: "", cjasSueltas: "" };

      const tr = document.createElement("tr");

      const tdSec = document.createElement("td");
      tdSec.textContent = r.sector;

      const tdCod = document.createElement("td");
      tdCod.textContent = r.codArt;

      const tdP = document.createElement("td");
      tdP.className = "compact";
      const selP = buildSelect(1, 50, STATE.fills[key].pilas);

      const tdCxp = document.createElement("td");
      tdCxp.className = "compact";
      const selCxp = buildSelect(1, 10, STATE.fills[key].cjasXPila);

      const tdS = document.createElement("td");
      tdS.className = "compact";
      const inpS = document.createElement("input");
      inpS.type = "tel";
      inpS.inputMode = "numeric";
      inpS.maxLength = 2;
      inpS.placeholder = "0";
      inpS.value = STATE.fills[key].cjasSueltas || "";

      function clamp2Digits() {
        inpS.value = onlyDigits(inpS.value).slice(0, 2);
        STATE.fills[key].cjasSueltas = inpS.value;
      }

      selP.addEventListener("change", () => {
        STATE.fills[key].pilas = selP.value;
      });
      selCxp.addEventListener("change", () => {
        STATE.fills[key].cjasXPila = selCxp.value;
      });
      inpS.addEventListener("input", clamp2Digits);

      tdP.appendChild(selP);
      tdCxp.appendChild(selCxp);
      tdS.appendChild(inpS);

      tr.appendChild(tdSec);
      tr.appendChild(tdCod);
      tr.appendChild(tdP);
      tr.appendChild(tdCxp);
      tr.appendChild(tdS);

      tbody.appendChild(tr);
    }
  }

  function renderTab3() {
    const legajoLine = $("pcmLegajoLine3");
    const countPill = $("pcmCountPill3");
    if (legajoLine) legajoLine.textContent = `Legajo: ${STATE.legajo}`;
    if (countPill) countPill.textContent = `${STATE.codes.length} códigos`;

    const tbody = $("pcmTbody3");
    if (!tbody) return;
    tbody.innerHTML = "";

    for (const code of STATE.codes) {
      if (!STATE.resumen[code]) STATE.resumen[code] = { pickings: "", pfc: "", transito: "" };

      const tr = document.createElement("tr");

      const tdCod = document.createElement("td");
      tdCod.textContent = code;

      const tdPA = document.createElement("td");
      const inpPA = document.createElement("input");
      inpPA.type = "tel";
      inpPA.inputMode = "numeric";
      inpPA.maxLength = 2;
      inpPA.placeholder = "0";
      inpPA.value = STATE.resumen[code].pickings || "";
      inpPA.addEventListener("input", () => {
        STATE.resumen[code].pickings = onlyDigits(inpPA.value).slice(0, 2);
      });
      tdPA.appendChild(inpPA);

      const tdPFC = document.createElement("td");
      const inpPFC = document.createElement("input");
      inpPFC.type = "tel";
      inpPFC.inputMode = "numeric";
      inpPFC.maxLength = 2;
      inpPFC.placeholder = "0";
      inpPFC.value = STATE.resumen[code].pfc || "";
      inpPFC.addEventListener("input", () => {
        STATE.resumen[code].pfc = onlyDigits(inpPFC.value).slice(0, 2);
      });
      tdPFC.appendChild(inpPFC);

      const tdMT = document.createElement("td");
      const inpMT = document.createElement("input");
      inpMT.type = "tel";
      inpMT.inputMode = "numeric";
      inpMT.maxLength = 2;
      inpMT.placeholder = "0";
      inpMT.value = STATE.resumen[code].transito || "";
      inpMT.addEventListener("input", () => {
        STATE.resumen[code].transito = onlyDigits(inpMT.value).slice(0, 2);
      });
      tdMT.appendChild(inpMT);

      tr.appendChild(tdCod);
      tr.appendChild(tdPA);
      tr.appendChild(tdPFC);
      tr.appendChild(tdMT);
      tbody.appendChild(tr);
    }
  }

  // API pública del módulo
  window.PCM = {
    open: function () {
      const modal = $("planillaConteoModal");
      if (modal) modal.classList.remove("hidden");
      switchTab(1);
      STATE.legajo = "";
      STATE.codes = [];
      STATE.rows = [];
      STATE.fills = {};
      STATE.resumen = {};
      const legajo = $("pcmLegajo");
      const cod1 = $("pcmCod1");
      const cod2 = $("pcmCod2");
      if (legajo) legajo.value = "";
      if (cod1) cod1.value = "";
      if (cod2) cod2.value = "";
      setStatus();
    },

    close: function () {
      const modal = $("planillaConteoModal");
      if (modal) modal.classList.add("hidden");
      switchTab(1);
    },

    siguiente1: function () {
      const parsed = parseTab1();
      if (!parsed) return;
      STATE.legajo = parsed.legajo;
      STATE.codes = parsed.codes;
      STATE.rows = parsed.rows;
      renderTab2();
      switchTab(2);
    },

    volver2: function () {
      switchTab(1);
    },

    siguiente2: function () {
      renderTab3();
      switchTab(3);
    },

    volver3: function () {
      switchTab(2);
    },

    reset2: function () {
      STATE.fills = {};
      renderTab2();
    },

    reset3: function () {
      STATE.resumen = {};
      renderTab3();
    },

    enviarFinal: async function () {
      showOverlay(true, "Enviando…", "Guardando en Google Sheet");
      try {
        const payload = {
          legajo: STATE.legajo,
          timestamp: new Date().toISOString(),
          tab2: Object.fromEntries(
            Object.entries(STATE.fills).map(([k, v]) => [
              k,
              { pilas: v.pilas, cxp: v.cjasXPila, sueltas: v.cjasSueltas }
            ])
          ),
          tab3: STATE.resumen
        };

        const response = await fetch(APP_SCRIPT_URL, {
          method: "POST",
          mode: "no-cors",
          body: JSON.stringify(payload)
        });

        showOverlay(false);
        alert("✅ Planilla enviada exitosamente");
        this.close();
      } catch (e) {
        showOverlay(false);
        alert("❌ Error al enviar: " + e.message);
      }
    },

    limpiar: function () {
      STATE.legajo = "";
      STATE.codes = [];
      STATE.rows = [];
      STATE.fills = {};
      STATE.resumen = {};
      const legajo = $("pcmLegajo");
      const cod1 = $("pcmCod1");
      const cod2 = $("pcmCod2");
      if (legajo) legajo.value = "";
      if (cod1) cod1.value = "";
      if (cod2) cod2.value = "";
      setStatus();
    },

    handleInput: function (el) {
      setStatus();
    }
  };
})();
