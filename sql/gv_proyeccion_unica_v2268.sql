-- v22.68 (Luis, 25/09/2026) — UNA SOLA PROYECCIÓN para Stock, generador de OC e Importados.
-- Aplicado en vivo; este archivo es DOCUMENTACIÓN (la fuente de verdad es la base).
--
-- Cadena:  LK sales_lines -> ventas_proy_lineas (sin intercompañía, regla L) -> _fn_proy_window(_split)
--          -> sync_proyeccion_madre_virgilio -> proyeccion_madre (acá) -> gv_proyeccion_articulo
--          -> vista_stock_procesada / stocks_carga_rapida · vista_generador_oc · gv_importados_ordenes · v_importados_ordenes
--
-- Regla L: venta de Chef de un código terminado en L a Cencosud o a un cliente de Tierra del Fuego
-- cuenta para el artículo base en LK. Toda otra venta de Chef (Dorinka, Lia Rojas, con o sin L)
-- queda en Chef con el código base (437EL -> 437E de Chef).
-- Familia: cada código suma a su principal (Equivalencias_Familia, 029 -> 437E); el secundario
-- conserva su fila propia (es_secundario = true).
-- Parámetros: Stock_Config proy_meses_ventana (6), proy_piso_mejor_mes (4), proy_meses_fallback (12),
-- proy_indice_default (1.5) + Importados_Config.meses_objetivo. Se editan en OCs > ⚙ Configuraciones
-- (gv_proy_config_guardar). LK los lee por v_lk_config (lk_config_feed) en el sync diario de 06:20 ART.
-- Pendiente (Luis): excepciones por artículo; overrides de Importados quedan aparte y a la vista;
-- meses sin stock que distorsionan importados.

create or replace view public.gv_proyeccion_articulo with (security_invoker = true) as
 WITH fam AS (
         SELECT DISTINCT gv_cod_stock("Equivalencias_Familia".cod_secundario) AS sec,
            gv_cod_stock("Equivalencias_Familia".cod_principal) AS ppal
           FROM "Equivalencias_Familia"
          WHERE NULLIF(btrim("Equivalencias_Familia".cod_secundario), ''::text) IS NOT NULL AND NULLIF(btrim("Equivalencias_Familia".cod_principal), ''::text) IS NOT NULL
        ), pm AS (
         SELECT gv_cod_stock(proyeccion_madre.cod) AS cod,
            sum(COALESCE(proyeccion_madre.proy_cajas_lk, 0::numeric)) AS lk,
            sum(COALESCE(proyeccion_madre.proy_cajas_chef, 0::numeric)) AS ch
           FROM proyeccion_madre
          WHERE NULLIF(btrim(proyeccion_madre.cod), ''::text) IS NOT NULL
          GROUP BY (gv_cod_stock(proyeccion_madre.cod))
        ), aporte AS (
         SELECT COALESCE(f.ppal, pm.cod) AS cod, pm.cod AS origen, pm.lk, pm.ch
           FROM pm LEFT JOIN fam f ON f.sec = pm.cod
        )
 SELECT a.cod, sum(a.lk) AS proy_lk, sum(a.ch) AS proy_ch, sum(a.lk + a.ch) AS proy_cajas_mes,
    sum(a.lk + a.ch) FILTER (WHERE a.origen = a.cod) AS proy_propia,
    COALESCE(sum(a.lk + a.ch) FILTER (WHERE a.origen <> a.cod), 0::numeric) AS proy_familia,
    jsonb_agg(jsonb_build_object('cod', a.origen, 'lk', a.lk, 'ch', a.ch) ORDER BY a.origen) FILTER (WHERE a.origen <> a.cod) AS detalle_familia,
    false AS es_secundario, NULL::text AS principal
   FROM aporte a GROUP BY a.cod
UNION ALL
 SELECT pm.cod, pm.lk, pm.ch, pm.lk + pm.ch, pm.lk + pm.ch, 0, NULL::jsonb, true, f.ppal
   FROM pm JOIN fam f ON f.sec = pm.cod;

-- Los lectores (vista_stock_procesada, vista_generador_oc, gv_importados_ordenes,
-- v_importados_ordenes) toman: código pelado -> proy_cajas_mes · "COD LK" -> proy_lk · "COD CH" -> proy_ch.
-- vista_generador_oc: índice por defecto = Stock_Config.proy_indice_default (antes 1.5 fijo).
-- Centinela: patrón 'gv_proyeccion_articulo' en los 4 objetos (GV_Reglas_Centinela).
-- Backups: zz_backups."GV_Backup_proy_defs_20260925" (definiciones + reloptions + ACL),
--          zz_backups."GV_Proy_Antes_20260925" (proyección anterior por módulo).

CREATE OR REPLACE FUNCTION public.gv_proy_config_guardar(p jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare k text; v numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  foreach k in array array['proy_meses_ventana','proy_piso_mejor_mes','proy_meses_fallback','proy_indice_default'] loop
    if p ? k then
      v := (p->>k)::numeric;
      if v is null or v <= 0 then raise exception '% tiene que ser mayor a 0', k; end if;
      if k in ('proy_meses_ventana','proy_piso_mejor_mes','proy_meses_fallback') and v <> trunc(v) then
        raise exception '% va en meses enteros', k; end if;
      insert into "Stock_Config"(clave, valor, actualizado) values (k, v::text, now())
      on conflict (clave) do update set valor = excluded.valor, actualizado = now();
    end if;
  end loop;
  if p ? 'meses_objetivo_importados' then
    v := (p->>'meses_objetivo_importados')::numeric;
    if v is null or v <= 0 then raise exception 'meses_objetivo_importados tiene que ser mayor a 0'; end if;
    update "Importados_Config" set meses_objetivo = v, actualizado = now() where id = 1;
  end if;
  if (select valor::int from "Stock_Config" where clave='proy_piso_mejor_mes')
     > (select valor::int from "Stock_Config" where clave='proy_meses_ventana') then
    raise exception 'El piso (N.º mejor mes) no puede ser mayor que la ventana';
  end if;
  return (select jsonb_object_agg(clave, valor) from "Stock_Config" where clave like 'proy\_%')
         || jsonb_build_object('meses_objetivo_importados', (select meses_objetivo from "Importados_Config" where id=1));
end $function$;
revoke execute on function public.gv_proy_config_guardar(jsonb) from public, anon;
grant execute on function public.gv_proy_config_guardar(jsonb) to authenticated;

-- ventas_mensuales_cod: la serie del pop-up suma la familia del principal. Se aplica como parche
-- idempotente sobre pg_get_functiondef (el cuerpo lleva claves: NO se copia acá). Otra sesión la
-- pisó una vez el 25/09; desde entonces tiene centinela ('Equivalencias_Familia').
-- Loop: for c in select v_cod union select <secundarios de Equivalencias_Familia del principal>
--       -> GET fn_ventas_mensuales_virgilio(c) -> v_acc || content -> sum(cajas) group by mes.

-- Chequeo:
-- select * from public.gv_reglas_perdidas;                        -- vacía
-- select cod, proy_lk, proy_ch, detalle_familia from public.gv_proyeccion_articulo where cod in ('437E','438E');
