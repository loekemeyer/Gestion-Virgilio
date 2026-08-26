/* =========================================================
   MÓDULO: Editar Talleristas / Proveedores AT
   v1.0 — Cambiar nombre, teléfono, estado, agregar/quitar artículos.
   ========================================================= */

let _tallEditModal = null, _tallEditState = {};

async function tallEditInit() {
  // Crear modal si no existe
  if (!document.getElementById("tallEditModal")) {
    const modal = document.createElement("div");
    modal.id = "tallEditModal";
    modal.className = "modal hidden";
    modal.innerHTML = `
      <div class="modal-content tall-edit-modal">
        <div class="modal-header">
          <h2>✏️ Editar Tallerista / Proveedor AT</h2>
          <button onclick="tallEditClose()" class="modal-close">×</button>
        </div>
        <div class="modal-body">

          <!-- PASO 1: Datos básicos -->
          <div id="tallEditStep1" class="tall-edit-step">
            <h3>Datos Básicos</h3>
            <div class="form-group">
              <label>Nombre:</label>
              <input id="tallEditNombre" type="text" class="form-input" readonly style="background:#f0f0f0;">
            </div>
            <div class="form-group">
              <label>Teléfono:</label>
              <input id="tallEditTelefono" type="text" placeholder="Ej: +54 9 11 1234-5678" class="form-input">
            </div>
            <div class="form-group">
              <label><input type="checkbox" id="tallEditActivo"> Activo</label>
            </div>
            <button onclick="tallEditStep1Save()" class="btn-primary" style="margin-top:12px;">💾 Guardar Datos</button>
          </div>

          <!-- PASO 2: Artículos -->
          <div id="tallEditStep2" class="tall-edit-step" style="margin-top:24px;">
            <h3>Artículos</h3>
            <div class="form-group">
              <label>Buscar artículos para agregar:</label>
              <input id="tallEditArtSearch" type="text" placeholder="🔎 código, descripción..." class="form-input" oninput="tallEditFilterArts()">
            </div>
            <div id="tallEditArtList" class="tall-edit-arts-list" style="max-height:200px; overflow-y:auto; border:1px solid #e2e8f0; border-radius:6px; padding:8px; margin-bottom:16px;">
              <div class="loading">Cargando artículos...</div>
            </div>

            <div style="margin-top:16px;">
              <h4 style="margin-bottom:8px;">Artículos Actuales:</h4>
              <div id="tallEditCurrentArts" style="border:1px solid #e2e8f0; border-radius:6px; padding:8px; max-height:250px; overflow-y:auto;">
                <div class="loading">Cargando...</div>
              </div>
            </div>

            <button onclick="tallEditClose()" class="btn-secondary" style="margin-top:16px;">Cerrar</button>
          </div>

        </div>
      </div>
    `;
    document.body.appendChild(modal);
    _tallEditModal = modal;
  }

  // Estilos
  if (!document.getElementById("tallEditStyles")) {
    const style = document.createElement("style");
    style.id = "tallEditStyles";
    style.textContent = `
      .tall-edit-modal { min-width: 500px; max-width: 650px; }
      .tall-edit-step { display: block; }
      .tall-edit-step.hidden { display: none; }
      .tall-edit-arts-list { border: 1px solid #e2e8f0; }
      .tall-edit-art-item { padding: 8px; border-bottom: 1px solid #f0f0f0; cursor: pointer; border-radius: 4px; }
      .tall-edit-art-item:hover { background: #f9fafb; }
      .tall-edit-art-item.selected { background: #dbeafe; border-left: 4px solid #3b82f6; }
      .tall-edit-art-item input { margin-right: 8px; }
      .tall-edit-current-art { padding: 8px; border-bottom: 1px solid #e2e8f0; display: flex; justify-content: space-between; align-items: center; border-radius: 4px; }
      .tall-edit-current-art:hover { background: #fffbeb; }
      .tall-edit-current-art button { background: #ef4444; color: white; border: none; padding: 4px 8px; border-radius: 3px; cursor: pointer; font-size: 11px; }
      .tall-edit-current-art button:hover { background: #dc2626; }
      .modal { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 9999; }
      .modal.hidden { display: none; }
      .modal-content { background: white; border-radius: 8px; padding: 20px; max-height: 90vh; overflow-y: auto; }
      .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
      .modal-close { background: none; border: none; font-size: 24px; cursor: pointer; }
      .form-group { margin-bottom: 12px; }
      .form-group label { display: block; font-weight: 600; margin-bottom: 4px; font-size: 13px; }
      .form-input { width: 100%; padding: 8px; border: 1px solid #cbd5e1; border-radius: 4px; font-size: 13px; }
      .btn-primary { background: #3b82f6; color: white; padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; font-weight: 600; }
      .btn-primary:hover { background: #2563eb; }
      .btn-secondary { background: #e2e8f0; color: #1e293b; padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; }
      .loading { text-align: center; padding: 16px; color: #64748b; }
      h4 { font-size: 14px; font-weight: 600; color: #1e293b; margin: 0; }
    `;
    document.head.appendChild(style);
  }
}

async function tallEditOpen(nombre) {
  await tallEditInit();
  _tallEditState = { nombre: nombre, telefono: "", activo: true, artsSelected: {}, allArts: [] };

  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };

  try {
    // Cargar datos del tallerista desde Tall_ProvAT_PS
    const tallRes = await fetch(
      SUPABASE_URL + "/rest/v1/Tall_ProvAT_PS?nombre=eq." + encodeURIComponent(nombre) + "&select=nombre,telefono,activo",
      { headers: H }
    );
    if (!tallRes.ok) throw new Error("Error cargando tallerista");
    const tallData = await tallRes.json();
    if (!tallData.length) { alert("Tallerista no encontrado."); return; }

    const tall = tallData[0];
    _tallEditState.nombre = tall.nombre;
    _tallEditState.telefono = tall.telefono || "";
    _tallEditState.activo = tall.activo;

    // Determinar tipo (tallerista o prov_at)
    const typeRes = await fetch(
      SUPABASE_URL + "/rest/v1/Tall_ProvAT_PS?nombre=eq." + encodeURIComponent(nombre) + "&select=prov_at",
      { headers: H }
    );
    const typeData = await typeRes.json();
    _tallEditState.tipo = typeData[0]?.prov_at ? "prov_at" : "tallerista";

    // Cargar artículos actuales
    if (_tallEditState.tipo === "prov_at") {
      const artsRes = await fetch(
        SUPABASE_URL + "/rest/v1/Articulos%20x%20Prov%20AT?Proveedor=eq." + encodeURIComponent(nombre) + "&select=Cod_Art,Descripcion,N_Caja",
        { headers: H }
      );
      const arts = await artsRes.json();
      _tallEditState.currentArts = arts || [];
    } else {
      const artsRes = await fetch(
        SUPABASE_URL + "/rest/v1/Articulos%20Virgilio%20X%20Tallerista?Tallerista=eq." + encodeURIComponent(nombre) + "&select=Cod_Art,Desc,Uni_x_Caja",
        { headers: H }
      );
      const arts = await artsRes.json();
      _tallEditState.currentArts = arts || [];
    }

    // Cargar artículos disponibles para agregar
    const ocArtsP = supaFetchAllSafe(SUPABASE_URL + "/rest/v1/OC_Maximos", "select=cod,descripcion&activo=eq.true");
    const allArts = await ocArtsP;
    _tallEditState.allArts = (allArts || []).map(a => ({ Cod_Art: a.cod, Desc: a.descripcion }));

    // Llenar formulario
    document.getElementById("tallEditNombre").value = tall.nombre;
    document.getElementById("tallEditTelefono").value = _tallEditState.telefono;
    document.getElementById("tallEditActivo").checked = _tallEditState.activo;

    // Mostrar modal
    document.getElementById("tallEditStep1").classList.remove("hidden");
    document.getElementById("tallEditStep2").classList.remove("hidden");
    tallEditRenderCurrentArts();
    tallEditFilterArts();

    _tallEditModal.classList.remove("hidden");
  } catch (e) {
    console.error("Error abriendo editor:", e);
    alert("Error al cargar tallerista: " + e.message);
  }
}

function tallEditClose() {
  if (_tallEditModal) _tallEditModal.classList.add("hidden");
  _tallEditState = {};
}

async function tallEditStep1Save() {
  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  const nombre = _tallEditState.nombre;
  const telefono = document.getElementById("tallEditTelefono").value.trim();
  const activo = document.getElementById("tallEditActivo").checked;

  try {
    const updateBody = { telefono: telefono || null, activo: activo };
    const res = await fetch(
      SUPABASE_URL + "/rest/v1/Tall_ProvAT_PS?nombre=eq." + encodeURIComponent(nombre),
      {
        method: "PATCH",
        headers: { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY, "Content-Type": "application/json" },
        body: JSON.stringify(updateBody)
      }
    );
    if (!res.ok) throw new Error("HTTP " + res.status);
    alert("✓ Datos guardados.");
    _tallEditState.telefono = telefono;
    _tallEditState.activo = activo;
  } catch (e) {
    console.error("Error al guardar:", e);
    alert("Error: " + e.message);
  }
}

function tallEditFilterArts() {
  const q = (document.getElementById("tallEditArtSearch").value || "").toLowerCase().trim();
  const arts = (_tallEditState.allArts || []).filter(a => {
    const cod = String(a.Cod_Art || "").toLowerCase();
    const desc = String(a.Desc || "").toLowerCase();
    return q === "" || cod.includes(q) || desc.includes(q);
  });

  const listEl = document.getElementById("tallEditArtList");
  if (!arts.length) {
    listEl.innerHTML = '<div class="loading">No se encontraron artículos.</div>';
    return;
  }

  // Filtrar artículos que ya están asignados
  const currentCods = (_tallEditState.currentArts || []).map(a => a.Cod_Art || a.cod);
  const available = arts.filter(a => !currentCods.includes(a.Cod_Art));

  if (!available.length) {
    listEl.innerHTML = '<div class="loading">Todos los artículos ya están asignados.</div>';
    return;
  }

  let html = '';
  available.forEach(a => {
    html += '<div class="tall-edit-art-item" onclick="tallEditAddArt(\'' + a.Cod_Art + '\', \'' + (a.Desc || '?').replace(/'/g, "\\'") + '\')">' +
      '<b>' + a.Cod_Art + '</b> — ' + (a.Desc || '?') +
      '</div>';
  });
  listEl.innerHTML = html;
}

async function tallEditAddArt(codArt, desc) {
  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  const nombre = _tallEditState.nombre;
  const tipo = _tallEditState.tipo;

  try {
    if (tipo === "prov_at") {
      // Insertar en Articulos x Prov AT
      const artBody = { Proveedor: nombre, Cod_Art: codArt, Descripcion: desc, Activo: true, N_Caja: 1, marca: null };
      const res = await fetch(SUPABASE_URL + "/rest/v1/Articulos%20x%20Prov%20AT", {
        method: "POST",
        headers: { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY, "Content-Type": "application/json", "Prefer": "return=minimal" },
        body: JSON.stringify(artBody)
      });
      if (!res.ok) throw new Error("HTTP " + res.status);
    } else {
      // Insertar en Articulos Virgilio X Tallerista (ambas líneas)
      const codsRes = await fetch(
        SUPABASE_URL + "/rest/v1/Codigos%20X%20Tallerista?Nombre=eq." + encodeURIComponent(nombre) + "&select=Linea,Codigo",
        { headers: H }
      );
      const cods = await codsRes.json();
      const codMap = {};
      (cods || []).forEach(c => { codMap[c.Linea] = c.Codigo; });

      const artRows = [];
      ["LK", "CH"].forEach(l => {
        if (codMap[l]) {
          artRows.push({
            Cod_Tallerista: codMap[l], Tallerista: nombre,
            Cod_Art: codArt, Linea: l, Desc: desc,
            Uni_x_Caja: 1
          });
        }
      });

      if (artRows.length) {
        const res = await fetch(SUPABASE_URL + "/rest/v1/Articulos%20Virgilio%20X%20Tallerista", {
          method: "POST",
          headers: { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY, "Content-Type": "application/json", "Prefer": "return=minimal" },
          body: JSON.stringify(artRows)
        });
        if (!res.ok) throw new Error("HTTP " + res.status);
      }
    }

    // Recargar artículos actuales
    await tallEditReloadCurrentArts();
    document.getElementById("tallEditArtSearch").value = "";
    tallEditFilterArts();
  } catch (e) {
    console.error("Error al agregar artículo:", e);
    alert("Error: " + e.message);
  }
}

async function tallEditReloadCurrentArts() {
  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  const nombre = _tallEditState.nombre;
  const tipo = _tallEditState.tipo;

  try {
    if (tipo === "prov_at") {
      const artsRes = await fetch(
        SUPABASE_URL + "/rest/v1/Articulos%20x%20Prov%20AT?Proveedor=eq." + encodeURIComponent(nombre) + "&select=Cod_Art,Descripcion,N_Caja",
        { headers: H }
      );
      _tallEditState.currentArts = await artsRes.json();
    } else {
      const artsRes = await fetch(
        SUPABASE_URL + "/rest/v1/Articulos%20Virgilio%20X%20Tallerista?Tallerista=eq." + encodeURIComponent(nombre) + "&select=Cod_Art,Desc,Uni_x_Caja",
        { headers: H }
      );
      _tallEditState.currentArts = await artsRes.json();
    }
    tallEditRenderCurrentArts();
  } catch (e) {
    console.error("Error recargando artículos:", e);
  }
}

function tallEditRenderCurrentArts() {
  const contEl = document.getElementById("tallEditCurrentArts");
  const arts = _tallEditState.currentArts || [];

  if (!arts.length) {
    contEl.innerHTML = '<div style="color:#999; text-align:center; padding:16px;">Sin artículos asignados.</div>';
    return;
  }

  let html = '';
  arts.forEach(a => {
    const cod = a.Cod_Art || a.cod;
    const desc = a.Desc || a.Descripcion || "?";
    html += '<div class="tall-edit-current-art">' +
      '<span><b>' + cod + '</b> — ' + desc + '</span>' +
      '<button onclick="tallEditRemoveArt(\'' + cod + '\')">Quitar</button>' +
      '</div>';
  });
  contEl.innerHTML = html;
}

async function tallEditRemoveArt(codArt) {
  if (!confirm("¿Quitar artículo " + codArt + "?")) return;

  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  const nombre = _tallEditState.nombre;
  const tipo = _tallEditState.tipo;

  try {
    if (tipo === "prov_at") {
      const res = await fetch(
        SUPABASE_URL + "/rest/v1/Articulos%20x%20Prov%20AT?Proveedor=eq." + encodeURIComponent(nombre) + "&Cod_Art=eq." + encodeURIComponent(codArt),
        { method: "DELETE", headers: H }
      );
      if (!res.ok) throw new Error("HTTP " + res.status);
    } else {
      const res = await fetch(
        SUPABASE_URL + "/rest/v1/Articulos%20Virgilio%20X%20Tallerista?Tallerista=eq." + encodeURIComponent(nombre) + "&Cod_Art=eq." + encodeURIComponent(codArt),
        { method: "DELETE", headers: H }
      );
      if (!res.ok) throw new Error("HTTP " + res.status);
    }

    await tallEditReloadCurrentArts();
  } catch (e) {
    console.error("Error al quitar artículo:", e);
    alert("Error: " + e.message);
  }
}

// Exponer globalmente
window.tallEditOpen = tallEditOpen;
window.tallEditClose = tallEditClose;
window.tallEditStep1Save = tallEditStep1Save;
window.tallEditFilterArts = tallEditFilterArts;
window.tallEditAddArt = tallEditAddArt;
window.tallEditReloadCurrentArts = tallEditReloadCurrentArts;
window.tallEditRenderCurrentArts = tallEditRenderCurrentArts;
window.tallEditRemoveArt = tallEditRemoveArt;
