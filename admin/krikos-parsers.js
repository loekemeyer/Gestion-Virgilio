// =============================================================================
// krikos-parsers.js — parsers de OC de supermercado, COPIADOS TEXTUALMENTE de
// admin/admin-supercot.js (el panel de LK). NO editar a mano.
// =============================================================================
// Lo genera scripts/gen-krikos-parsers.sh, que copia tal cual estos rangos del
// original:
//   349-401    parseNum y helpers numéricos
//   444-1660   detectSuper, splitLines, findFirstMatch, los 11 parsers por
//              cadena, extractPdfTotal y el mapa PARSERS
//   1826-1874  codVariants / findInPool (match de código con variantes)
//
// QUIÉN LO USA: la Edge Function `krikos-auto-import` del proyecto Supabase de
// LK lo importa por HTTPS desde el GitHub Pages de este repo. Es el importador
// automático de las OC de súper que llegan por Krikos: baja el PDF, lo parsea
// con ESTE código —el mismo que el panel— y carga el pedido solo.
//
// Queda AFUERA a propósito extractPdfText() (líneas 402-443 del original): usa
// pdf.js del navegador. El equivalente para Deno vive en la Edge Function,
// calcado línea por línea (mismo agrupado por Y con tolerancia de 1px, ordenado
// por X), y ya está probado contra OC reales.
//
// Verificación del parseo contra OC reales (11/09): Coto 9/9, Carrefour 14/14,
// Diarco 10/10 idénticos al pedido cargado a mano; La Anónima 17 de 18 (el 198E
// no está en el maestro de productos — problema 26 de github_repo_problemas).
// =============================================================================

  // ============================================================================
  // PARSE NUMERICO TOLERANTE
  // ============================================================================
  function parseNum(s) {
    if (s == null) return 0;
    var t = String(s).trim();
    if (!t) return 0;
    t = t.replace(/[^0-9.,\-]/g, "");
    if (!t) return 0;
    var hasDot = t.indexOf(".") !== -1;
    var hasComma = t.indexOf(",") !== -1;
    var lastDot = t.lastIndexOf(".");
    var lastComma = t.lastIndexOf(",");
    var n;
    if (hasDot && hasComma) {
      if (lastComma > lastDot) {
        n = parseFloat(t.replace(/\./g, "").replace(",", "."));
      } else {
        n = parseFloat(t.replace(/,/g, ""));
      }
    } else if (hasComma) {
      var parts = t.split(",");
      if (parts.length === 2 && parts[1].length === 3) {
        n = parseFloat(t.replace(",", "."));
      } else if (parts.length === 2 && parts[1].length <= 2) {
        n = parseFloat(t.replace(",", "."));
      } else {
        n = parseFloat(t.replace(/,/g, ""));
      }
    } else if (hasDot) {
      var pParts = t.split(".");
      // Si lo que sigue al ultimo dot son exactamente 3 digitos:
      //  - si esos 3 digitos son "000", es decimal X.000 = X (caso Coto/Diarco/Abastecedor)
      //  - si no, es miles AR ("1.260" = 1260) cuando primer parte tiene 1-3 digitos
      //  - si la primer parte tiene >=4 digitos, es decimal (3015.000 = 3015, 12345.678 = decimal)
      if (pParts.length === 2 && pParts[1].length === 3) {
        if (pParts[1] === "000" || pParts[0].length >= 4) {
          n = parseFloat(t);
        } else {
          n = parseFloat(t.replace(/\./g, ""));
        }
      } else {
        n = parseFloat(t);
      }
    } else {
      n = parseFloat(t);
    }
    return isNaN(n) ? 0 : n;
  }

  // ============================================================================
  // EXTRACCION TEXTO PDF (browser, pdf.js)
  // ============================================================================

  // ============================================================================
  // DETECCION DE CADENA
  // ============================================================================
  function detectSuper(text) {
    var t = text || "";
    if (/OrdCotoPlx|COTO\s+CICSA/i.test(t)) return "coto";
    if (/OrdDiaAPlx|SUPERMERCADO\s+DIA\s+ARG/i.test(t)) return "dia";
    if (/COMPRADOR:\s*DIARCO|OrdMayPlx/i.test(t)) return "diarco";
    if (/COMPRADOR:\s*DORINKA|OrdRmsDorinka/i.test(t)) return "dorinka";
    if (/OrdLaAnonimaPlx|S\.A\.\s*IMP\s*Y\s*EXP\.\s*DE\s*LA\s*PATAGONIA/i.test(t))
      return "laanonima";
    if (/Empresa\s+Cencosud|OrdJumboPlx|OrdDiscoPlx/i.test(t)) return "cencosud";
    if (/ALBERDI|Adm\.\s*Central:\s*Rocha\s+Sol/i.test(t)) return "alberdi";
    if (/COMPRADOR:\s*LIBERTAD|OrdLibertadAPlx/i.test(t)) return "libertad";
    if (/SUPERMERCADOS\s+EL\s+ABASTECEDOR|TECNOLAR/i.test(t))
      return "abastecedor";
    if (/OrdIncPlx|COMPRADOR:\s*INC\s*S\.?A\.?/i.test(t)) return "inc";
    // Messina: el encabezado viene con letras espaciadas "M E S S I N A   H N O S"
    if (/M\s*E\s*S\s*S\s*I\s*N\s*A\s*H\s*N\s*O\s*S/i.test(t)) return "messina";
    return null;
  }

  // ============================================================================
  // HELPERS PARA PARSERS
  // ============================================================================
  function splitLines(text) {
    return text
      .split(/\n/)
      .map(function (l) {
        return l.trim();
      })
      .filter(Boolean);
  }

  function findFirstMatch(lines, regex) {
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(regex);
      if (m) return m;
    }
    return null;
  }

  // ---- DUE DATE HELPERS ----
  // Normaliza una fecha (DD/MM/YYYY o DD.MM.YYYY o DD-MM-YYYY) a "DD/MM/YYYY".
  // Si recibe DD/MM/YY agrega "20".
  function normalizeDueDate_(s) {
    if (!s) return "";
    var m = String(s).trim().match(/(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})/);
    if (!m) return "";
    var d = m[1].length < 2 ? "0" + m[1] : m[1];
    var mo = m[2].length < 2 ? "0" + m[2] : m[2];
    var y = m[3];
    if (y.length === 2) y = (parseInt(y, 10) < 50 ? "20" : "19") + y;
    return d + "/" + mo + "/" + y;
  }

  // Suma "days" dias a una fecha DD/MM/YYYY (o variante). Devuelve DD/MM/YYYY.
  function addDaysToDate_(dateStr, days) {
    var n = normalizeDueDate_(dateStr);
    if (!n) return "";
    var p = n.split("/");
    var dt = new Date(parseInt(p[2], 10), parseInt(p[1], 10) - 1, parseInt(p[0], 10));
    if (isNaN(dt.getTime())) return "";
    dt.setDate(dt.getDate() + Number(days || 0));
    var dd = String(dt.getDate()).padStart(2, "0");
    var mm = String(dt.getMonth() + 1).padStart(2, "0");
    var yy = dt.getFullYear();
    return dd + "/" + mm + "/" + yy;
  }

  // Fecha de ENTREGA generica (para las cadenas cuyo parser no la devuelve):
  // label inline "Fecha (de) Entrega: dd/mm/yyyy" o "Fecha Prometida", y si no,
  // la fecha mas cercana a un label de entrega. Es distinta de dueDate, que es
  // el VENCIMIENTO (cuando hay que cobrar), no cuando hay que entregar.
  function findDeliveryDateGeneric_(lines) {
    var inline = findFieldRegex_(
      lines,
      /Fecha\s*(?:de\s*)?(?:Entrega|Prometida|Recepci[oó]n)\s*:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i
    );
    if (inline) return normalizeDueDate_(inline);
    var near = findDateNearLabel_(lines, /Fecha\s*(?:de\s*)?(?:Entrega|Prometida)/i, { window: 4, preferAfter: true });
    return normalizeDueDate_(near);
  }

  // Busca primer match de regex en lines y devuelve el grupo 1 capturado.
  function findFieldRegex_(lines, regex) {
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(regex);
      if (m) return m[1];
    }
    return "";
  }

  // Para PDFs Planexware donde el VALOR esta en otra linea que el LABEL.
  // dir = 1 (siguiente), -1 (anterior), 2 (2 lineas despues), etc.
  function findFieldByLabel_(lines, labelRegex, dir) {
    for (var i = 0; i < lines.length; i++) {
      if (labelRegex.test(lines[i])) {
        var idx = i + (dir || 1);
        if (idx < 0 || idx >= lines.length) continue;
        var m = String(lines[idx]).match(/(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/);
        if (m) return m[1];
      }
    }
    return "";
  }

  // Busca una fecha cerca de un label (ventana +/-N lineas), priorizando direccion.
  // opts: { window: 5, preferAfter: true }
  function findDateNearLabel_(lines, labelRegex, opts) {
    opts = opts || {};
    var window = opts.window || 5;
    var preferAfter = opts.preferAfter !== false;
    var DATE_RE = /(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/;
    for (var i = 0; i < lines.length; i++) {
      if (!labelRegex.test(lines[i])) continue;
      // Misma linea: buscar fecha despues del label
      var lm = String(lines[i]).match(labelRegex);
      if (lm) {
        var rest = String(lines[i]).substring((lm.index || 0) + lm[0].length);
        var dm = rest.match(DATE_RE);
        if (dm) return dm[1];
      }
      // Lineas alrededor en orden de proximidad
      var tries = [];
      for (var d = 1; d <= window; d++) {
        if (preferAfter) tries.push(i + d, i - d);
        else tries.push(i - d, i + d);
      }
      for (var t = 0; t < tries.length; t++) {
        var idx = tries[t];
        if (idx < 0 || idx >= lines.length) continue;
        var dm2 = String(lines[idx]).match(DATE_RE);
        if (dm2) return dm2[1];
      }
    }
    return "";
  }

  // Para PDFs estilo Planexware con N labels de fecha consecutivos seguidos
  // de N valores. Devuelve el N-esimo valor (1-based, default 3 = ultima de 3).
  // labelGroupRegex matchea cualquiera de los labels consecutivos.
  // startLabelRegex matchea solo el primero (para ubicar el inicio).
  function findNthDateAfterLabels_(lines, startLabelRegex, labelGroupRegex, n) {
    n = n || 3;
    var DATE_RE = /^\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/;
    for (var i = 0; i < lines.length; i++) {
      if (!startLabelRegex.test(lines[i])) continue;
      // contar labels consecutivos
      var labelCount = 0;
      var j = i;
      while (j < lines.length && labelGroupRegex.test(lines[j])) {
        labelCount++;
        j++;
      }
      if (labelCount < n) continue;
      // recolectar fechas en lineas siguientes
      var fechas = [];
      for (var k = j; k < lines.length && fechas.length < n + 2; k++) {
        var m = String(lines[k]).match(DATE_RE);
        if (m) fechas.push(m[1]);
        else if (lines[k].trim() !== "") {
          // si encuentra texto que no es fecha y no es vacio, romper
          if (fechas.length > 0) break;
        }
      }
      if (fechas.length >= n) return fechas[n - 1];
    }
    return "";
  }

  // Para PDFs donde N fechas vienen ANTES de los labels (caso Diarco).
  // Busca el primer label, recolecta hasta N fechas hacia atras (ignorando lineas vacias).
  function findNthDateBeforeLabel_(lines, labelRegex, n) {
    n = n || 3;
    var DATE_RE = /^\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/;
    for (var i = 0; i < lines.length; i++) {
      if (!labelRegex.test(lines[i])) continue;
      var fechas = [];
      for (var j = i - 1; j >= 0 && fechas.length < n + 2; j--) {
        var m = String(lines[j]).match(DATE_RE);
        if (m) fechas.unshift(m[1]);
        else if (lines[j].trim() !== "") {
          if (fechas.length > 0) break;
        }
      }
      if (fechas.length >= n) return fechas[n - 1];
    }
    return "";
  }

  // Strip "D" suffix from codes like "229D" -> "229" (Alberdi, La Anonima)
  function stripDSuffix(cod) {
    return String(cod || "").replace(/D$/i, "").trim();
  }

  // Coto trae los totales en una grilla: header con varias columnas y valores
  // en la siguiente linea por posicion. Tot.Imp.Neto es la 4ta columna.
  // Header: Tot.Unidades | Tot.U.Bonific. | Total Bultos | Tot.Imp.Neto | Total Cuota IVA | Total Imp.Int. | Total Imp. A Pagar
  function extractCotoTotal(text) {
    if (!text) return null;
    var lines = text.split(/\n/);
    for (var i = 0; i < lines.length; i++) {
      // Header row tiene Tot.Imp.Neto + alguna otra etiqueta tipica
      if (
        /Tot\.?\s*Imp\.?\s*Neto/i.test(lines[i]) &&
        /(Total|Pagar|Bultos|Unidades|Bonific|IVA)/i.test(lines[i])
      ) {
        for (var j = i + 1; j < Math.min(i + 5, lines.length); j++) {
          var line = (lines[j] || "").trim();
          if (!line) continue;
          var nums = line.match(/[\d.,]+/g) || [];
          if (nums.length >= 4) {
            var v = parseNum(nums[3]);
            if (v > 0) return v;
          }
          break;
        }
      }
    }
    return null;
  }

  // Extraer el total declarado en el PDF (si lo trae). Sirve para chequeo
  // interno vs el total calculado. Las patterns están ordenadas por prioridad —
  // primero los "sub totales" sin IVA / sin impuestos para matchear directo
  // con el calc.
  function extractPdfTotal(text, superKey) {
    if (!text) return null;
    // Caso especial: Coto requiere extraccion por posicion de columna
    var cotoVal = extractCotoTotal(text);
    if (cotoVal) return cotoVal;
    // Messina: "Subtotal : 4,156,139.40" (sin IVA, matchea calc directo).
    // Solo para messina, para no pisar el fallback generico "Total:" de otras cadenas.
    if (superKey === "messina") {
      var mm = text.match(/Subtotal\s*:?\s*\$?\s*([\d.,]+)/i);
      if (mm) {
        var mv = parseNum(mm[1]);
        if (mv > 0) return mv;
      }
    }
    var patterns = [
      // Abastecedor: "TOTAL O. C.: 2365860" (sub total sin IVA, matchea calc)
      /TOTAL\s*O\.?\s*C\.?:?\s*\$?\s*([\d.,]+)/i,
      // La Anonima: "Sub total sin impuestos internos: 605640" (matchea calc)
      /Sub\s*total\s*sin\s*impuestos\s*internos:?\s*\$?\s*([\d.,]+)/i,
      // Diarco, Dorinka, Libertad, INC: "Total OC: XXX"
      /Total\s*OC:?\s*\$?\s*([\d.,]+)/i,
      // Alberdi: "Total Neto:"
      /Total\s*Neto:?\s*\$?\s*([\d.,]+)/i,
      // Alberdi: "Sub Total CD01: 1,620,168.00"
      /Sub\s*Total\s*CD\d+:?\s*\$?\s*([\d.,]+)/i,
      // Fallback genérico: "Total: 593587.76"
      /\bTotal:\s*\$?\s*([\d.,]+)/,
      // Fallback Abastecedor viejo: "TOTAL:" anchor
      /^TOTAL:?\s*\$?\s*([\d.,]+)/im,
    ];
    for (var i = 0; i < patterns.length; i++) {
      var m = text.match(patterns[i]);
      if (m && m[1]) {
        var v = parseNum(m[1]);
        if (v > 0) return v;
      }
    }
    return null;
  }

  // Buscar etiqueta + valor que pueden estar en la misma linea o en lineas
  // consecutivas. labelRe debe matchear la etiqueta (con o sin valor en grupo 1).
  // valueRe matchea el valor sobre la linea siguiente cuando la primera no lo tiene.
  function findFieldML(lines, labelRe, valueRe) {
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      var m = l.match(labelRe);
      if (m) {
        if (m[1] && m[1].trim()) return m[1].trim();
        // Buscar valor en hasta 15 lineas siguientes (saltea lineas con etiquetas)
        for (var j = i + 1; j < Math.min(i + 16, lines.length); j++) {
          var v = (lines[j] || "").match(valueRe);
          if (v) return v[1].trim();
        }
      }
    }
    return "";
  }

  // ============================================================================
  // PARSERS POR CADENA
  // ============================================================================

  // ---- COTO ----
  // 2 lineas por item. Linea 1 contiene EAN. Linea 2 empieza con Fabric (5 dig)
  // y trae: Fabric Cod.Int.Prov Bultos 0 0 CxB 0 0 0 C.Neto
  function parseCoto(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      m = l.match(/L\.Dest:?\s*([A-Z0-9\-]+)/i);
      if (m && !branchId) branchId = m[1].trim();
      m = l.match(/Pedido:?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/T[ée]rminos?\s*de\s*Pago:?\s*(.+?)(?:\s*L\.|$)/i);
      if (m && !paymentTermRaw) paymentTermRaw = m[1].trim();
      m = l.match(/L\.\s*de\s*Entrega:?\s*(.+)/i);
      if (m && !branchName) branchName = m[1].trim();
    });

    // Fecha vencimiento: "Fecha Tope: DD/MM/YYYY"
    var dueDate = normalizeDueDate_(findFieldRegex_(lines, /Fecha\s+Tope:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i));

    // Items: para cada linea con EAN, leer la siguiente con datos.
    // En PDFs multi-pagina, line 2 puede estar separada por header de pagina
    // (4-5 lineas: Raz.Social, Pedido, PLU/EAN header, Fabric/Cod header). Por eso
    // buscamos hasta 10 lineas adelante saltando lineas que no matcheen el patron.
    for (var i = 0; i < lines.length; i++) {
      var line1 = lines[i];
      var eanM = line1.match(/\b(\d{13})\b/);
      if (!eanM) continue;
      var line2 = "";
      for (var j = i + 1; j <= Math.min(i + 10, lines.length - 1); j++) {
        // Si encontramos otra linea con EAN antes de la linea 2, abortar (probablemente
        // este item no tiene su linea 2 en el rango)
        if (/\b\d{13}\b/.test(lines[j])) break;
        if (/^\d{4,6}\s+\w+\s+\d/.test(lines[j])) {
          line2 = lines[j];
          break;
        }
      }
      if (!line2) continue;
      // Parsear linea 2: Fabric Cod.Int.Prov Bultos B1 B2 CxB ... C.Neto
      var tokens = line2.split(/\s+/);
      if (tokens.length < 6) continue;
      var codLk = tokens[1];
      var cajas = parseInt(tokens[2]);
      var uxb = parseInt(tokens[5]);
      // C.Neto = ultimo token con decimales
      var unitPrice = 0;
      for (var k = tokens.length - 1; k >= 0; k--) {
        var v = parseNum(tokens[k]);
        if (v > 50) {
          unitPrice = v;
          break;
        }
      }
      if (codLk && cajas > 0 && unitPrice > 0) {
        items.push({
          codLk: codLk,
          ean: eanM[1],
          description: "",
          cajas: cajas,
          uxb: uxb || 0,
          unitPrice: unitPrice,
        });
      }
    }

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
    };
  }

  // ---- DIA ----
  // 1 linea por item: DESCRIPCION EAN COD_COMPRADOR CAJAS UxB UNIDADES CAPAS PALLETS PRECIO_NETO
  // codLk = EAN[9..12]
  function parseDia(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    // Etiqueta + valor pueden estar en la misma linea o en lineas consecutivas
    for (var li = 0; li < lines.length; li++) {
      var l = lines[li];
      var nextL = lines[li + 1] || "";
      var m;
      // Lugar de entrega / Nombre — buscar patron "N - Texto" en misma linea o siguiente
      if (!branchId) {
        m = l.match(/(?:Lugar\s*de\s*entrega|Nombre):?\s*(\d+)\s*[-–]\s*(.+)/i);
        if (!m) {
          var hasLabel = /(?:Lugar\s*de\s*entrega|Nombre):?\s*$/i.test(l);
          if (hasLabel) m = nextL.match(/^(\d+)\s*[-–]\s*(.+)/);
        }
        if (m) {
          branchId = m[1].trim();
          branchName = m[2].trim();
        }
      }
      if (!orderNumber) {
        m = l.match(/N[uú]mero\s*de\s*Orden\s*de\s*Compra:?\s*(\d+)/i);
        if (!m && /N[uú]mero\s*de\s*Orden\s*de\s*Compra:?\s*$/i.test(l))
          m = nextL.match(/^(\d{4,})\s*$/);
        if (m) orderNumber = m[1].trim();
      }
      if (!paymentTermRaw) {
        m = l.match(/(?:Forma\s*de\s*[Pp]ago|Cond\.?\s*Pago):?\s*(.+)/i);
        if (m && m[1].trim()) paymentTermRaw = m[1].trim();
      }
    }

    lines.forEach(function (line) {
      var eanM = line.match(/\b(\d{13})\b/);
      if (!eanM) return;
      var ean = eanM[1];
      var idx = line.indexOf(ean);
      var after = line.substring(idx + ean.length).trim();
      var tokens = after.split(/\s+/);
      if (tokens.length < 4) return;
      var cajas = parseInt(tokens[1]);
      var uxb = parseInt(tokens[2]);
      var unitPrice = 0;
      for (var k = tokens.length - 1; k >= 0; k--) {
        var v = parseNum(tokens[k]);
        if (v > 50) {
          unitPrice = v;
          break;
        }
      }
      var codLk = ean.substring(9, 12);
      if (cajas > 0 && unitPrice > 0) {
        items.push({
          codLk: codLk,
          ean: ean,
          description: "",
          cajas: cajas,
          uxb: uxb || 0,
          unitPrice: unitPrice,
        });
      }
    });

    // Fecha vencimiento: Dia no la trae explicita. Usamos "Fecha de entrega" + 90 dias.
    var dueDate = "";
    var fechaEntrega = findFieldByLabel_(lines, /Fecha\s*de\s*entrega:?\s*$/i, 1);
    if (!fechaEntrega) {
      fechaEntrega = findFieldRegex_(lines, /Fecha\s*de\s*entrega:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i);
    }
    if (fechaEntrega) dueDate = addDaysToDate_(fechaEntrega, 90) + " (aprox)";

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
      deliveryDate: normalizeDueDate_(fechaEntrega),
    };
  }

  // ---- DIARCO ----
  // 1 linea: EAN Cod.Prod ...desc... UxB Bultos Unidades P.Unit TOTAL
  function parseDiarco(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      m = l.match(/Nombre:?\s*(\d+)\s*[-–]\s*(.+)/i);
      if (m && !branchId) {
        branchId = m[1].trim();
        branchName = m[2].trim();
      }
      m = l.match(/ORDEN\s*DE\s*COMPRA:?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/Forma\s*de\s*Pago:?\s*(.+)/i);
      if (m && m[1].trim() && !paymentTermRaw) paymentTermRaw = m[1].trim();
    });
    if (!orderNumber)
      orderNumber = findFieldML(lines, /ORDEN\s*DE\s*COMPRA:?\s*$/i, /^(\d{4,})\s*$/);
    if (!paymentTermRaw)
      paymentTermRaw = findFieldML(lines, /Forma\s*de\s*Pago:?\s*$/i, /^(\S.+)/);

    // Pattern: line with EAN and end matching uxb bultos unidades p.unit total
    // Trailing 5 numbers: uxb, bultos, unidades, p.unit (decimales), total (decimales)
    var TAIL = /(\d+)\s+(\d+)\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*$/;
    lines.forEach(function (line) {
      var eanM = line.match(/\b(\d{13})\b/);
      if (!eanM) return;
      var ean = eanM[1];
      var tail = line.match(TAIL);
      if (!tail) return;
      var uxb = parseInt(tail[1]);
      var bultos = parseInt(tail[2]);
      var unitPrice = parseNum(tail[4]);
      // codLk = primer numero despues del EAN
      var afterEan = line.substring(line.indexOf(ean) + ean.length).trim();
      var codLk = "";
      var firstTokenM = afterEan.match(/^(\S+)/);
      if (firstTokenM) codLk = stripDSuffix(firstTokenM[1]);
      if (codLk && bultos > 0 && unitPrice > 0) {
        items.push({
          codLk: codLk,
          ean: ean,
          description: "",
          cajas: bultos,
          uxb: uxb,
          unitPrice: unitPrice,
        });
      }
    });

    // Fecha vencimiento: Diarco trae 3 fechas consecutivas ANTES de los labels
    // "Fecha OC / Fecha Entrega / Fecha Cancelación". La 3ra (Cancelación) = vto.
    var dueDate = normalizeDueDate_(findNthDateBeforeLabel_(lines, /Fecha\s*OC/i, 3));
    if (!dueDate) dueDate = normalizeDueDate_(findDateNearLabel_(lines, /Fecha\s*Cancelaci[óÛo]n/i, { window: 8, preferAfter: false }));
    // Fecha de entrega: la 2da de las 3 fechas (OC / Entrega / Cancelación).
    var deliveryDate = normalizeDueDate_(findNthDateBeforeLabel_(lines, /Fecha\s*OC/i, 2));
    if (!deliveryDate) deliveryDate = normalizeDueDate_(findDateNearLabel_(lines, /Fecha\s*Entrega/i, { window: 8, preferAfter: false }));

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
      deliveryDate: deliveryDate,
    };
  }

  // ---- DORINKA (Walmart) ----
  // 1 linea: EAN SKU Ref.Prov ...desc... UxB Bultos_Pedidos Unidades_Pedidas Precio_simp Total_simp
  // Precio s/imp es por BULTO. unitPrice = Precio / UxB / (1 - volDiscount)
  function parseDorinka(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";
    var volDiscount = 0;

    lines.forEach(function (l) {
      var m;
      m = l.match(/LUGAR\s+DE\s+ENTREGA:?\s*([0-9]+)\s*[-–]?\s*(.*)/i);
      if (m && !branchId) {
        branchId = m[1].trim();
        branchName = (m[2] || "").trim();
      }
      m = l.match(/ORDEN\s*DE\s*COMPRA:?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/Condicion\s*Pago:?\s*(.+)/i);
      if (m && !paymentTermRaw) paymentTermRaw = m[1].trim();
      m = l.match(/Descuento\s+por\s+volumen.*?(\d+(?:\.\d+)?)\s*%/i);
      if (m) volDiscount = parseNum(m[1]) / 100;
    });
    if (!orderNumber)
      orderNumber = findFieldML(lines, /ORDEN\s*DE\s*COMPRA:?\s*$/i, /^(\d{4,})\s*$/);
    if (!paymentTermRaw)
      paymentTermRaw = findFieldML(lines, /Condicion\s*Pago:?\s*$/i, /^(\S.+)/);

    // Tail: UxB Bultos Unidades Precio Total (Precio y Total con decimales)
    var TAIL = /(\d+)\s+(\d+)\s+(\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s*$/;
    lines.forEach(function (line) {
      var eanM = line.match(/\b(\d{13})\b/);
      if (!eanM) return;
      var ean = eanM[1];
      var tail = line.match(TAIL);
      if (!tail) return;
      var uxb = parseInt(tail[1]);
      var bultos = parseInt(tail[2]);
      var precioBulto = parseNum(tail[4]);
      // codLk = Ref.Prov (3er token, despues de EAN y SKU)
      var afterEan = line.substring(line.indexOf(ean) + ean.length).trim();
      var tokens = afterEan.split(/\s+/);
      var codLk = tokens.length >= 2 ? tokens[1] : "";
      // unitPrice = Precio_per_bulto / UxB / (1 - volDiscount)
      var unitPrice = precioBulto;
      if (uxb > 0) unitPrice = unitPrice / uxb;
      if (volDiscount > 0 && volDiscount < 1)
        unitPrice = unitPrice / (1 - volDiscount);
      if (codLk && bultos > 0 && unitPrice > 0) {
        items.push({
          codLk: codLk,
          ean: ean,
          description: "",
          cajas: bultos,
          uxb: uxb,
          unitPrice: unitPrice,
        });
      }
    });

    // Fecha vencimiento: "Fecha Tope: DD/MM/YYYY"
    var dueDate = normalizeDueDate_(findFieldRegex_(lines, /Fecha\s+Tope:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i));

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      volDiscount: volDiscount,
      dueDate: dueDate,
    };
  }

  // ---- LA ANONIMA ----
  // 1 linea (puede dividirse en 2 si HNOS termina en linea siguiente):
  // Cod.Art Cod.Prov Desc Bto CantUM CU Cant Costo %Bonif %IVA Total
  // codLk = Cod.Prov (strip D), unitPrice = Costo / Bto
  function parseLaAnonima(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      m = l.match(/SUCURSAL\s+DESTINO\s*(\d+)\s*[-–]?\s*(.*)/i);
      if (m && !branchId) {
        branchId = m[1].trim();
        branchName = (m[2] || "").trim();
      }
      m = l.match(/N[ÚU]MERO\s*OC\s*:?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/CONDICIONES\s*DE\s*PAGO:?\s*(.+)/i);
      if (m && !paymentTermRaw) paymentTermRaw = m[1].trim();
    });
    // pdf.js junta columnas "LUGAR DE ENTREGA" y "SUCURSAL DESTINO" en una sola
    // linea. Necesito tomar la SEGUNDA "DIGITOS - NOMBRE" (SUCURSAL DESTINO).
    if (!branchId) {
      for (var li = 0; li < lines.length; li++) {
        if (/LUGAR\s+DE\s+ENTREGA.*SUCURSAL\s+DESTINO/i.test(lines[li]) ||
            /SUCURSAL\s+DESTINO\s*$/i.test(lines[li])) {
          for (var lj = li + 1; lj < Math.min(li + 6, lines.length); lj++) {
            var allMatches = lines[lj].match(/(\d+)\s*[-–]\s*[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s.]+/g);
            if (allMatches && allMatches.length) {
              // Si hay 2 (pdf.js juntando cols), tomar el SEGUNDO.
              // Si hay 1 (pdf-parse), tomar el unico (puede ser cualquiera).
              var pick = allMatches.length >= 2 ? allMatches[1] : allMatches[0];
              var pm = pick.match(/(\d+)\s*[-–]\s*(.+)/);
              if (pm) {
                branchId = pm[1].trim();
                branchName = pm[2].trim();
                break;
              }
            }
          }
          if (branchId) break;
        }
      }
    }
    if (!orderNumber)
      orderNumber = findFieldML(lines, /N[ÚU]MERO\s*OC\s*:?\s*$/i, /^(\d{4,})\s*$/);

    // Pattern tail: ... Bto CantUM CU Cant Costo %Bonif %IVA Total
    var TAIL = /(\d+)\s+(\d+)\s+CU\s+(\d+)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s*$/;
    var HEAD = /^(\d{6,})\s+([A-Z0-9]+)\s+/i;
    // Probar cada linea como-esta, y si no matchea probar concatenando con +1 o +2 lineas
    // (el formato pdf-parse split a veces deja "HNOS 24 1 CU..." en linea siguiente)
    for (var i = 0; i < lines.length; i++) {
      if (!HEAD.test(lines[i])) continue;
      var matched = false;
      for (var span = 1; span <= 3 && !matched; span++) {
        var combined = lines.slice(i, i + span).join(" ");
        var tail = combined.match(TAIL);
        var head = combined.match(HEAD);
        if (tail && head) {
          var codLk = stripDSuffix(head[2]);
          var bto = parseInt(tail[1]);
          var cant = parseInt(tail[3]);
          var costoPorBulto = parseNum(tail[4]);
          var unitPrice = bto > 0 ? costoPorBulto / bto : costoPorBulto;
          if (codLk && cant > 0 && unitPrice > 0) {
            items.push({
              codLk: codLk,
              ean: "",
              description: "",
              cajas: cant,
              uxb: bto,
              unitPrice: unitPrice,
            });
            matched = true;
          }
        }
      }
    }

    // Fecha vencimiento: label "FECHA VENCIMIENTO:" con valor cerca (priorizar antes)
    var dueDate = normalizeDueDate_(
      findDateNearLabel_(lines, /FECHA\s*VENCIMIENTO/i, { window: 5, preferAfter: false })
    );

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
    };
  }

  // ---- CENCOSUD (Jumbo/Disco/Vea) ----
  // 2 lineas por item (linea 2 = atributos, ignorar)
  // Linea 1: Articulo EAN ...desc... UxB Paq Cant.Uni CostoBruto CostoNeto IVA RecFinan DescCaja D#### Bonif%
  // codLk = EAN[9..12], unitPrice = CostoBruto
  function parseCencosud(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      // Pd.Emisor puede tener texto despues del ID; no anclar a fin de linea
      m = l.match(/Pd\.?\s*Emisor[:\s]*(.+?)\s*[-–]\s*(\d+)\b/i);
      if (m && !branchId) {
        branchId = m[2].trim();
        branchName = m[1].trim();
      }
      m = l.match(/Nro\s*OC\s+(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/Cond\.?\s*Pago[:\s]+(.+)/i);
      if (m && !paymentTermRaw) paymentTermRaw = m[1].trim();
    });

    // Tail: UxB Paq Cant.Uni CostoBruto CostoNeto IVA RecFinan DescCaja D#### Bonif%
    var TAIL = /(\d+)\s+(\d+)\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+\d+\.\d+\s+\d+\s+\d+(?:\.\d+)?\s+D\d+\s+\d+(?:\.\d+)?\s*%\s*$/;
    lines.forEach(function (line) {
      var eanM = line.match(/\b(\d{13})\b/);
      if (!eanM) return;
      var ean = eanM[1];
      var tail = line.match(TAIL);
      if (!tail) return;
      var uxb = parseInt(tail[1]);
      var paq = parseInt(tail[2]);
      var costoBruto = parseNum(tail[4]);
      var codLk = ean.substring(9, 12);
      if (paq > 0 && costoBruto > 0) {
        items.push({
          codLk: codLk,
          ean: ean,
          description: "",
          cajas: paq,
          uxb: uxb,
          unitPrice: costoBruto,
        });
      }
    });

    // Fecha vencimiento: Cencosud trae "Fh.Vencimiento" arriba sin valor inline + "Fecha Tope: DD/MM/YYYY"
    var dueDate = normalizeDueDate_(findFieldRegex_(lines, /Fecha\s+Tope:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i));
    if (!dueDate) dueDate = normalizeDueDate_(findFieldByLabel_(lines, /Fh\.?\s*Vencimiento:?\s*$/i, 1));

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
    };
  }

  // ---- ALBERDI ----
  // 1 linea (tab-separated): Codigo Cod.Prov Descripcion P.Lista Variaciones P.Unit I.I. UxB Cant UMP Total
  // codLk = Cod.Prov (strip D), unitPrice = P.Lista (coma decimal AR)
  function parseAlberdi(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      m = l.match(/Destino:?\s*([A-Z0-9]+)\s*(.*)/i);
      if (m && !branchId) {
        branchId = m[1].trim();
        branchName = (m[2] || "").trim();
      }
      m = l.match(/Pedido\s*N[º°∫]?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/Condici[óÛo]n\s*de\s*Pago:?\s*(.+)/i);
      if (m && !paymentTermRaw) paymentTermRaw = m[1].trim();
    });
    if (!orderNumber)
      orderNumber = findFieldML(lines, /Pedido\s*N[º°∫]?\s*$/i, /^(\d{4,})\s*$/);

    // Linea de item: empieza con Codigo (5d) seguido de Cod.Prov (2-5 chars alfanumericos)
    // Tipico: "21178 027 Colador Loekemeyer Acero Inox 10cm 1un 1260,000 -15.00-5.00 1,017.450 24 10,0 BTO 244,188.00"
    // Pattern: ^(\d+)\s+([A-Z0-9]+)\s+(.+?)\s+(\d[\d.,]*)\s+([\-\d.]+)\s+([\d,.]+)\s+(\d+)\s+([\d,.]+)\s+(\w+)\s+([\d,.]+)$
    var ITEM_RE = /^(\d+)\s+([A-Z0-9]+D?)\s+(.+?)\s+([\d.,]+)\s+([\-\d.]+)\s+([\d,.]+)\s+(\d+)\s+([\d,.]+)\s+\w+\s+([\d,.]+)\s*$/i;
    lines.forEach(function (line) {
      var m = line.match(ITEM_RE);
      if (!m) return;
      var codLk = stripDSuffix(m[2]);
      var pLista = parseNum(m[4]);
      var uxb = parseInt(m[7]);
      var cant = Math.floor(parseNum(m[8]));
      if (codLk && cant > 0 && pLista > 0) {
        items.push({
          codLk: codLk,
          ean: "",
          description: m[3].trim(),
          cajas: cant,
          uxb: uxb,
          unitPrice: pLista,
        });
      }
    });

    // Fecha vencimiento: Alberdi no la trae explicita. "Fecha de Entrega: DD.MM.YYYY" + 30 dias.
    var dueDate = "";
    var fechaEnt = findFieldRegex_(lines, /Fecha\s*de\s*Entrega:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i);
    if (fechaEnt) dueDate = addDaysToDate_(fechaEnt, 30) + " (aprox)";

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
      deliveryDate: normalizeDueDate_(fechaEnt),
    };
  }

  // ---- LIBERTAD ----
  // 1 linea: EAN Articulo ...desc... UxB Bultos Cantidad CostoBruto CostoNeto Descuento TOTAL
  // codLk = EAN[9..12], unitPrice = Costo Bruto
  function parseLibertad(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      // Nombre: NAME - DIGITS  (puede tener mas texto despues como "Fecha Entrega: ...")
      m = l.match(/Nombre:?\s*(.+?)\s*[-–]\s*(\d+)\b/i);
      if (m && !branchId) {
        branchName = m[1].trim();
        branchId = m[2].trim();
      }
      m = l.match(/ORDEN\s*DE\s*COMPRA:?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/Forma\s*de\s*pago:?\s*(.+)/i);
      if (m && m[1].trim() && !paymentTermRaw) paymentTermRaw = m[1].trim();
    });
    if (!orderNumber)
      orderNumber = findFieldML(lines, /ORDEN\s*DE\s*COMPRA:?\s*$/i, /^(\d{4,})\s*$/);
    if (!paymentTermRaw)
      paymentTermRaw = findFieldML(lines, /Forma\s*de\s*pago:?\s*$/i, /^(\S.+)/);

    // Tail: UxB Bultos Cantidad CostoBruto CostoNeto Descuento TOTAL
    var TAIL = /(\d+)\s+(\d+)\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*$/;
    lines.forEach(function (line) {
      var eanM = line.match(/\b(\d{13})\b/);
      if (!eanM) return;
      var ean = eanM[1];
      var tail = line.match(TAIL);
      if (!tail) return;
      var uxb = parseInt(tail[1]);
      var bultos = parseInt(tail[2]);
      var costoBruto = parseNum(tail[4]);
      var codLk = ean.substring(9, 12);
      if (bultos > 0 && costoBruto > 0) {
        items.push({
          codLk: codLk,
          ean: ean,
          description: "",
          cajas: bultos,
          uxb: uxb,
          unitPrice: costoBruto,
        });
      }
    });

    // Fecha vencimiento: 3 labels consecutivos (Fecha OC / Entrega / Vto), valores en orden.
    // Tomar el 3er valor.
    var dueDate = normalizeDueDate_(
      findNthDateAfterLabels_(
        lines,
        /Fecha\s*OC:?\s*$/i,
        /Fecha\s*(?:OC|Entrega|Vto):?\s*$/i,
        3
      )
    );
    if (!dueDate) {
      dueDate = normalizeDueDate_(
        findDateNearLabel_(lines, /Fecha\s*Vto/i, { window: 6, preferAfter: true })
      );
    }
    // Fecha de entrega: 2do valor del mismo bloque de 3 labels.
    var deliveryDate = normalizeDueDate_(
      findNthDateAfterLabels_(lines, /Fecha\s*OC:?\s*$/i, /Fecha\s*(?:OC|Entrega|Vto):?\s*$/i, 2)
    );
    if (!deliveryDate) {
      deliveryDate = normalizeDueDate_(
        findDateNearLabel_(lines, /Fecha\s*Entrega/i, { window: 6, preferAfter: true })
      );
    }

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
      deliveryDate: deliveryDate,
    };
  }

  // ---- EL ABASTECEDOR (Tecnolar) ----
  // 1 linea: Descripcion Unid PrecioRep Total EAN Bultos UxB CBruto Codigo Cod.Prov
  // codLk = Cod.Prov (ultimo token), unitPrice = C.Bruto
  function parseAbastecedor(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      m = l.match(/SUCURSAL:?\s*\[\s*([0-9]+)\s*\]\s*(.*)/i);
      if (m && !branchId) {
        branchId = m[1].trim();
        branchName = (m[2] || "").trim();
      }
      // Abastecedor: el numero puede ir ANTES del label "Orden de Compra Nro:"
      m = l.match(/Orden\s*de\s*Compra\s*Nro:?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      if (!orderNumber) {
        m = l.match(/^(\d+)\s+Orden\s*de\s*Compra\s*Nro/i);
        if (m) orderNumber = m[1].trim();
      }
      m = l.match(/Cond\.?\s*Pago:?\s*(.+)/i);
      if (m && !paymentTermRaw) paymentTermRaw = m[1].trim();
    });
    if (!orderNumber)
      orderNumber = findFieldML(
        lines,
        /Orden\s*de\s*Compra\s*Nro:?\s*$/i,
        /^(\d{4,})\s*$/,
      );

    // Hay 2 ordenes posibles segun el extractor de PDF:
    //  A) Browser pdf.js (produccion): Codigo EAN Cod.Prov Desc UxB Bultos Unid CBruto CNeto Total
    //     Ej: 150475 7795587005021 502 LOEKEMEYER ABRELATAS... 12.00 10 120.00 2545.000 2545.000 305400.0
    //  B) pdf-parse / texto column-order: ...Desc Unid CBruto Total EAN Bultos UxB CNeto Codigo Cod.Prov
    //     Ej: LOEKEMEYER ABRELATAS... 120.00 2545.000 305400.0 7795587005021 10 12.00 2545.000 150475 502
    var TAIL_BROWSER =
      /^(\d+)\s+(\d{13})\s+(\w+)\s+(.+?)\s+(\d+\.?\d*)\s+(\d+)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s*$/;
    var TAIL_PDFPARSE =
      /(\d{13})\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+)\s+(\w+)\s*$/;
    lines.forEach(function (line) {
      var mB = line.match(TAIL_BROWSER);
      if (mB) {
        var ean = mB[2];
        var codLk = mB[3];
        var uxb = parseInt(parseNum(mB[5]));
        var bultos = parseInt(mB[6]);
        var cBruto = parseNum(mB[8]);
        if (codLk && bultos > 0 && cBruto > 0) {
          items.push({
            codLk: codLk,
            ean: ean,
            description: (mB[4] || "").trim(),
            cajas: bultos,
            uxb: uxb,
            unitPrice: cBruto,
          });
        }
        return;
      }
      var mP = line.match(TAIL_PDFPARSE);
      if (mP) {
        var ean2 = mP[1];
        var bultos2 = parseInt(mP[2]);
        var uxb2 = parseInt(parseNum(mP[3]));
        var cBruto2 = parseNum(mP[4]);
        var codLk2 = mP[6];
        if (codLk2 && bultos2 > 0 && cBruto2 > 0) {
          items.push({
            codLk: codLk2,
            ean: ean2,
            description: "",
            cajas: bultos2,
            uxb: uxb2,
            unitPrice: cBruto2,
          });
        }
      }
    });

    // Fecha vencimiento: Abastecedor no la trae explicita. "Fecha Prometida" + 30 dias.
    var dueDate = "";
    var fechaProm = findFieldRegex_(lines, /Fecha\s+Prometida:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i);
    var deliveryDate = normalizeDueDate_(fechaProm); // "Fecha Prometida" = fecha de entrega
    if (!fechaProm) fechaProm = findFieldRegex_(lines, /Fecha\s+Emision:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i);
    if (fechaProm) dueDate = addDaysToDate_(fechaProm, 30) + " (aprox)";

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
      deliveryDate: deliveryDate,
    };
  }

  // ---- INC (Carrefour) ----
  // 1 linea: EAN ...desc... CJ UxB CantPed Precio Total
  // codLk = EAN[9..12], cajas = CantPed, unitPrice = Precio (per unit)
  function parseInc(text) {
    var lines = splitLines(text);
    var items = [];
    var orderNumber = "";
    var branchId = "";
    var branchName = "";
    var paymentTermRaw = "";

    lines.forEach(function (l) {
      var m;
      m = l.match(/ENTREGA:?\s*(\d+)/i);
      if (m && !branchId) branchId = m[1].trim();
      m = l.match(/Nombre:?\s*(.+)/i);
      if (m && m[1].trim() && !branchName) branchName = m[1].trim();
      m = l.match(/Nro\.?\s*OC:?\s*(\d+)/i);
      if (m && !orderNumber) orderNumber = m[1].trim();
      m = l.match(/Forma\s*de\s*pago:?\s*(.+)/i);
      if (m && m[1].trim() && !paymentTermRaw) paymentTermRaw = m[1].trim();
    });
    if (!branchId)
      branchId = findFieldML(lines, /ENTREGA:?\s*$/i, /^(\d{4,})\s*$/);
    if (!branchName)
      branchName = findFieldML(lines, /Nombre:?\s*$/i, /^(.+)$/);
    if (!orderNumber)
      orderNumber = findFieldML(lines, /Nro\.?\s*OC:?\s*$/i, /^(\d{4,})\s*$/);
    if (!paymentTermRaw)
      paymentTermRaw = findFieldML(lines, /Forma\s*de\s*pago:?\s*$/i, /^(\S.+)/);

    // Tail: CJ UxB CantPed Precio Total
    // CJ a veces aparece, a veces no. Pattern flexible: ... (CJ|UN|...) UxB CantPed Precio Total
    var TAIL = /\b(?:CJ|UN|CAJ|BLT)?\s*(\d+)\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*$/i;
    lines.forEach(function (line) {
      var eanM = line.match(/\b(\d{13})\b/);
      if (!eanM) return;
      var ean = eanM[1];
      var tail = line.match(TAIL);
      if (!tail) return;
      var uxb = parseInt(tail[1]);
      var cantPed = parseInt(tail[2]);
      var precio = parseNum(tail[3]);
      var codLk = ean.substring(9, 12);
      if (cantPed > 0 && precio > 0) {
        items.push({
          codLk: codLk,
          ean: ean,
          description: "",
          cajas: cantPed,
          uxb: uxb,
          unitPrice: precio,
        });
      }
    });

    // Fecha vencimiento: "Fecha de cancelación" — buscar fecha cerca (preferir despues)
    var dueDate = normalizeDueDate_(
      findDateNearLabel_(lines, /Fecha\s*de\s*cancelaci[óÛo]n/i, { window: 5, preferAfter: true })
    );

    // Fecha de TURNO de entrega: SOLO INC la trae en la OC. El rótulo es "Fecha entrega:"
    // (sin "de"; el valor cae unas líneas después, en el bloque de valores de Planexware).
    // Es la que Gestión usa para programar el pedido DIRECTO al día del turno (súper aparte
    // de clientes). Ojo: NO es "Fecha de cancelación" (vencimiento) ni "Fecha OC" (emisión)
    // ni "Hora de entrega". El regex exige "Fecha" delante de "entrega", así que "Hora de
    // entrega" y el "ENTREGA:" de la sucursal no matchean.
    var fechaTurno = normalizeDueDate_(
      findDateNearLabel_(lines, /Fecha\s*(?:de\s*)?entrega\s*:/i, { window: 8, preferAfter: true })
    );

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
      fechaTurno: fechaTurno,
    };
  }

  // ---- MESSINA (Hnos) ----
  // "PEDIDO DE COTIZACION". 1 linea por item (agrupada por Y):
  // COD_MESSINA DESC [DESC ADICIONAL] Caja x N Uni[d] COD_LK EAN13 UNIDADES P.UNIT %BON IMPORTE
  // El "Código Artículo Proveedor" ES el cod LK (501, 505, 960E...). La cantidad
  // viene en UNIDADES → cajas = unidades / uxb ("Caja x 6 Unid" / "Caja x 12 Uni").
  // Precio unitario POR UNIDAD (importe = unidades × precio). Subtotal sin IVA.
  function parseMessina(text) {
    var lines = splitLines(text);
    var items = [];

    var ITEM_RE = /^(\d{8,12})\s+(.+?)\s+Caja\s*x\s*(\d+)\s*Uni\w*\.?\s+(\S+)\s+(\d{13})\s+([\d.,]+)\s+([\d.,]+)\s+([\d.,]+)\s+([\d.,]+)\s*$/i;
    lines.forEach(function (line) {
      var m = line.match(ITEM_RE);
      if (!m) return;
      var uxb = parseInt(m[3], 10) || 0;
      var unidades = parseNum(m[6]);
      var cajas = uxb > 0 ? Math.round(unidades / uxb) : 0;
      var unitPrice = parseNum(m[7]);
      if (cajas > 0 && unitPrice > 0) {
        items.push({
          codLk: m[4].trim().toUpperCase(),
          ean: m[5],
          description: m[2].trim(),
          cajas: cajas,
          uxb: uxb,
          unitPrice: unitPrice,
        });
      }
    });

    // "Nº Orden : 00000-00007058" → "7058" (ultimo tramo, sin ceros a la izquierda)
    var orderNumber = "";
    var om = findFieldRegex_(lines, /N[ºo°]?\s*Orden\s*:?\s*([\d-]+)/i);
    if (om) {
      var tramo = om.split("-").pop();
      orderNumber = String(parseInt(tramo, 10) || "");
    }

    // Deposito de entrega: el label "Depósito Entrega:" cierra la linea de
    // Cond.Compra y el VALOR cae en la linea de Observaciones (misma Y).
    // Ej: "Observaciones: DP1 MADRES D PLAZA D" → branchId "DP1".
    var branchId = "";
    var branchName = "";
    for (var i = 0; i < lines.length; i++) {
      var m2 =
        lines[i].match(/Dep[oó]sito\s*Entrega:?\s*([A-Z]{2,3}\d{1,3})\s+(.{3,})/i) ||
        lines[i].match(/^Observaciones:?\s*([A-Z]{2,3}\d{1,3})\s+(.{3,})/i);
      if (m2) {
        branchId = m2[1].trim().toUpperCase();
        branchName = m2[2].trim();
        break;
      }
    }

    // Condicion de compra: "Cond.Compra : 22 CUENTA CORRIENTE. 15 DIAS FF ..."
    var paymentTermRaw = "";
    var pm = findFieldRegex_(
      lines,
      /Cond\.?\s*Compra\s*:?\s*\d*\s*([A-ZÁÉÍÓÚ][^]*?)(?:\s*Dep[oó]sito\s*Entrega.*)?$/i
    );
    if (pm) paymentTermRaw = pm.trim();

    // Vencimiento: Fecha Vigencia si viene; si no, Fecha Entrega + dias de la
    // condicion de pago ("15 DIAS FF" → entrega + 15, aprox).
    var dueDate = findFieldRegex_(
      lines,
      /Fecha\s*Vigencia\s*:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i
    );
    var entrega = findFieldRegex_(
      lines,
      /Fecha\s*Entrega\s*:?\s*(\d{1,2}[\/\.\-]\d{1,2}[\/\.\-]\d{2,4})/i
    );
    if (!dueDate) {
      var diasM = paymentTermRaw.match(/(\d+)\s*DIAS/i);
      if (entrega && diasM) dueDate = addDaysToDate_(entrega, parseInt(diasM[1], 10)) + " (aprox)";
    }

    return {
      items: items,
      orderNumber: orderNumber,
      branchId: branchId,
      branchName: branchName,
      paymentTermRaw: paymentTermRaw,
      dueDate: dueDate,
      deliveryDate: normalizeDueDate_(entrega),
    };
  }

  var PARSERS = {
    coto: parseCoto,
    dia: parseDia,
    diarco: parseDiarco,
    dorinka: parseDorinka,
    laanonima: parseLaAnonima,
    cencosud: parseCencosud,
    alberdi: parseAlberdi,
    libertad: parseLibertad,
    abastecedor: parseAbastecedor,
    inc: parseInc,
    messina: parseMessina,
  };
  //   "587"  -> ["587", "587E", "587L", "587A", "587T", "587D"]
  //   "587A" -> ["587A", "587", "587E", "587L", "587T", "587D"]
  //   "26"   -> ["26", "26E", ..., "026", "026E", ...]
  //   "229D" -> ["229D", "229", "229E", "229L", "229A", "229T"]
  var COMMON_SUFFIXES = ["", "E", "L", "A", "T", "D"];
  function codVariants(cod) {
    var c = String(cod || "").trim().toUpperCase();
    if (!c) return [];
    var seen = {};
    var out = [];
    function add(v) {
      if (!v) return;
      if (seen[v]) return;
      seen[v] = true;
      out.push(v);
    }
    add(c);
    // Si termina en sufijo single-letter conocido, sacarlo y probar variantes
    var sufM = c.match(/^(.+?)([A-Z])$/);
    var base = sufM && COMMON_SUFFIXES.indexOf(sufM[2]) >= 0 ? sufM[1] : c;
    // Variantes base con cada sufijo
    COMMON_SUFFIXES.forEach(function (s) {
      add(base + s);
    });
    // Padding a 3 digitos si numerico
    if (/^\d+$/.test(base)) {
      var padded = base.length < 3 ? ("000" + base).slice(-3) : base;
      var unpadded = base.replace(/^0+/, "") || base;
      COMMON_SUFFIXES.forEach(function (s) {
        add(padded + s);
        add(unpadded + s);
      });
    }
    return out;
  }

  function findInPool(pool, variants) {
    for (var i = 0; i < variants.length; i++) {
      var v = variants[i];
      var p = pool.find(function (x) {
        return String(x.cod || "").trim().toUpperCase() === v;
      });
      if (p) return p;
    }
    return null;
  }

  // Devuelve { product, isLoke } | null.
  // Para supers que usan products de Chef (solo Dorinka): busca en chef products.

export { parseNum, detectSuper, PARSERS, extractPdfTotal, codVariants, findInPool, splitLines };
