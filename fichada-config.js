// Configuracion del sistema de fichada con QR rotativo.
// El QR redirige a fichada.html con un token TOTP. El ingreso se
// registra en Supabase (tabla Fichadas_Virgilio). Las salidas y el
// almuerzo se reportan desde la app principal de Virgilio con los
// botones "Pare Comida" (PC) y "Finalizar Jornada" (FJ).
//
// Editar SOLO los valores marcados con TODO antes de desplegar.
window.FICHADA_CONFIG = {
  // ===== Supabase =====
  // Esta URL y key tienen que ser las mismas que usa index.html / sw.js.
  // La publishable key tiene permisos INSERT (RLS) sobre Fichadas_Virgilio
  // y SELECT sobre Empleados.
  supabaseUrl: "https://hrxfctzncixxqmpfhskv.supabase.co",
  supabaseKey: "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT",

  // ===== Google Form bridge (mirror del sheet de fichadas Esnaola) =====
  // En paralelo al insert en Supabase, mandamos la fichada como
  // "Entrada" al Form. El sheet conectado al Form recibe la fila auto:
  // https://docs.google.com/spreadsheets/d/19jF76wpbkVi7qBYNQ6BeZe1w5skJojljLJZttaOBD8g/edit?gid=1495479968
  // Si el Form falla (red, Google caido, etc) NO bloqueamos la fichada
  // — Supabase es la fuente de verdad, el Form es solo mirror legacy.
  formActionUrl:
    "https://docs.google.com/forms/d/e/1FAIpQLScjwID9-oLoXfay0BKMGsfZL-prFwZI5SDFKs8d-i1MllkjfA/formResponse",
  // ID del campo "Evento". Como el QR es solo para ingreso, siempre
  // mandamos "Entrada" como valor.
  eventoEntryId: "entry.1604904801",
  // El Form esta configurado con "Recolectar correos -> Entrada del
  // responder", asi que el email va en el campo POST especial "emailAddress".
  // Si en el futuro cambia a pregunta normal de respuesta corta, hay
  // que poner aca el entry.X y cambiar el modo a "entry".
  emailMode: "emailAddress",

  // ===== TOTP / QR =====
  // Secreto compartido entre index.html (genera el QR) y fichada.html
  // (verifica el token). ADVERTENCIA: este valor queda visible en el JS
  // publico de ambas paginas. Es disuasivo, no barrera criptografica.
  // Si lo cambias, las tokens generadas antes del deploy quedan
  // invalidadas durante la ventana de rotacion (30s default).
  hmacSecret: "5gzwxCtxT55dVUKV6y1nUpIsy3OnbpOaaha7DyLAlcGXNFzuBJHsRHTSklOSNj7",

  // Duracion de cada token en segundos. Mas corto = mas seguro, pero
  // exige relojes mas sincronizados entre TV y celulares.
  tokenPeriodSec: 30,

  // Cuantas ventanas hacia atras/adelante se aceptan (cubre desfasaje
  // chico de reloj). 1 = se acepta el bucket actual, el anterior y el
  // siguiente.
  tokenTolerance: 1,
};
