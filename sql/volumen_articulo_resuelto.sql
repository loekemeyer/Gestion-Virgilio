-- ============================================================================
-- m³ por artículo con la "L" final resuelta · v12.75, regla revisada 2026-09-04
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ============================================================================
-- LA REGLA: UN CÓDIGO CON "L" ES EL MISMO ARTÍCULO QUE SU BASE
-- ----------------------------------------------------------------------------
-- `438EL` es el `438E` de Loekemeyer vendido por Chef. Es la MISMA caja: sale de
-- la misma góndola y ocupa el mismo lugar en el camión. Entonces su m³ **es el del
-- base, siempre** — no "si el base tiene", no "cuando falta el propio": siempre.
-- Decisión del dueño (2026-09-04): *"usá los valores del código pelado para todos
-- los códigos L"*.
--
-- ⚠ La primera versión de esta vista hacía lo contrario (el crudo mandaba y el base
--   sólo llenaba huecos) porque no estaba claro cuál medida era la buena. Lo está:
--   los datos muestran que las filas L son las malas.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ LA FILA "L" ES EL DATO MALO
-- ----------------------------------------------------------------------------
-- `Volumen_Articulos` tiene 156 códigos con L medidos. **Los 156 tienen su base
-- medido también**, y 102 ya coinciden exactamente. Los 54 que no, no se desvían
-- un poco: se desvían como se desvía un error de tipeo.
--
--   523L 0,0510 vs 523 0,0051   ← ×10 justo
--   531L 0,0240 vs 531 0,0024   ← ×10 justo
--   560L 0,0512 vs 560 0,0051   ← ×10 justo
--   521L 0,0024 vs 521 0,0240   ← ÷10 justo
--   366EL 0,0016 vs 366E 0,0160 ← ÷10 justo
--   539EL 0,0630 vs 539E 0,0029 · 404EL 0,0645 vs 404E 0,0065 · 580EL 0,0240 vs 580E 0,0033
--
-- Seis casos de coma corrida diez lugares y dos al revés. No son artículos que
-- midan distinto: son cargas mal tipeadas en la fila del código con L. El base es
-- el que alguien midió de verdad.
--
-- ✅ **LIMPIADAS el 2026-09-04**, por pedido del dueño. Las 54 filas se alinearon al
-- valor de su base (`update ... set m3 = m3_del_base`). No se borraron: el código
-- sigue existiendo en el catálogo, con el número bueno.
-- **Esto no cambió ningún m³ que la app calcule** —la vista ya usaba el base—; lo que
-- arregla es la TABLA CRUDA, para el que la consulte directo sin pasar por la vista.
-- Valores viejos guardados en `sql/backups/backup_volumen_articulos_codigos_L_20260904.sql`.
-- Verificado después: 0 discrepancias entre una fila con L y su base.
--
-- ----------------------------------------------------------------------------
-- QUÉ CAMBIA EN LA PRÁCTICA
-- ----------------------------------------------------------------------------
-- Sobre los pedidos web de Chef (los únicos que traen códigos con L) hay 12 de
-- estos códigos, y el cambio mueve **dos** m³ en todo el histórico:
--   439EL  0,0561 → 0,0185 · 8 cajas  → −0,30 m³
--   438EL  0,0093 → 0,0185 · 16 cajas → +0,15 m³
-- Los otros 10 ya venían del base (9 no tenían medida propia y `809EL` coincidía).
-- El resto del catálogo no se toca: verificado, 0 códigos sin L cambiaron de valor.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ UNA VISTA
-- ----------------------------------------------------------------------------
-- La conversión es lógica de negocio y va en el backend (protocolo del CLAUDE.md).
-- El front sólo cambia de endpoint: `pwebVolumenes()` lee esta vista y no pela
-- nada. Y no se reescribe el código del pedido en el back — regla dura del dueño,
-- §4.3 de docs/HANDOFF-PIPELINE-VENTAS.md: la equivalencia se resuelve en LECTURA,
-- el pedido conserva `438EL`.
--
-- `security_invoker = true`: la RLS de `Volumen_Articulos` es la que decide, no el
-- dueño de la vista. Sin eso correría como `postgres` y saltearía la RLS — que es
-- exactamente el agujero que tenía `vista_pedidos_web_feed`.
--
-- Verificado: 1.480 filas (778 propias + 702 por base), 0 códigos duplicados,
-- 0 códigos con L que no sigan a su base, 0 códigos sin L movidos.
-- ============================================================================

create or replace view public.vista_volumen_articulo_resuelto
with (security_invoker = true) as
with med as (
  -- `Volumen_Articulos` tiene 2.547 filas pero sólo 934 con valor: una fila sin m³
  -- es un código dado de alta sin medir, y no debe llegar como 0 (sumaría de menos
  -- sin que nadie se entere, que es peor que no mostrarlo).
  select upper(trim(v.codigo)) as codigo, v.m3
    from public."Volumen_Articulos" v
   where v.m3 > 0
)
-- 1) Códigos sin "L": tal cual.
select m.codigo, m.m3, 'propio'::text as origen
  from med m
 where m.codigo !~ '[0-9E]L$'
union all
-- 2) Códigos con "L" que tienen fila propia: manda el base. La medida propia queda
--    sólo por si el base no está medido (hoy no pasa nunca: los 156 tienen base).
select m.codigo,
       coalesce(b.m3, m.m3),
       case when b.m3 is not null then 'base' else 'propio' end
  from med m
  left join med b on b.codigo = regexp_replace(m.codigo, '([0-9E])L$', '\1')
 where m.codigo ~ '[0-9E]L$'
union all
-- 3) La variante con "L" de cada base medido que NO tiene fila propia — así un
--    `097L` que nunca se dio de alta igual resuelve.
--    El `[0-9E]$` es el mismo recorte que `pkStripL`: la L pega a dígito o a "E"
--    (505L, 438EL), nunca a un sufijo de empresa (" LK" / " CH" terminan en K/H).
select b.codigo || 'L', b.m3, 'base'::text
  from med b
 where b.codigo ~ '[0-9E]$'
   and not exists (select 1 from med w where w.codigo = b.codigo || 'L');

grant select on public.vista_volumen_articulo_resuelto to anon, authenticated;

-- ----------------------------------------------------------------------------
-- Verificación
-- ----------------------------------------------------------------------------
-- -- Ningún código duplicado (si da > 0, el `not exists` del brazo 3 está mal):
-- select codigo, count(*) from public.vista_volumen_articulo_resuelto
--  group by 1 having count(*) > 1;
--
-- -- Ningún código con L puede diferir de su base (tiene que dar 0):
-- select count(*) from public.vista_volumen_articulo_resuelto r
--   join public.vista_volumen_articulo_resuelto b
--     on b.codigo = regexp_replace(r.codigo, '([0-9E])L$', '\1')
--  where r.codigo ~ '[0-9E]L$' and r.m3 is distinct from b.m3;
--
-- -- Ningún código SIN L cambió respecto de la tabla cruda (tiene que dar 0):
-- select count(*) from public."Volumen_Articulos" v
--   join public.vista_volumen_articulo_resuelto r on r.codigo = upper(trim(v.codigo))
--  where v.m3 > 0 and upper(trim(v.codigo)) !~ '[0-9E]L$' and r.m3 is distinct from v.m3;
--
-- -- Filas L cuya medida propia contradiga al base (tiene que dar 0 desde la limpieza):
-- with med as (select upper(trim(codigo)) codigo, m3 from public."Volumen_Articulos" where m3 > 0)
-- select m.codigo, m.m3 as m3_fila_L, b.codigo as base, b.m3 as m3_base,
--        round(m.m3 / b.m3, 2) as veces
--   from med m join med b on b.codigo = regexp_replace(m.codigo, '([0-9E])L$', '\1')
--  where m.codigo ~ '[0-9E]L$' and m.m3 <> b.m3
--  order by abs(ln(m.m3 / b.m3)) desc;

-- ----------------------------------------------------------------------------
-- PENDIENTE: el resto de los caminos de m³ (`loadVolumenes`, el panel de datos
-- faltantes) siguen leyendo `Volumen_Articulos` crudo. Hoy no molesta —las NP de
-- ISIS traen el m³ ya calculado en `PPP_Programacion_Diaria`— pero si alguno pasa
-- a calcularlo, tiene que leer esta vista.
-- ----------------------------------------------------------------------------
