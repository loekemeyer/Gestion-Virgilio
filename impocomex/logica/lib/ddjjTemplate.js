// Referencia del formulario DDJJ Banco Credicoop 20320-4 (13/04/2026)
// "DECLARACIONES JURADAS COMUNICACION A 7030 Y COMPL. DEL BCRA — IMPORTACION DE BIENES"
//
// Fuente: docs/DDJJ-20320-Banco.md  (reglas de llenado dictadas por el usuario)
//
// OJO: si el banco publica una version nueva del formulario cambia el codigo del pie
// (20320-N (dd/mm/aaaa)). Ese es el chequeo duro de "se modifico el formulario".

export const FORM_ID = '20320-4';
export const FORM_FECHA = '13/04/2026';
export const FORM_PAGINAS = 6;

// Empresas del grupo que firman la DDJJ.
// caracterFirmante = lo que va en "caracter invocado" al pie de la pagina 6.
export const EMPRESAS_DDJJ = {
  CHEF: {
    id: 'CHEF',
    razonSocial: 'CHEF S.R.L.',
    alias: ['CHEF SRL', 'CHEF S.R.L.', 'CHEF S R L', 'CHEF'],
    cuit: '30-68575625-7',
    caracterFirmante: 'Socio Gerente',
  },
  TN: {
    id: 'TN',
    razonSocial: 'TN',              // TODO: completar razon social exacta
    alias: ['TN'],
    cuit: '',                        // TODO: completar CUIT
    caracterFirmante: 'Presidente',
  },
};

// Cuadro punto 4.A de pagina 5 — controlante directo (siempre el mismo).
// En la version WEB (repo publico de Gestion Virgilio) estos datos personales NO van en el codigo:
// quedan vacios y los completa la puerta Impo_Comex_web al entrar (cargarDatosPrivados, web.js).
const DATOS_CONTROLANTE = { denominacion: '', apellido: '', domicilio: '', cuit: '' };

export const CONTROLANTE = {
  ...DATOS_CONTROLANTE,
  organismoPublico: false,
  esControlante: true,
  grupoEconomico: false,
  seHizoEntrega: false,
};

// Punto 4.B pagina 5 — opcion a marcar (a/b/c/d/e). Regla del usuario: se tilda b).
export const OPCION_4B = 'b';

export const CASOS = {
  transito: {
    id: 'transito',
    label: 'Mercaderia en transito',
    desc: 'Pago parcial o total ANTES del despacho a plaza (mercaderia embarcada, sin registro de ingreso aduanero).',
    // Sin despacho => el cuadro de posiciones arancelarias es OBLIGATORIO por el propio formulario.
    posicionesObligatorias: true,
    checkboxEsperado: null,          // depende de anticipado / vista / MiPyME — a definir
    reglasDefinidas: false,
    opcionesPosibles: [
      'PAGOS ANTICIPADOS Y/O VISTA (BK SIN CONDICION MIPYME) — punto 10.10.2.2.',
      'PAGOS ANTICIPADOS DESDE CUENTA EN MONEDA EXTRANJERA — punto 10.10.2.14.',
      'PAGOS VISTA (CON CERTIFICADO MIPYME) — punto 10.10.2.1.',
      'PAGOS VISTA DESDE CUENTA EN MONEDA EXTRANJERA — punto 10.10.2.13.',
      'OPERACIONES FINANCIADAS POR ENTIDADES FINANCIERAS LOCALES — punto 10.10.2.3.',
    ],
  },
  despacho: {
    id: 'despacho',
    label: 'Mercaderia con despacho a plaza',
    desc: 'Pago parcial o total una vez que la mercaderia ya arribo y tiene registro de ingreso aduanero.',
    // El cuadro dice "completar unicamente si NO hay despacho", pero el banco lo pide igual.
    posicionesObligatorias: true,
    posicionesNota: 'El cuadro aclara "solo sin despacho a plaza", pero el banco pide completarlo igual.',
    checkboxEsperado: 'MERCADERIAS CON DESPACHO (POSTERIOR AL 12/12/2023)',
    reglasDefinidas: true,
    opcionesPosibles: [],
  },
};

// Checklist visual: lo que NO se puede leer del texto del PDF (tildes, firmas)
// y el operador tiene que confirmar mirando el documento.
export function checklistManual(caso, empresa) {
  const emp = EMPRESAS_DDJJ[empresa] || EMPRESAS_DDJJ.CHEF;
  const base = [
    { pag: 0, id: 'redaccion',  txt: 'Redaccion: cotejados a ojo los porcentajes, plazos, fechas y puntos normativos (ver tabla de valores criticos) — no cambio ni una letra' },
    { pag: 1, id: 'p1-lugar',   txt: 'Pag.1 — "Lugar: Bs.As" escrito' },
    { pag: 1, id: 'p1-fecha',   txt: 'Pag.1 — Fecha del encabezado = dia de la firma' },
    { pag: 1, id: 'p1-fecha2',  txt: 'Pag.1 — Fecha del parrafo B.C.L. = misma fecha' },
    { pag: 1, id: 'p1-importe', txt: 'Pag.1 — Importe escrito como "usd <monto>" (aclarado en dolares)' },
    { pag: 1, id: 'p1-vacios',  txt: 'Pag.1 — Puntos i) a viii) del inciso b) SIN importes (encuadra solo en a))' },
    { pag: 2, id: 'p2-ncm',     txt: 'Pag.2 — Cuadro: posicion arancelaria (NCM) cargada' },
    { pag: 2, id: 'p2-moneda',  txt: 'Pag.2 — Cuadro: moneda "usd"' },
    { pag: 2, id: 'p2-monto',   txt: 'Pag.2 — Cuadro: monto = importe a transferir' },
    { pag: 3, id: 'p3-nada',    txt: 'Pag.3 — SIN tildar nada' },
    { pag: 4, id: 'p4-nada',    txt: 'Pag.4 — SIN tildar nada' },
    { pag: 5, id: 'p5-cuadro',  txt: `Pag.5 — Cuadro 4.A: ${CONTROLANTE.denominacion} / ${CONTROLANTE.domicilio} / ${CONTROLANTE.cuit}` },
    { pag: 5, id: 'p5-ctrl',    txt: 'Pag.5 — Cuadro 4.A: tildado SOLO "Es controlante"' },
    { pag: 5, id: 'p5-b',       txt: 'Pag.5 — Punto 4.B: tildada SOLO la opcion b)' },
    { pag: 6, id: 'p6-firma',   txt: 'Pag.6 — Firma' },
    { pag: 6, id: 'p6-aclara',  txt: 'Pag.6 — Aclaracion de firma' },
    { pag: 6, id: 'p6-caracter', txt: `Pag.6 — Caracter invocado: ${emp.caracterFirmante} (${emp.razonSocial})` },
  ];
  const antesDeP3 = base.findIndex(b => b.id === 'p3-nada');
  base.splice(antesDeP3, 0, caso === 'despacho'
    ? { pag: 2, id: 'p2-desp', txt: 'Pag.2 — Tildado "MERCADERIAS CON DESPACHO (POSTERIOR AL 12/12/2023)"' }
    : { pag: 2, id: 'p2-transito', txt: 'Pag.2 — Tildada la opcion que corresponda (anticipado / vista / MiPyME / financiada) — NO "con despacho"' });
  return base;
}

// Valores finos (porcentajes, plazos, fechas y referencias normativas) que el OCR
// NO permite verificar de forma confiable. Se muestran en pantalla para cotejarlos
// a ojo contra el PDF: si el banco cambio un numero, se ve aca.
export const VALORES_CRITICOS = [
  { pag: 1, items: ['USD 100.000 (cien mil dolares)', 'punto 3.16.2.', 'Com. A 8112 / Com. A 8137', '20 dias habiles', '365 dias corridos', 'puntos 7.11.1.5. y 7.11.1.6.', '29/11/2024', '180 dias corridos', '5 dias habiles'] },
  { pag: 2, items: ['28/5/2020', 'Usd. 100,000', 'POSTERIOR AL 12/12/2023', 'punto 10.10.1.', '13/12/23', 'punto 10.6.6.', 'punto 10.10.2.2.', '30% (treinta por ciento) FOB', '80% (ochenta por ciento) FOB', 'punto 12.1.', 'punto 10.10.2.14.', '90% del valor FOB', 'punto 10.10.2.1.', '14/04/25', 'punto 10.10.2.13.'] },
  { pag: 3, items: ['puntos 10.10.2.3 I y II', '15 (quince) dias corridos', 'punto 10.10.2.9.', 'punto 10.10.2.4.', 'punto 10.10.2.5.', 'punto 10.10.2.6.', 'punto 10.10.2.7.', 'punto 10.10.2.8.', 'ANTERIORES AL 12/12/2023', 'punto 10.11.5', '5% de lo suscripto', 'Com. A 7925/7941', 'Form. 20598/1', 'punto 10.11.7.', 'Com A 7952', 'USD 500.000', 'Form. 20600/1', '13/12/23'] },
  { pag: 4, items: ['90 (noventa) dias corridos', '11/4/2025', 'punto 3.16.3.6.', 'Com. A 8108', 'puntos 3.16.3.3 y 3.16.3.4.', 'Com. A 7327', 'Com. A 7766', 'puntos 1.2.1.1. y 1.2.2.1.'] },
  { pag: 5, items: ['90 (noventa) dias corridos', '11/4/2025', 'punto 3.16.3.4.', 'punto 3.16.3.7. ap. I', 'Com. A 7772 punto 2.1.', 'punto 3.16.3.3.'] },
  { pag: 6, items: ['punto 3.16.3.7. ap. II e)', 'Com. A 7772 puntos 2.2.a) y 2.2.b)', 'punto 1.2.2.1.', 'Ley 19.359'] },
];

// Frases ancla del formulario. Se busca cada una en la pagina indicada.
// Cortas y distintivas: aguantan ruido de OCR mejor que parrafos enteros.
export const ANCLAS = [
  // ---- Pagina 1
  { pag: 1, txt: 'DECLARACIONES JURADAS COMUNICACION A 7030 Y COMPL DEL BCRA' },
  { pag: 1, txt: 'DEPARTAMENTO DE IMPORTACION - IMPORTACION DE BIENES' },
  { pag: 1, txt: 'Sres. BANCO CREDICOOP Cooperativo Ltdo' },
  { pag: 1, txt: 'en cumplimiento del punto 3.16.2. del T.O. de las normas sobre Exterior y Cambios del BCRA' },
  { pag: 1, txt: 'certificados de depositos argentinos representativos de acciones extranjeras' },
  { pag: 1, txt: 'valor superior al equivalente de USD 100.000 (cien mil dolares estadounidenses)' },
  { pag: 1, txt: 'situaciones enunciadas en los incisos i) a vi) del punto 3.16.2.' },
  { pag: 1, txt: 'punto 3. de la Com. A 8112 del BCRA y/o punto 5 de la Com. A 8137 del BCRA' },
  { pag: 1, txt: 'no transcurrio el plazo de 20 dias habiles desde su percepcion' },
  { pag: 1, txt: 'no supera el equivalente a pagar por capital e intereses en los proximos 365 dias corridos' },
  { pag: 1, txt: 'puntos 7.11.1.5. y 7.11.1.6.' },
  { pag: 1, txt: 'contempladas en el punto 3.16.3.6. iii)' },
  { pag: 1, txt: 'recibidos a partir del 29/11/2024' },
  { pag: 1, txt: 'ultimos 180 (ciento ochenta) dias corridos' },

  // ---- Pagina 2
  { pag: 2, txt: 'con posterioridad al 28/5/2020' },
  { pag: 2, txt: 'no excedo los Usd. 100,000' },
  { pag: 2, txt: 'Detalle de posiciones arancelarias (completar unicamente en el caso de mercaderia sin despacho a plaza)' },
  { pag: 2, txt: 'Posicion Arancelaria (NCM) Moneda Monto' },
  { pag: 2, txt: 'MERCADERIAS CON DESPACHO (POSTERIOR AL 12/12/2023)' },
  { pag: 2, txt: 'En el punto 10.10.1. del T.O. de las normas sobre Exterior y Cambios del BCRA' },
  { pag: 2, txt: 'pagos diferidos de importaciones de bienes con registro de ingreso aduanero a partir del 13/12/23' },
  { pag: 2, txt: 'operaciones no comprendidas en el punto 10.6.6.' },
  { pag: 2, txt: 'PAGOS ANTICIPADOS Y/O VISTA (BK SIN CONDICION MIPYME)' },
  { pag: 2, txt: 'Conforme al punto 10.10.2.2. del T.O de las normas sobre Exterior y Cambios del BCRA' },
  { pag: 2, txt: 'no supera el 30% (treinta por ciento) del valor FOB de los bienes a importar' },
  { pag: 2, txt: 'no supera el 80% (ochenta por ciento) del valor FOB de los bienes a importar' },
  { pag: 2, txt: 'no correspondan a aquellas comprendidas en el punto 12.1.' },
  { pag: 2, txt: 'PAGOS ANTICIPADOS DESDE CUENTA EN MONEDA EXTRANJERA' },
  { pag: 2, txt: 'En el punto 10.10.2.14. i) por tratarse de un pago anticipado de importacion de bienes de capital' },
  { pag: 2, txt: 'como minimo, el 90% del valor FOB total a pagar corresponde a bienes de capital' },
  { pag: 2, txt: 'PAGOS VISTA (CON CERTIFICADO MIPYME)' },
  { pag: 2, txt: 'bienes que hayan sido embarcados en origen a partir del 14/04/25' },
  { pag: 2, txt: 'NO SE PODRA DAR POR CUMPLIDO EL SEGUIMIENTO DE LA OPERACION EN SEPAIMPO' },
  { pag: 2, txt: 'PAGOS VISTA DESDE CUENTA EN MONEDA EXTRANJERA' },
  { pag: 2, txt: 'En el punto 10.10.2.13. i) por tratarse de un pago a la vista y/o diferido' },

  // ---- Pagina 3
  { pag: 3, txt: 'OPERACIONES FINANCIADAS POR ENTIDADES FINANCIERAS LOCALES' },
  { pag: 3, txt: 'se cumplen las condiciones previstas en los punto 10.10.2.3 i y 10.10.2.3 ii' },
  { pag: 3, txt: 'dentro de los 15 (quince) dias corridos desde su arribo al pais' },
  { pag: 3, txt: 'Liquidacion de cobros anticipados o prefinanciaciones de exportacion (punto 10.10.2.9' },
  { pag: 3, txt: 'Provision de medicamentos de uso critico' },
  { pag: 3, txt: 'Endeudamiento financiero con el exterior (punto 10.10.2.3. del T.O. de las normas sobre Exterior y Cambios)' },
  { pag: 3, txt: 'Financiaciones para la importacion de bienes con aplicacion de cobros de exportacion de bienes (punto 10.10.2.4.' },
  { pag: 3, txt: 'aporte de inversion extranjera (punto 10.10.2.5.' },
  { pag: 3, txt: 'produccion incremental de petroleo y/o gas natural (punto 10.10.2.6.' },
  { pag: 3, txt: 'financiadas por entidades financieras locales hasta el 12/12/23 (punto 10.10.2.7.' },
  { pag: 3, txt: 'financiadas por organismos internacionales hasta el 12/12/23 (punto 10.10.2.8.' },
  { pag: 3, txt: 'DESPACHOS ANTERIORES AL 12/12/2023' },
  { pag: 3, txt: 'Bopreal Serie 1 - pagos por hasta el 5% de lo suscripto' },
  { pag: 3, txt: 'El punto 10.11.5 del T.O de las normas sobre Exterior y Cambios del BCRA' },
  { pag: 3, txt: 'Com. A 7925/7941' },
  { pag: 3, txt: 'Acceso al Mercado de cambios por hasta el 5% de la suscripcion Bopreal 1' },
  { pag: 3, txt: 'Declaraciones Juradas a suscribir por los importadores' },
  { pag: 3, txt: 'MIPyMe - deudas menores a USD 500.000' },
  { pag: 3, txt: 'El punto 10.11.7. del T.O de las normas sobre Exterior y Cambios del BCRA' },
  { pag: 3, txt: 'Com A 7952 - Acceso al Mercado de Cambios MIPYME - Deuda hasta USD 500.000' },
  { pag: 3, txt: 'Formulario 20600/1 - ANEXO PAGO DE DEUDAS POR IMPORTACION DE BIENES Y SERVICIOS PREVIAS AL 13/12/23' },
  { pag: 3, txt: 'en los terminos del punto 3.16.3.1. y 3.16.3.2. del T.O. de las normas sobre Exterior y Cambios' },

  // ---- Pagina 4
  { pag: 4, txt: 'en los 90 (noventa) dias corridos anteriores o desde el 11/4/2025, el termino que resulte menor' },
  { pag: 4, txt: 'no he/hemos concertado ventas en el pais de titulos valores con liquidacion en moneda extranjera' },
  { pag: 4, txt: 'no he/hemos realizado canjes de titulos valores emitidos por residentes por activos externos' },
  { pag: 4, txt: 'no he/hemos realizado transferencias de titulos valores a entidades depositarias del exterior' },
  { pag: 4, txt: 'no he/hemos adquirido en el pais titulos valores emitidos por no residentes con liquidacion en pesos' },
  { pag: 4, txt: 'no he/hemos adquirido certificados de depositos argentinos representativos de acciones extranjeras' },
  { pag: 4, txt: 'no he/hemos adquirido titulos valores representativos de deuda privada emitida en jurisdiccion extranjera' },
  { pag: 4, txt: 'a no entregar fondos en moneda local u otros activos locales' },
  { pag: 4, txt: 'encuadran en los supuestos enumerados en el punto 3.16.3.6. del T.O.' },
  { pag: 4, txt: 'ni tampoco en el punto 4. de la Com. A 8108 del BCRA' },
  { pag: 4, txt: 'CAMPO OBLIGATORIO PARA PERSONAS JURIDICAS' },
  { pag: 4, txt: 'en cumplimiento de lo dispuesto en los puntos 3.16.3.3 y 3.16.3.4.' },
  { pag: 4, txt: 'conforme los terminos dispuestos por la Com. A 7327' },
  { pag: 4, txt: 'en los terminos del punto 2 de la Com. A 7766 del BCRA' },
  { pag: 4, txt: 'punto 1.2.1.1 y 1.2.2.1. de las normas de Grandes Exposiciones al Riesgo de Credito' },

  // ---- Pagina 5
  { pag: 5, txt: 'Denominacion / Apellido y nombre' },
  { pag: 5, txt: 'CUIT/CUIL Organismo Publico Es controlante Es Grupo economico' },
  { pag: 5, txt: 'Se hizo entrega de moneda local u otros activos liquidos locales' },
  { pag: 5, txt: 'marcar solo la opcion que corresponda: a, b, c, d, o e' },
  { pag: 5, txt: 'salvo aquellos directamente asociados a operaciones habituales entre residentes de adquisicion de bienes y/o servicios' },
  { pag: 5, txt: 'Punto 3.16.3.4. de las normas de Exterior y Cambios, texto s/Com. A 7766 BCRA' },
  { pag: 5, txt: 'punto 3.16.3.7. apartado i de las normas de Exterior y Cambios' },
  { pag: 5, txt: 'En este (unico) caso no sera necesario completar el cuadro de controlantes y grupo economico' },
  { pag: 5, txt: 'hemos entregado fondos en moneda local u otros activos locales liquidos' },
  { pag: 5, txt: 'Conf Punto 2.1. de la Comunicacion A 7772 del BCRA' },
  { pag: 5, txt: 'no existen personas humanas o juridicas que ejerzan una relacion de control directo sobre la que suscribe' },
  { pag: 5, txt: 'una asociacion mutual' },
  { pag: 5, txt: 'una asociacion civil' },
  { pag: 5, txt: 'una cooperativa cuyo capital social y derechos de voto se encuentran atomizados' },
  { pag: 5, txt: 'una Universidad Nacional' },

  // ---- Pagina 6
  { pag: 6, txt: 'punto 3.16.3.7. apartado ii e) de las normas de Exterior y Cambios' },
  { pag: 6, txt: 'Que cumple con lo requerido en los puntos 3.16.3.1. y 3.16.3.2. de las normas de Exterior y Cambios' },
  { pag: 6, txt: 'Punto 2.2.a) de la Comunicacion A 7772 del BCRA' },
  { pag: 6, txt: 'la DDJJ identificada como anexo 2' },
  { pag: 6, txt: 'la DDJJ identificada como anexo 3' },
  { pag: 6, txt: 'Punto 2.2.b) de la Comunicacion A 7772 del BCRA' },
  { pag: 6, txt: 'los datos consignados en el presente instrumento son correctos, completos' },
  { pag: 6, txt: 'esta declaracion ha sido confeccionada sin omitir ni falsear dato alguno' },
  { pag: 6, txt: 'punto 1.2.2.1. del T.O. de las normas sobre Grandes Exposiciones al Riesgo de Credito del BCRA' },
  { pag: 6, txt: 'certificamos al Banco Credicoop Coop. Ltdo. la genuinidad de lo manifestado' },
  { pag: 6, txt: 'son exactos y verdaderos en el marco del Regimen Penal Cambiario' },
  { pag: 6, txt: 'Regimen Penal de Cambio, del cual tenemos pleno conocimiento de sus normas y sanciones (Ley 19.359 y concordantes)' },
  { pag: 6, txt: 'verifico firmas y facultades' },
  { pag: 6, txt: 'caracter invocado por el firmante' },
  { pag: 6, txt: 'dentro de las normas de prevencion para el blanqueo y lavado de dinero' },
  { pag: 6, txt: 'este formulario debera ser presentado en tu filial' },
  { pag: 6, txt: 'importacion@bancocredicoop.coop' },
];
