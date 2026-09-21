-- v20.40 — el NUMERO del comprobante estaba en otra columna del Crystal.
--
-- Medido con el Excel de Chef del 21/09 (135 lineas, 44 clientes): la col E que el parser
-- tomaba como "comprobante" trae el TIPO (FCA, RC, NCA, FCE, AjP, FCPYM...) y el numero
-- formateado ("0006-00005511") esta en la col G. Con el tipo solo no hay nada que cruzar:
-- las 135 lineas quedaron en "sin factura parseada".
--
-- Layout del renglon de detalle, sacado de `fila` (que se guarda cruda desde la v20.35):
--   0 fecha (serial) · 1 vencimiento · 2 dias · 3 division · 4 TIPO · 5 nro numerico
--   6 NRO FORMATEADO · 7 sector · 8 cant · 9 moneda · 10 cotiz · 11 PENDIENTE · 12 importe
--
-- Con el numero, el cruce contra la factura de ISIS da 96 de 97 comprobantes reales
-- (FCA 70/71, NCA 20/20, FCE 4/4, NDE 1/1). Los que no cruzan son los que no son factura:
-- RC (recibos, 27), FCPYM (7), AjP (3), RCHR (1) — ISIS no tiene recibos parseados.

create or replace function public.gv_cuarentena_comp_key(p_fila jsonb, p_comprobante text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $function$
  select coalesce(
    case when jsonb_typeof(p_fila) = 'array' and nullif(btrim(coalesce(p_fila->>6, '')), '') is not null
         then public.gv_comprobante_key(coalesce(p_fila->>4, '') || ' ' || coalesce(p_fila->>6, ''))
    end,
    public.gv_comprobante_key(p_comprobante));
$function$;

-- La vista arma la clave con esa funcion (asi lo ya cargado se recupera sin pedir el archivo
-- otra vez) y expone el tipo y el numero. El CREATE completo esta en
-- sql/gv_cuarentena_deuda_detalle_v2036.sql; aca va lo que cambio:
--   det as (select d.*, public.gv_cuarentena_comp_key(d.fila, d.comprobante) as ck from ...)
--   left join doc on doc.empresa = d.empresa and doc.comp_key = d.ck
--   + columnas al final: tipo_comprobante, nro_comprobante
-- y despues, SIEMPRE: alter view public.gv_cuarentena_deuda_sucursal set (security_invoker = true);
