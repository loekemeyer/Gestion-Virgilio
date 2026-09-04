-- ============================================================================
-- m³ por artículo con la "L" final resuelta · v12.75
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ============================================================================
-- QUÉ ARREGLA
-- ----------------------------------------------------------------------------
-- Un código terminado en "L" (438EL, 097L) es un artículo de LOEKEMEYER que
-- VENDE Chef: el pedido entra como NP de Chef pero la mercadería sale de la
-- góndola de Loeke. El picking y el armado ya lo resuelven desde v12.37/v12.39
-- (`pkStripL` / `pkEmpresaArt` / `pkResolveArt` en index.html), pero el **m³ no**:
-- `pwebVolumenes()` buscaba `Volumen_Articulos` por el código crudo y listo.
--
-- Medido el 2026-09-04 sobre los pedidos web: Chef trae **12 códigos con L** y
-- **9 no tienen fila de m³ con valor**. Esas NP salían con el m³ de menos —
-- marcadas `m3_parcial`, pero de menos igual, y el m³ es lo que decide la tanda.
-- Pelando la L resuelven 8 de los 9; `727EL` no tiene medida ni crudo ni pelado
-- y sigue sin m³, que es lo correcto (mejor sin dato que un 0 silencioso).
--
-- ----------------------------------------------------------------------------
-- LA REGLA: EL CRUDO MANDA, EL PELADO ES FALLBACK
-- ----------------------------------------------------------------------------
-- ⚠ Tres códigos con L **tienen fila propia** (`438EL`, `439EL`, `809EL`) y en dos
--   NO coincide con la del base: `439EL` mide 0,0561 y `439E` 0,0185 — el triple.
--   Alguna de las dos está mal, pero eso es un dato a revisar, no algo que esta
--   vista pueda decidir. Por eso el pelado **nunca pisa** una medida propia: sólo
--   entra donde no hay ninguna. Así esto no cambia ni un m³ de los que hoy salen.
--
-- Por qué una VISTA y no pelar la L en el front: la conversión es lógica de
-- negocio y va en el backend (protocolo del CLAUDE.md). El front sólo cambia de
-- endpoint — no pela nada. Y por qué no un trigger que reescriba el código: el
-- dueño lo prohibió expresamente (regla dura, §4.3 de docs/HANDOFF-PIPELINE-VENTAS.md).
-- Se resuelve en LECTURA, el código del pedido queda crudo.
--
-- `security_invoker = true`: la RLS de `Volumen_Articulos` es la que decide, no el
-- dueño de la vista. Sin eso la vista correría como `postgres` y saltearía la RLS.
-- La policy `vol_art_select_anon` es `using (true)` para anon/authenticated, así
-- que la app la lee igual que antes.
--
-- Verificado: 1.480 filas (934 propias + 546 peladas), 0 códigos duplicados, y
-- las 934 propias devuelven exactamente el mismo m³ que la tabla cruda.
-- ============================================================================

create or replace view public.vista_volumen_articulo_resuelto
with (security_invoker = true) as
  -- 1) Lo medido, tal cual. `Volumen_Articulos` tiene 2.547 filas pero sólo 934
  --    con valor: una fila sin m³ es un código dado de alta sin medir, y no debe
  --    llegar como 0 (sumaría de menos sin que nadie se entere).
  select upper(trim(v.codigo)) as codigo, v.m3, 'propio'::text as origen
    from public."Volumen_Articulos" v
   where v.m3 > 0
  union all
  -- 2) La variante con "L" de cada código medido, SÓLO si no tiene medida propia.
  --    El `~ '[0-9E]$'` es el mismo recorte que `pkStripL`: la L pega a dígito o a
  --    "E" (505L, 438EL), nunca a un sufijo de empresa (" LK" / " CH" terminan en
  --    K/H, así que no entran).
  select upper(trim(v.codigo)) || 'L', v.m3, 'pelado'::text
    from public."Volumen_Articulos" v
   where v.m3 > 0
     and upper(trim(v.codigo)) ~ '[0-9E]$'
     and not exists (
           select 1 from public."Volumen_Articulos" w
            where upper(trim(w.codigo)) = upper(trim(v.codigo)) || 'L'
              and w.m3 > 0);

grant select on public.vista_volumen_articulo_resuelto to anon, authenticated;

-- ----------------------------------------------------------------------------
-- Verificación
-- ----------------------------------------------------------------------------
-- -- Ningún código duplicado (si da > 0, el `not exists` de arriba está mal):
-- select codigo, count(*) from public.vista_volumen_articulo_resuelto
--  group by 1 having count(*) > 1;
--
-- -- Los códigos con L de los pedidos de Chef, y de dónde sacan el m³:
-- with it as (
--   select distinct upper(trim(x->>'cod_art')) cod
--     from public.vista_pedidos_web_feed f, lateral jsonb_array_elements(f.items) x
--    where f.empresa = 'ch' and upper(trim(x->>'cod_art')) ~ 'L$')
-- select it.cod, r.m3, r.origen
--   from it left join public.vista_volumen_articulo_resuelto r on r.codigo = it.cod
--  order by 1;
--
-- -- Que no se haya movido ningún m³ existente (tiene que dar 0 filas):
-- select v.codigo, v.m3, r.m3
--   from public."Volumen_Articulos" v
--   join public.vista_volumen_articulo_resuelto r on r.codigo = upper(trim(v.codigo))
--  where v.m3 > 0 and r.m3 is distinct from v.m3;

-- ----------------------------------------------------------------------------
-- PENDIENTE: el resto de los caminos de m³ (`loadVolumenes`, el panel de datos
-- faltantes) siguen leyendo `Volumen_Articulos` crudo. Hoy no molesta —las NP de
-- ISIS traen el m³ ya calculado en `PPP_Programacion_Diaria`— pero si alguno pasa
-- a calcularlo, tiene que leer esta vista.
-- ----------------------------------------------------------------------------
