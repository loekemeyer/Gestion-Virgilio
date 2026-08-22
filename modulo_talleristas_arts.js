/* =========================================================
   MÓDULO: Gestión de Talleristas / Proveedores AT con Artículos
   v1.0 — Agregar tallerista, asignar artículos automáticamente
   con validación de marca (LK/CH) y detección de overlaps.
   ========================================================= */

let _tallArtModal = null, _tallArtState = {};

async function tallArtInit() {
  // Crear modal si no existe
  if (!document.getElementById("tallArtModal")) {
    const modal = document.createElement("div");
    modal.id = "tallArtModal";
    modal.className = "modal hidden";
    modal.innerHTML = `
      <div class="modal-content tall-art-modal">
        <div class="modal-header">
          <h2>➕ Nuevo Tallerista / Proveedor AT</h2>
          <button onclick="tallArtClose()" class="modal-close">×</button>
        </div>
        <div class="modal-body">

          <!-- PASO 1: Datos básicos -->
          <div id="tallArtStep1" class="tall-art-step">
            <h3>Paso 1: Datos básicos</h3>
            <div class="form-group">
              <label>Nombre del tallerista/proveedor:</label>
              <input id="tallArtNombre" type="text" placeholder="Ej: Cabral, Maspoli, etc" class="form-input">
            </div>
            <div class="form-group">
              <label>Tipo:</label>
              <div class="radio-group">
                <label><input type="radio" name="tallArtTipo" value="tallerista"> Tallerista (recibe partes)</label>
                <label><input type="radio" name="tallArtTipo" value="prov_at" checked> Proveedor AT (entrega artículos terminados)</label>
              </div>
            </div>
            <div class="form-group">
              <label><input type="checkbox" id="tallArtActivo" checked> Activo</label>
            </div>
            <button onclick="tallArtStep1Next()" class="btn-primary">Siguiente → Artículos</button>
          </div>

          <!-- PASO 2: Búsqueda y selección de artículos -->
          <div id="tallArtStep2" class="tall-art-step hidden">
            <h3>Paso 2: Asignar Artículos</h3>
            <p style="font-size:13px; color:#64748b; margin-bottom:12px;">
              Busca y selecciona los artículos que ${(() => {
                const tipo = document.querySelector('input[name="tallArtTipo"]:checked')?.value;
                return tipo === 'prov_at' ? 'entrega este proveedor' : 'recibe este tallerista';
              })()}. Los datos de descripción y unidades se cargan automáticamente.
            </p>
            <div class="form-group">
              <label>Buscar artículos:</label>
              <input id="tallArtArtSearch" type="text" placeholder="🔎 código, descripción..." class="form-input" oninput="tallArtFilterArts()">
            </div>
            <div id="tallArtArtList" class="tall-art-arts-list" style="max-height:300px; overflow-y:auto; border:1px solid #e2e8f0; border-radius:6px; padding:8px;">
              <div class="loading">Cargando artículos...</div>
            </div>
            <div style="margin-top:12px; font-size:12px; color:#64748b;">
              <b>Seleccionados:</b> <span id="tallArtSelCount">0</span> artículos
            </div>
            <div class="tall-art-buttons" style="margin-top:16px;">
              <button onclick="tallArtStep2Back()" class="btn-secondary">← Atrás</button>
              <button onclick="tallArtStep2Next()" class="btn-primary">Siguiente → Validar</button>
            </div>
          </div>

          <!-- PASO 3: Validación de overlaps y marcas -->
          <div id="tallArtStep3" class="tall-art-step hidden">
            <h3>Paso 3: Validar Marcas</h3>
            <p style="font-size:13px; color:#64748b; margin-bottom:12px;">
              Algunos artículos existen en otros talleristas. Confirmá la marca (LK/CH) para cada uno.
            </p>
            <div id="tallArtOverlapList" style="max-height:300px; overflow-y:auto;">
              <!-- Llenado por JS -->
            </div>
            <div class="tall-art-buttons" style="margin-top:16px;">
              <button onclick="tallArtStep3Back()" class="btn-secondary">← Atrás</button>
              <button onclick="tallArtStep3Save()" class="btn-primary">💾 Guardar Todo</button>
            </div>
          </div>

        </div>
      </div>
    `;
    document.body.appendChild(modal);
    _tallArtModal = modal;
  }

  // Estilos
  if (!document.getElementById("tallArtStyles")) {
    const style = document.createElement("style");
    style.id = "tallArtStyles";
    style.textContent = `
      .tall-art-modal { min-width: 500px; max-width: 600px; }
      .tall-art-step { display: block; }
      .tall-art-step.hidden { display: none; }
      .tall-art-arts-list { border: 1px solid #e2e8f0; }
      .tall-art-art-item { padding: 8px; border-bottom: 1px solid #f0f0f0; cursor: pointer; border-radius: 4px; }
      .tall-art-art-item:hover { background: #f9fafb; }
      .tall-art-art-item.selected { background: #dbeafe; border-left: 4px solid #3b82f6; }
      .tall-art-art-item input { margin-right: 8px; }
      .tall-art-buttons { display: flex; gap: 8px; justify-content: flex-end; }
      .tall-art-overlap-item { padding: 12px; border: 1px solid #fde047; background: #fefce8; border-radius: 6px; margin-bottom: 8px; }
      .tall-art-overlap-item select { margin-top: 6px; padding: 4px; }
      .modal { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 9999; }
      .modal.hidden { display: none; }
      .modal-content { background: white; border-radius: 8px; padding: 20px; max-height: 90vh; overflow-y: auto; }
      .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
      .modal-close { background: none; border: none; font-size: 24px; cursor: pointer; }
      .form-group { margin-bottom: 12px; }
      .form-group label { display: block; font-weight: 600; margin-bottom: 4px; font-size: 13px; }
      .form-input { width: 100%; padding: 8px; border: 1px solid #cbd5e1; border-radius: 4px; font-size: 13px; }
      .radio-group { display: flex; flex-direction: column; gap: 6px; }
      .radio-group label { font-weight: normal; display: flex; align-items: center; }
      .btn-primary { background: #3b82f6; color: white; padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; font-weight: 600; }
      .btn-primary:hover { background: #2563eb; }
      .btn-secondary { background: #e2e8f0; color: #1e293b; padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; }
      .loading { text-align: center; padding: 16px; color: #64748b; }
    `;
    document.head.appendChild(style);
  }
}

function tallArtOpen() {
  tallArtInit();
  _tallArtState = { nombre: "", tipo: "prov_at", activo: true, artsSelected: {}, overlaps: {} };
  document.getElementById("tallArtStep1").classList.remove("hidden");
  document.getElementById("tallArtStep2").classList.add("hidden");
  document.getElementById("tallArtStep3").classList.add("hidden");
  _tallArtModal.classList.remove("hidden");
}

function tallArtClose() {
  if (_tallArtModal) _tallArtModal.classList.add("hidden");
  _tallArtState = {};
}

async function tallArtStep1Next() {
  const nombre = document.getElementById("tallArtNombre").value.trim();
  if (!nombre) { alert("Ingresá el nombre del tallerista/proveedor."); return; }

  // Verificar que no exista
  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  const chk = await fetch(SUPABASE_URL + "/rest/v1/Tall_ProvAT_PS?nombre=eq." + encodeURIComponent(nombre) + "&select=nombre", { headers: H }).then(r => r.json()).catch(() => []);
  if (chk.length) { alert("Ya existe un tallerista/proveedor con ese nombre."); return; }

  _tallArtState.nombre = nombre;
  _tallArtState.tipo = document.querySelector('input[name="tallArtTipo"]:checked').value;
  _tallArtState.activo = document.getElementById("tallArtActivo").checked;

  // Ir al paso 2
  document.getElementById("tallArtStep1").classList.add("hidden");
  document.getElementById("tallArtStep2").classList.remove("hidden");
  await tallArtLoadArts();
}

async function tallArtLoadArts() {
  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  try {
    // v11.23 — paginado (PostgREST corta en 1000 filas; la tabla tiene ~350 y crece)
    const arts = await supaFetchAllSafe(SUPABASE_URL + "/rest/v1/Articulos%20Virgilio%20X%20Tallerista", "select=Cod_Art,Desc,Uni_x_Caja");
    _tallArtState.allArts = arts || [];
    tallArtFilterArts();
  } catch (e) {
    console.error("Error cargando artículos:", e);
    document.getElementById("tallArtArtList").innerHTML = '<div class="loading" style="color:red;">Error al cargar artículos.</div>';
  }
}

function tallArtFilterArts() {
  const q = (document.getElementById("tallArtArtSearch").value || "").toLowerCase().trim();
  const arts = (_tallArtState.allArts || []).filter(a => {
    const cod = String(a.Cod_Art || "").toLowerCase();
    const desc = String(a.Desc || "").toLowerCase();
    return q === "" || cod.includes(q) || desc.includes(q);
  });

  const listEl = document.getElementById("tallArtArtList");
  if (!arts.length) {
    listEl.innerHTML = '<div class="loading">No se encontraron artículos.</div>';
    return;
  }

  let html = '';
  arts.forEach(a => {
    const artId = a.Cod_Art;
    const checked = _tallArtState.artsSelected[artId] ? 'checked' : '';
    html += `
      <div class="tall-art-art-item ${_tallArtState.artsSelected[artId] ? 'selected' : ''}">
        <input type="checkbox" value="${artId}" ${checked} onchange="tallArtToggleArt('${artId}', this.checked)">
        <b>${a.Cod_Art}</b> — ${a.Desc || '?'} <small>(${a.Uni_x_Caja || 1} u/caja)</small>
      </div>
    `;
  });
  listEl.innerHTML = html;
  document.getElementById("tallArtSelCount").textContent = Object.keys(_tallArtState.artsSelected).length;
}

function tallArtToggleArt(artId, checked) {
  if (checked) {
    const art = (_tallArtState.allArts || []).find(a => a.Cod_Art === artId);
    if (art) {
      _tallArtState.artsSelected[artId] = { cod: artId, desc: art.Desc, uni: art.Uni_x_Caja || 1, marca: "" };
    }
  } else {
    delete _tallArtState.artsSelected[artId];
  }
  tallArtFilterArts();
}

function tallArtStep2Back() {
  document.getElementById("tallArtStep2").classList.add("hidden");
  document.getElementById("tallArtStep1").classList.remove("hidden");
}

async function tallArtStep2Next() {
  const arts = Object.keys(_tallArtState.artsSelected);
  if (!arts.length) { alert("Seleccioná al menos 1 artículo."); return; }

  // Detectar overlaps
  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  try {
    const existing = await fetch(SUPABASE_URL + "/rest/v1/Articulos%20x%20Prov%20AT?Cod_Art=in.(" + arts.map(encodeURIComponent).join(",") + ")&select=Cod_Art,Proveedor,marca", { headers: H }).then(r => r.json()).catch(() => []);

    _tallArtState.overlaps = {};
    existing.forEach(row => {
      if (!_tallArtState.overlaps[row.Cod_Art]) {
        _tallArtState.overlaps[row.Cod_Art] = [];
      }
      _tallArtState.overlaps[row.Cod_Art].push({ prov: row.Proveedor, marca: row.marca });
    });

    // Si hay overlaps, ir al paso 3; si no, guardar directamente
    const hasOverlaps = Object.keys(_tallArtState.overlaps).length > 0;
    if (hasOverlaps) {
      tallArtStep2ToStep3();
    } else {
      // Sin overlaps, guardar directamente
      await tallArtStep3Save();
    }
  } catch (e) {
    console.error("Error detectando overlaps:", e);
    alert("Error al verificar artículos duplicados.");
  }
}

function tallArtStep2ToStep3() {
  document.getElementById("tallArtStep2").classList.add("hidden");
  document.getElementById("tallArtStep3").classList.remove("hidden");

  let html = '';
  const artsWithOverlap = Object.keys(_tallArtState.overlaps).filter(a => _tallArtState.overlaps[a].length > 0);

  artsWithOverlap.forEach(artId => {
    const art = _tallArtState.artsSelected[artId];
    const existing = _tallArtState.overlaps[artId];
    const existingStr = existing.map(e => `${e.prov}${e.marca ? ' (' + e.marca + ')' : ''}`).join(', ');

    html += `
      <div class="tall-art-overlap-item">
        <b>${artId}</b> — ${art.desc || '?'} <br>
        <small style="color:#666;">Ya existe en: ${existingStr}</small>
        <div style="margin-top:8px;">
          <label>Marca para este proveedor:</label>
          <select id="marca_${artId}" style="padding:6px; border:1px solid #cbd5e1; border-radius:4px; width:100%;">
            <option value="">— Sin marca específica</option>
            <option value="LK">LK (Loekemeyer)</option>
            <option value="CH">CH (Chef)</option>
          </select>
        </div>
      </div>
    `;
  });

  document.getElementById("tallArtOverlapList").innerHTML = html || '<div style="color:#64748b;">Sin overlaps detectados.</div>';
}

function tallArtStep3Back() {
  document.getElementById("tallArtStep3").classList.add("hidden");
  document.getElementById("tallArtStep2").classList.remove("hidden");
}

async function tallArtStep3Save() {
  const H = { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  const nombre = _tallArtState.nombre;
  const tipo = _tallArtState.tipo;
  const activo = _tallArtState.activo;

  try {
    // 1. Insertar tallerista/proveedor
    const tallRes = await fetch(SUPABASE_URL + "/rest/v1/Tall_ProvAT_PS", {
      method: "POST",
      headers: { ...H, "Content-Type": "application/json", "Prefer": "return=minimal" },
      body: JSON.stringify({
        nombre: nombre,
        activo: activo,
        rec_virg: true,
        rec_cerv: false,
        ctrl_tall: tipo === "tallerista",
        solo_grj: false,
        mostrar_grj: false,
        prov_at: tipo === "prov_at",
        interno: false,
        ps: false,
        notas: `Creado ${new Date().toLocaleDateString("es-AR")}`
      })
    });

    if (!tallRes.ok) throw new Error("No se pudo guardar tallerista");

    // 2. Insertar artículos
    const artsToInsert = [];
    Object.keys(_tallArtState.artsSelected).forEach(artId => {
      const art = _tallArtState.artsSelected[artId];
      const marca = document.getElementById(`marca_${artId}`)?.value || "";
      artsToInsert.push({
        "Proveedor": nombre,
        "Cod_Art": artId,
        "Descripcion": art.desc || "?",
        "Activo": true,
        "N_Caja": art.uni || 1,
        marca: marca || null
      });
    });

    if (artsToInsert.length) {
      const artRes = await fetch(SUPABASE_URL + "/rest/v1/Articulos%20x%20Prov%20AT", {
        method: "POST",
        headers: { ...H, "Content-Type": "application/json", "Prefer": "return=minimal" },
        body: JSON.stringify(artsToInsert)
      });

      if (!artRes.ok) throw new Error("No se pudieron guardar artículos");
    }

    alert(`✓ ${nombre} agregado con ${artsToInsert.length} artículos.`);
    tallArtClose();
    window.location.reload(); // Recargar para ver cambios
  } catch (e) {
    console.error("Error al guardar:", e);
    alert("Error al guardar: " + e.message);
  }
}

// Exposer globalmente
window.tallArtOpen = tallArtOpen;
window.tallArtClose = tallArtClose;
window.tallArtStep1Next = tallArtStep1Next;
window.tallArtStep2Back = tallArtStep2Back;
window.tallArtStep2Next = tallArtStep2Next;
window.tallArtStep2ToStep3 = tallArtStep2ToStep3;
window.tallArtStep3Back = tallArtStep3Back;
window.tallArtStep3Save = tallArtStep3Save;
window.tallArtFilterArts = tallArtFilterArts;
window.tallArtToggleArt = tallArtToggleArt;
window.tallArtLoadArts = tallArtLoadArts;
