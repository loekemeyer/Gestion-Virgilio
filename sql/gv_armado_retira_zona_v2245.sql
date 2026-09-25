-- v22.45 (2026-09-24) — UN PEDIDO RETIRA LLEVA ZONA 'Retira' ARRIBA DEL ARMADOR
--
-- Caso: Silvano Lucas Martin (LK 4282, LK 0096) figuraba "Zona 6 · Retira 🚚 CABA" y estaba
-- METIDO en la tanda de REPARTO E64C (Zona 6 - GBA Norte). Pero lo viene a buscar el cliente
-- al depósito (direccion/barrio = 'Retira'): no va en camión.
--
-- Causa: la zona que viaja en la fila del armado es la del CLIENTE en el padrón (zona_expreso
-- = "Zona 6"), no la del PEDIDO. Un cliente de Zona 6 que ESTE pedido lo retira tiene
-- direccion/barrio 'Retira' pero zona_expreso 'Zona 6' (regla v20.74: lo decide el pedido, no
-- la ficha). Los pases de reparto de gv_ppp_web_armar_pendientes filtran por zona ~ '^Zona N';
-- como la zona era "Zona 6", el pase (a0e) —cliente nuevo aprobado, 48 h forzado— lo tomó y lo
-- programó en un camión de reparto, en vez de dejarlo como Retira.
--
-- Fix de RAÍZ (no toca datos): arriba de todo el armador se normaliza la zona de cada fila a
-- 'Retira' cuando el pedido es retira (pase a0R). Con eso:
--   · ningún pase de reparto lo agarra (zona ya no matchea '^Zona N');
--   · (a4) lo reconoce como Retira → su propia tanda si tiene día elegido, o queda en A Programar
--     (regla v20.64: un Retira sin día elegido no se programa solo).
-- Es UN cambio que arregla los 11 pases a la vez (la regla ya escrita: "la zona de un Retira es
-- Retira"), en vez de parchear pase por pase.
--
-- Medido (mismo pedido, con la normalización):
--   zona_antes = 'Zona 6 - GBA Norte'  ->  zona_despues = 'Retira'
--   reparto (~ '^Zona N'):  antes true  ->  despues false
--   retira  (~ 'retira'):   despues true
-- Y el armador corre sin error con la fila retira (0 tandas de reparto).
--
-- El front acompaña (v22.40): la fila Retira muestra "🏭 Retira" y esconde la zona/expreso.

-- 1) HELPER: un pedido es Retira si lo dice la direccion/barrio (match EXACTO ^retira$; "Retiro"
--    es un barrio de CABA y NO es Retira, regla v19.86), o la direccion del deposito, o "Exp. Retira".
create or replace function public.gv_es_retira_fila(p_barrio text, p_zona text, p_direccion text)
returns boolean
language sql immutable
as $$
  select coalesce(
       (lower(btrim(coalesce(p_barrio,'')))    ~ '^retira$')
    or (lower(btrim(coalesce(p_zona,'')))       ~ '^retira$')
    or (lower(btrim(coalesce(p_direccion,'')))  ~ '^retira$')
    or (lower(btrim(coalesce(p_direccion,'')))  ~ 'virgilio\s*2788')
    or (lower(btrim(coalesce(p_direccion,'')))  ~ '^exp\.?\s*retira')
  , false);
$$;
grant execute on function public.gv_es_retira_fila(text,text,text) to anon, authenticated, service_role;

-- 2) NORMALIZACION en gv_ppp_web_armar_pendientes. Se aplica SOBRE LA DEFINICION VIVA (varias
--    sesiones tocan esta funcion), es IDEMPOTENTE (marcador v22.45-retira) y falla con un raise
--    si el ancla no aparece (no escribe una version vieja encima).
do $do$
declare
  v_def    text;
  v_anchor text := 'create temp table _gv_tmp (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int) on commit drop;';
  v_block  text := $blk$

  -- (a0R) v22.45-retira (2026-09-24) -- un RETIRA lleva zona 'Retira', SIEMPRE. Lo decide el
  --   PEDIDO (direccion/barrio), no la ficha del padron (regla v20.74). Sin esto (a0e) y los
  --   demas pases de reparto, que filtran por zona ~ '^Zona N', lo metian en una tanda de
  --   reparto (caso Silvano LK 4282 -> E64C). Con la zona en 'Retira' lo toma (a4) si tiene dia
  --   elegido, o queda en A Programar; ningun pase de reparto lo agarra.
  p_filas := coalesce((
    select jsonb_agg(case when public.gv_es_retira_fila(x->>'barrio', x->>'zona', x->>'direccion')
                          then x || jsonb_build_object('zona','Retira') else x end)
      from jsonb_array_elements(p_filas) x), '[]'::jsonb);
$blk$;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if position('v22.45-retira' in v_def) > 0 then
    raise notice 'ya aplicado (v22.45-retira), no se toca'; return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'anchor no encontrado: la definicion viva cambio, revisar a mano';
  end if;
  execute replace(v_def, v_anchor, v_anchor || v_block);
  raise notice 'aplicado v22.45-retira';
end $do$;

-- 3) CENTINELA (patron del CODIGO, no del comentario): si alguien pisa la funcion con una copia
--    vieja y borra la normalizacion, gv_reglas_perdidas lo marca.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_web_armar_pendientes','funcion','gv_es_retira_fila',
        'Un pedido Retira lleva zona Retira arriba del armador (pase a0R): lo decide el pedido (direccion/barrio), no la ficha del padron, para que ningun pase de reparto lo agarre. Caso Silvano LK 4282 -> E64C.',
        'Thomas/Luis (regla retira v20.74/v19.52)','v22.45')
on conflict do nothing;

-- CHEQUEO
--   select * from public.gv_reglas_perdidas;   -- vacia = la regla sigue puesta
--   select (prosrc ~ 'v22\.45-retira') from pg_proc where proname='gv_ppp_web_armar_pendientes';

-- ROLLBACK (saca la normalizacion, deja la funcion como antes):
--   do $r$ declare v text; b text;
--   begin
--     v := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
--     b := substring(v from '\n\n  -- \(a0R\) v22\.45-retira.*?\$\[\]\$::jsonb\);');  -- (aprox; mejor recortar a mano)
--     -- en la practica: traer la def viva, borrar el bloque (a0R) entre '(a0R) v22.45-retira' y
--     -- el ');' de p_filas, y execute. El helper gv_es_retira_fila puede quedar (no molesta).
--   end $r$;
