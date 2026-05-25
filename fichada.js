/* =========================================================
   fichada.js — Ingreso Virgilio (Supabase)
   El QR es solo para ingreso. La fichada se manda a la tabla
   "Fichadas_Virgilio" en Supabase. Después, el monitor de Virgilio
   cruza el email contra la tabla "Empleados" para resolver legajo
   y calcular la jornada combinando con PC (Paré Comida) y FJ (Fin
   Jornada) que se envían desde la app principal.
   ========================================================= */
(function () {
  const cfg = window.FICHADA_CONFIG;
  const { verifyToken } = window.FichadaToken;

  const form = document.getElementById("fichada-form");
  const emailInput = document.getElementById("email-input");
  const rememberCb = document.getElementById("remember-email");
  const userEmailLbl = document.getElementById("user-email");
  const changeAccountBtn = document.getElementById("change-account");
  const submitBtn = document.getElementById("submit-btn");
  const clearBtn = document.getElementById("clear-btn");
  const statusEl = document.getElementById("form-status");
  const emailErr = document.getElementById("email-error");

  const params = new URLSearchParams(location.search);
  const token = params.get("t");

  const SUPABASE_URL = cfg.supabaseUrl;
  const SUPABASE_KEY = cfg.supabaseKey;
  const FICHADAS_ENDPOINT = SUPABASE_URL + "/rest/v1/Fichadas_Virgilio";
  const EMPLEADOS_ENDPOINT = SUPABASE_URL + "/rest/v1/Empleados";

  init();

  async function init() {
    const ok =
      token &&
      (await verifyToken(
        token,
        cfg.hmacSecret,
        cfg.tokenPeriodSec,
        cfg.tokenTolerance
      ));
    if (!ok) {
      showInvalidToken();
      return;
    }
    setupEmailMemory();
    wireUp();
  }

  function showInvalidToken() {
    form.hidden = true;
    statusEl.dataset.state = "error";
    statusEl.classList.add("form-status--banner");
    statusEl.textContent = token
      ? "El codigo QR expiro. Volve a escanear el QR de la pantalla de fichada."
      : "Esta pagina solo es accesible escaneando el QR de fichada de la sede.";
  }

  function setupEmailMemory() {
    const saved = localStorage.getItem("fichada.email");
    if (saved) {
      emailInput.value = saved;
      userEmailLbl.textContent = saved;
      rememberCb.checked = true;
    } else {
      userEmailLbl.textContent = "(sin correo)";
    }
    emailInput.addEventListener("input", () => {
      const v = emailInput.value.trim();
      userEmailLbl.textContent = v || "(sin correo)";
    });
    changeAccountBtn.addEventListener("click", () => {
      localStorage.removeItem("fichada.email");
      emailInput.value = "";
      userEmailLbl.textContent = "(sin correo)";
      rememberCb.checked = false;
      emailInput.focus();
    });
  }

  function wireUp() {
    form.addEventListener("submit", onSubmit);
    clearBtn.addEventListener("click", () => {
      form.reset();
      emailErr.hidden = true;
      statusEl.textContent = "";
      statusEl.removeAttribute("data-state");
    });
  }

  async function onSubmit(e) {
    e.preventDefault();
    emailErr.hidden = true;

    const email = emailInput.value.trim().toLowerCase();

    if (!isEmail(email)) {
      emailErr.hidden = false;
      emailInput.focus();
      return;
    }

    const stillValid = await verifyToken(
      token,
      cfg.hmacSecret,
      cfg.tokenPeriodSec,
      cfg.tokenTolerance
    );
    if (!stillValid) {
      statusEl.dataset.state = "error";
      statusEl.textContent =
        "El codigo QR expiro mientras llenabas el formulario. Escanea uno nuevo.";
      return;
    }

    if (rememberCb.checked) {
      localStorage.setItem("fichada.email", email);
    } else {
      localStorage.removeItem("fichada.email");
    }

    submitBtn.disabled = true;
    statusEl.removeAttribute("data-state");
    statusEl.textContent = "Registrando ingreso...";

    try {
      // Antes de insertar, intento cruzar email -> legajo para que
      // quede guardado directamente en la fila de fichada. Si no
      // encuentra, igual registra el ingreso con legajo=null y el
      // monitor avisa al supervisor.
      let legajo = null;
      try {
        legajo = await lookupLegajoByEmail(email);
      } catch (_) {
        // Si falla el lookup (red flaky), seguimos igual y dejamos
        // legajo=null. Lo importante es no perder el ingreso.
        legajo = null;
      }

      // Supabase es la fuente de verdad — si falla, fallamos toda la fichada.
      // El Google Form es un mirror para el sheet de fichadas Esnaola
      // (legacy), best-effort: si falla no se nota, Supabase ya guardó.
      await submitFichadaToSupabase(email, legajo);
      submitToGoogleFormMirror(email).catch(() => {/* fire-and-forget */});

      statusEl.dataset.state = "ok";
      statusEl.textContent = legajo
        ? "Ingreso registrado (legajo " + legajo + ")."
        : "Ingreso registrado. Avisale al encargado si tu email no aparece linkeado.";
      resetAfterSuccess();
    } catch (err) {
      statusEl.dataset.state = "error";
      statusEl.textContent =
        "No se pudo registrar el ingreso. Reintenta en unos segundos.";
    } finally {
      submitBtn.disabled = false;
    }
  }

  async function lookupLegajoByEmail(email) {
    // Empleados tiene columna email y Legajo. Usamos ilike (case-insensitive)
    // para tolerar que el supervisor haya cargado el email con mayúsculas
    // diferentes a las que escribe el operario. ilike sin wildcards = match
    // exacto pero case-insensitive.
    const url =
      EMPLEADOS_ENDPOINT +
      "?email=ilike." +
      encodeURIComponent(email) +
      "&select=Legajo&limit=1";
    const res = await fetch(url, {
      method: "GET",
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: "Bearer " + SUPABASE_KEY,
      },
    });
    if (!res.ok) return null;
    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) return null;
    const leg = data[0].Legajo;
    return leg != null ? String(leg) : null;
  }

  async function submitFichadaToSupabase(email, legajo) {
    const clientId = makeClientId();
    const body = {
      client_id: clientId,
      email: email,
      legajo: legajo, // puede ser null si no se encontró
      tipo: "ingreso",
      ts_cliente: new Date().toISOString(),
      user_agent: navigator.userAgent || null,
    };

    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 12000);

    try {
      const res = await fetch(FICHADAS_ENDPOINT, {
        method: "POST",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: "Bearer " + SUPABASE_KEY,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
      clearTimeout(t);
      if (!res.ok && res.status !== 409) {
        throw new Error("server_" + res.status);
      }
    } catch (e) {
      clearTimeout(t);
      throw e;
    }
  }

  function makeClientId() {
    // Mismo formato que usa la app principal: ts + random base36.
    return (
      Date.now().toString(36) +
      "-" +
      Math.random().toString(36).slice(2, 10)
    );
  }

  // Bridge al Google Form (mirror del sheet de fichadas Esnaola).
  // Postea como "Entrada" + email. Usa el pattern ghost-form + iframe sink
  // porque Google Forms no permite POST con fetch() por CORS — pero sí
  // acepta un form submit clásico apuntando a un iframe oculto.
  // Best-effort: si falla, no rompemos. Supabase es la fuente de verdad.
  function submitToGoogleFormMirror(email) {
    return new Promise((resolve, reject) => {
      try {
        console.log("[bridge-form] submit Entrada para", email);
        if (!cfg.formActionUrl) {
          console.warn("[bridge-form] sin formActionUrl en config, skip");
          resolve(); return;
        }
        if (!cfg.eventoEntryId || cfg.eventoEntryId.indexOf("REEMPLAZAR") !== -1) {
          console.warn("[bridge-form] eventoEntryId invalido:", cfg.eventoEntryId);
          resolve(); return;
        }
        const sink = document.getElementById("gforms_sink");
        if (!sink) {
          console.warn("[bridge-form] iframe gforms_sink NO existe en el DOM");
          resolve(); return;
        }

        const ghost = document.createElement("form");
        ghost.action = cfg.formActionUrl;
        ghost.method = "POST";
        ghost.target = "gforms_sink";
        ghost.style.display = "none";

        const addHidden = (name, value) => {
          const inp = document.createElement("input");
          inp.type = "hidden";
          inp.name = name;
          inp.value = value;
          ghost.appendChild(inp);
        };

        // Como el QR es solo para ingreso, siempre "Entrada".
        addHidden(cfg.eventoEntryId, "Entrada");
        if (cfg.emailMode === "entry") {
          addHidden(cfg.emailEntryId, email);
        } else {
          addHidden("emailAddress", email);
        }
        // Boilerplate que Google Forms espera en el POST.
        addHidden("fvv", "1");
        addHidden("draftResponse", "[]");
        addHidden("pageHistory", "0");

        document.body.appendChild(ghost);

        let settled = false;
        const cleanup = () => {
          sink.removeEventListener("load", onLoad);
          try { ghost.remove(); } catch {}
        };
        const onLoad = () => {
          if (settled) return;
          settled = true;
          console.log("[bridge-form] iframe LOAD — POST procesado por Google");
          cleanup();
          resolve();
        };
        sink.addEventListener("load", onLoad);
        try {
          ghost.submit();
          console.log("[bridge-form] ghost.submit() ejecutado");
        } catch (subErr) {
          console.error("[bridge-form] ghost.submit() tiro:", subErr);
          cleanup();
          reject(subErr);
          return;
        }

        // Timeout chico — si Google tarda demasiado damos por fallida la
        // mirror y seguimos. La fichada ya quedó en Supabase.
        setTimeout(() => {
          if (settled) return;
          settled = true;
          console.warn("[bridge-form] TIMEOUT — iframe no disparo load en 6s. Probable bloqueo iOS/CSP/red.");
          cleanup();
          reject(new Error("timeout"));
        }, 6000);
      } catch (e) {
        console.error("[bridge-form] excepcion:", e);
        reject(e);
      }
    });
  }

  function resetAfterSuccess() {
    form.reset();
    const saved = localStorage.getItem("fichada.email");
    if (saved) {
      emailInput.value = saved;
      rememberCb.checked = true;
      userEmailLbl.textContent = saved;
    } else {
      userEmailLbl.textContent = "(sin correo)";
    }
  }

  function isEmail(s) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
  }
})();
