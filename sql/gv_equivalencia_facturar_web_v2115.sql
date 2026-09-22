-- v21.15 (2026-09-22, Luis) — el aviso de Telegram "al facturar cambiá el código" NO veía los
-- pedidos WEB, y el match de la L estaba dado vuelta.
--
-- Es la tercera pieza del mismo agujero de la v21.12: vista_pedidos_secundarios y
-- vista_pedidos_equivalencia leían sólo GV_PPP_Base_Pedidos (ISIS) y no PPP_Web_Base. Esta
-- función no usa ninguna de las dos vistas: rehace el join por su cuenta contra la base de
-- ISIS, así que quedó con el mismo hueco.
--
-- ⚠ Y aparecio un segundo error, que es el que duele: EL MATCH PELABA LA L DE LOS DOS LADOS.
--    Equivalencias_Codigos tiene DOS filas cuyo cod_pedido TERMINA EN L:
--        438EL -> 438E   ·   439EL -> 439E
--    Pelando la L del pedido, '438EL' se compara como '438E' contra un cod_pedido '438EL':
--    no matchea NUNCA. O sea que el pelado hacia invisibles justo a las dos equivalencias que
--    existen para codigos con L. Medido: CH 0022 (438EL) y CH 0024 (439EL), las dos
--    programadas y sin facturar, no salian en ningun lado.
--    Se compara el codigo CRUDO **y** el pelado: cualquiera de los dos que matchee, avisa.
--    Nunca sobra un aviso (es "mira el codigo al facturar") y falta uno cuesta una factura mal.
--
-- ⚠ Esto NO vale para Equivalencias_Familia (vista_pedidos_secundarios): ahi cod_secundario
--    NO tiene ni una fila terminada en L (medido: 0 de N), asi que pelar es lo correcto y se
--    deja como esta.
--
-- ⚠ La consulta del aviso sale de la funcion y pasa a ser una VISTA, para poder probarla sin
--    mandar el Telegram. tg_enqueue escribe en el outbox y el cron 28 lo vacia cada minuto:
--    llamar a la funcion "para ver que da" manda el mensaje de verdad.
--
-- Impacto medido al aplicar: el aviso pasa de 0 a 2 pedidos (CH 0022 y CH 0024). La corrida
-- es el cron 14 `generar-reporte-agentes`, 0 11,15,19 UTC = 08:00 / 12:00 / 16:00 ART.

begin;

-- 1) la vista de la pantalla: el web matchea por codigo crudo O pelado
create or replace view public.vista_pedidos_equivalencia as
 SELECT DISTINCT btrim(bp.pedido) AS np, bp.articulo AS cod_pedido,
        eq.cod_real, COALESCE(eq.nota, ''::text) AS nota
   FROM "GV_PPP_Base_Pedidos" bp
   JOIN "Equivalencias_Codigos" eq
     ON regexp_replace(upper(btrim(bp.articulo)), '^0+(.)'::text, '\1'::text)
      = regexp_replace(upper(btrim(eq.cod_pedido)), '^0+(.)'::text, '\1'::text)
UNION
 SELECT DISTINCT btrim(w.np_label) AS np, w.articulo AS cod_pedido,
        eq.cod_real, COALESCE(eq.nota, ''::text) AS nota
   FROM "PPP_Web_Base" w
   JOIN "Equivalencias_Codigos" eq
     ON regexp_replace(upper(btrim(eq.cod_pedido)), '^0+(.)'::text, '\1'::text) IN (
          -- crudo: agarra 438EL -> 438E, que es la fila que existe en la tabla
          regexp_replace(upper(btrim(w.articulo)), '^0+(.)'::text, '\1'::text),
          -- pelado: agarra un 727L contra el cod_pedido 727
          regexp_replace(regexp_replace(upper(btrim(w.articulo)), '([0-9E])L$'::text, '\1'::text),
                         '^0+(.)'::text, '\1'::text))
  WHERE w.np_label IS NOT NULL AND btrim(w.np_label) <> ''::text;

alter view public.vista_pedidos_equivalencia set (security_invoker = true);

-- 2) lo que el aviso manda: programado y sin facturar. Vista para poder PROBARLO sin Telegram.
create or replace view public.gv_equivalencia_facturar_pendiente as
 SELECT 'isis'::text AS origen, btrim(bp.pedido) AS np, bp.articulo AS cod_pedido,
        eq.cod_real, COALESCE(eq.nota, ''::text) AS nota
   FROM "GV_PPP_Base_Pedidos" bp
   JOIN "GV_PPP_Programacion_Diaria" pd ON btrim(pd.np) = btrim(bp.pedido)
   JOIN "Equivalencias_Codigos" eq
     ON regexp_replace(upper(btrim(bp.articulo)), '^0+(.)'::text, '\1'::text)
      = regexp_replace(upper(btrim(eq.cod_pedido)), '^0+(.)'::text, '\1'::text)
  WHERE NOT EXISTS (SELECT 1 FROM "Facturacion_NP" f WHERE btrim(f.np) = btrim(bp.pedido))
UNION
 SELECT 'web'::text AS origen, btrim(w.np_label) AS np, w.articulo AS cod_pedido,
        eq.cod_real, COALESCE(eq.nota, ''::text) AS nota
   FROM "PPP_Web_Base" w
   -- ⚠ PPP_Web_Programacion.np es el CONTADOR (integer), no la etiqueta: se une por la clave
   --    del pedido, no por el texto de la NP.
   JOIN "PPP_Web_Programacion" wp
     ON wp.empresa = w.empresa AND wp.order_id = w.order_id AND wp.np_idx = w.np_idx
   JOIN "Equivalencias_Codigos" eq
     ON regexp_replace(upper(btrim(eq.cod_pedido)), '^0+(.)'::text, '\1'::text) IN (
          regexp_replace(upper(btrim(w.articulo)), '^0+(.)'::text, '\1'::text),
          regexp_replace(regexp_replace(upper(btrim(w.articulo)), '([0-9E])L$'::text, '\1'::text),
                         '^0+(.)'::text, '\1'::text))
  WHERE w.np_label IS NOT NULL AND btrim(w.np_label) <> ''::text
    AND NOT EXISTS (SELECT 1 FROM "Facturacion_NP" f WHERE btrim(f.np) = btrim(w.np_label));

alter view public.gv_equivalencia_facturar_pendiente set (security_invoker = true);
revoke select on public.gv_equivalencia_facturar_pendiente from anon, authenticated;

-- 3) la funcion del aviso deja de rehacer el join: lee la vista.
create or replace function public.reporte_agentes_equivalencia_facturar()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  n int; lista text; ids text;
  hoy text := to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date,'YYYY-MM-DD');
begin
  -- v21.15: ISIS **y** WEB, desde gv_equivalencia_facturar_pendiente. Antes rehacia el join
  -- contra GV_PPP_Base_Pedidos, o sea que los pedidos de la pagina no existian para el aviso.
  select count(*),
    string_agg('NP ' || np || ': facturá ' || cod_real || ' (no ' || cod_pedido || ')'
      || case when nota <> '' then ' — ' || nota else '' end, E'\n• ' order by np),
    string_agg(np || '|' || cod_pedido, ',' order by np)
  into n, lista, ids from public.gv_equivalencia_facturar_pendiente;

  if coalesce(n,0) = 0 then return; end if;

  insert into public.reporte_agentes (categoria, severidad, titulo, detalle, valor)
  values ('equivalencia_facturar','media',
    n || ' pedido(s) con código de equivalencia — al facturar cambiá el código',
    'El cliente pidió un código (ej. 029) pero se factura con el real (437E). La factura se hace afuera de la app → hay que cambiarlo a mano al facturar.',
    n);

  perform public.tg_enqueue(
    '🧾 FACTURACIÓN — cambiá el código (equivalencias):' || E'\n• ' || coalesce(lista,'-')
      || E'\n\n👉 La factura va con el código REAL, no con el del pedido.',
    'equiv_facturar_' || hoy || '_' || md5(coalesce(ids,'')));
exception when others then null;
end $function$;

-- 4) centinelas: las dos reglas que no se pueden perder
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_equivalencia_facturar_pendiente','vista','PPP_Web_Base',
  'El aviso de equivalencias al facturar tiene que mirar TAMBIEN los pedidos web, no solo los de ISIS.',
  'Luis','v21.15'),
 ('gv_equivalencia_facturar_pendiente','vista','\[0-9E\]\)L\$',
  'El codigo web se compara CRUDO y PELADO: Equivalencias_Codigos tiene cod_pedido terminados en L (438EL, 439EL) y pelando de los dos lados no matchean nunca.',
  'Luis','v21.15'),
 ('reporte_agentes_equivalencia_facturar','funcion','gv_equivalencia_facturar_pendiente',
  'La funcion del aviso lee la vista, no rehace el join contra GV_PPP_Base_Pedidos (asi no se le escapan los pedidos web otra vez).',
  'Luis','v21.15')
on conflict do nothing;

commit;
