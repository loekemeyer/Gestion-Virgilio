#!/usr/bin/env node
// Candado de la regla de la L (Luis, 2026-09-21): "la L solo indica que son codigos de LK
// pero sin la L (702EL = 702E de LK)". Se explico varias veces y se volvio a leer mal, asi
// que el bloque del CLAUDE.md que lo dice no se puede borrar ni diluir sin que esto falle.
const fs = require("fs");
const path = require("path");

const md = fs.readFileSync(path.join(__dirname, "..", "CLAUDE.md"), "utf8");

const exigidos = [
  ['el bloque grande de la L', 'LA "L" = EL MISMO NÚMERO, PERO DE LOEKEMEYER'],
  ['el ejemplo de Luis',       '702EL'],
  ['la cita textual',          'la L solo indica que son códigos de'],
  ['el bloque de la denotación', 'LA «L» NO ES UN CÓDIGO — ES UNA DENOTACIÓN'],
  ['la regla de no sacarla',   'NO hay que "limpiar" la L'],
];

const faltan = exigidos.filter(([, txt]) => !md.includes(txt));
if (faltan.length) {
  console.error("regla-L: FALLA — al CLAUDE.md le falta:");
  faltan.forEach(([que, txt]) => console.error(`  - ${que}  (buscaba: ${txt})`));
  process.exit(1);
}

// El bloque grande va ARRIBA: si queda enterrado a mitad del archivo, nadie lo lee.
const pos = md.indexOf('LA "L" = EL MISMO NÚMERO');
if (pos > 2000) {
  console.error(`regla-L: FALLA — el bloque de la L quedo en el caracter ${pos}; va arriba de todo.`);
  process.exit(1);
}

console.log("regla-L: OK — la regla de la L esta arriba del CLAUDE.md y completa.");
