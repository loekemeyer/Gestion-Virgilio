-- v22.22 (Luis, 2026-09-24) — vista_facturacion_neto_items: tres reglas nuevas, LK y Chef.
--
-- 1) EMPRESA de la NP (ya aplicado en v22.20, acá queda escrito entero): LK xxxx / 9xxxx -> lk,
--    CH xxxx / 4xxxx -> chef. Antes `np ~ '^9'` mandaba toda NP web de LK a Chef.
--
-- 2) SÚPER: el precio canónico es el de la ÚLTIMA FACTURA DE ISIS a ese cliente para ese código
--    (GV_Precio_Facturado_Cache: precio_bruto + dto_pct, lo refresca gv_refrescar_precio_facturado).
--    Luis: "carga precios en base a las ultimas facturas... ese es el precio real al final del día".
--    Sin factura previa del código, sigue la cadena de antes (lista súper, lista general).
--    Caso: Cencosud (chef 2444) no tiene un solo precio en cobranzas_precios_super; ISIS le factura
--    lista propia -16 %. Matiz (lk 4263) 55219 a 5.485. La UxC del 55219 queda A DEFINIR (Luis).
--
-- 3) 2 % WEB (regla §3.bl, LK y Chef): se aplica a cliente NO súper cuya condición de pago es de
--    cotizador (8-13, 18). "Sin Cotizador" (código 1) NO lleva 2 %.
--    La condición sale del PEDIDO si es web (lk_pedidos_match.metodo_pago, lo eligió el cliente)
--    y de la FACTURA de ISIS si la NP se tipeó en ISIS (no hay otro lado donde viva).
--    Sin dato -> 2 % (lo que se hacía hasta hoy: 93 de 103 NP de ISIS LK lo llevan).
--    Medido: las 6 NP que ISIS facturó sin 2 % (98541, 98650, 98693, LK 0067, LK 0072, LK 0097)
--    tienen condición "Sin Cotizador" en ISIS.
--
-- Rollback: sql/gv_conciliacion_empresa_np_web_v2219.sql tiene la versión anterior (sólo cambio 1).

create or replace view public.vista_facturacion_neto_items as
 WITH ent AS (
         SELECT regexp_replace(e.np, '\.0+$'::text, ''::text) AS np,
            canon_cod(e.cod_art) AS cod_canon,
            min(e.cod_art) AS cod_orig,
            regexp_replace(e.cod_cliente, '\D'::text, ''::text, 'g'::text) AS cc,
            sum(COALESCE(e.cajas_entregadas, (0)::numeric)) AS cajas_ent,
            sum(COALESCE(e.cajas_pedidas, (0)::numeric)) AS cajas_ped,
            sum(COALESCE(e.cajas_falto, (0)::numeric)) AS cajas_falto
           FROM "Entregas_Virgilio" e
          WHERE ((COALESCE(e.cajas_pedidas, (0)::numeric) > (0)::numeric) OR (COALESCE(e.cajas_entregadas, (0)::numeric) > (0)::numeric) OR (COALESCE(e.cajas_falto, (0)::numeric) > (0)::numeric))
          GROUP BY (regexp_replace(e.np, '\.0+$'::text, ''::text)), (canon_cod(e.cod_art)), (regexp_replace(e.cod_cliente, '\D'::text, ''::text, 'g'::text))
        ), npe AS (
         -- una fila por NP: empresa y condición de pago (v22.22)
         SELECT x.np, x.empresa, x.web,
            CASE WHEN x.web THEN
                   ( SELECT lp.metodo_pago
                       FROM "PPP_Web_NP" wn
                       JOIN lk_pedidos_match lp ON lp.empresa = wn.empresa AND lp.order_id = wn.order_id
                      WHERE wn.empresa = x.empresa
                        AND wn.np = NULLIF(regexp_replace(x.np, '\D'::text, ''::text, 'g'::text), ''::text)::integer
                      LIMIT 1)
                 ELSE
                   ( SELECT COALESCE(dl.condicion_venta, dc.condicion_venta)
                       FROM "GV_Cruce_FC_Asig" a
                       LEFT JOIN isis_lk.documentos dl ON x.empresa = 'lk'::text AND dl.id = a.doc_id
                       LEFT JOIN isis_ch.documentos dc ON x.empresa = 'chef'::text AND dc.id = a.doc_id
                      WHERE a.np = x.np
                      LIMIT 1)
            END AS condicion
           FROM ( SELECT d.np,
                    CASE
                        WHEN ((d.np ~* '^\s*LK'::text) OR ((d.np !~* '^\s*CH'::text) AND (d.np ~ '^9'::text))) THEN 'lk'::text
                        ELSE 'chef'::text
                    END AS empresa,
                    (d.np ~* '^\s*(LK|CH)\s*\d'::text) AS web
                   FROM ( SELECT DISTINCT ent.np FROM ent) d) x
        ), base AS (
         SELECT ent.np,
            ent.cod_canon,
            ent.cod_orig,
            ent.cc,
            ent.cajas_ent,
            ent.cajas_ped,
            ent.cajas_falto,
            npe.empresa,
            (COALESCE(npe.condicion, ''::text) ~* 'sin\s*cotiz'::text) AS sin_cotizador,
            (upper(btrim(ent.cod_orig)) ~ '[0-9E]L$'::text) AS es_art_lk,
            ( SELECT cc2.super_key
                   FROM (cobranzas_cliente_cadena cc2
                     JOIN cobranzas_super_cadena sc ON (((sc.super_key = cc2.super_key) AND (NOT sc.usa_lista_general))))
                  WHERE ((cc2.empresa =
                        CASE
                            WHEN (npe.empresa = 'lk'::text) THEN 'lk'::text
                            ELSE 'ch'::text
                        END) AND (cc2.cod_cliente = ent.cc))
                 LIMIT 1) AS super_key
           FROM (ent
             JOIN npe ON ((npe.np = ent.np)))
        ), base2 AS (
         SELECT b.np,
            b.cod_canon,
            b.cod_orig,
            b.cc,
            b.cajas_ent,
            b.cajas_ped,
            b.cajas_falto,
            b.empresa,
            b.sin_cotizador,
            b.es_art_lk,
            b.super_key,
                CASE
                    WHEN b.es_art_lk THEN 'lk'::text
                    ELSE b.empresa
                END AS empresa_precio,
                CASE
                    WHEN b.es_art_lk THEN canon_cod(regexp_replace(upper(btrim(b.cod_orig)), 'L$'::text, ''::text))
                    ELSE b.cod_canon
                END AS cod_precio
           FROM base b
        ), val AS (
         SELECT b.np,
            b.cod_canon,
            b.cod_orig,
            b.cc,
            b.cajas_ent,
            b.cajas_ped,
            b.cajas_falto,
            b.empresa,
            b.sin_cotizador,
            b.es_art_lk,
            b.super_key,
            b.empresa_precio,
            b.cod_precio,
            uxe.uxb AS uxb_r,
            -- v22.22: súper -> precio de la última factura de ISIS (canónico)
            ((b.super_key IS NOT NULL) AND (pfc.precio_bruto > (0)::numeric)) AS precio_super_fc,
                CASE
                    WHEN ((b.super_key IS NOT NULL) AND (pfc.precio_bruto > (0)::numeric)) THEN pfc.precio_bruto
                    ELSE COALESCE(ps.precio_unit, pcl.precio_unit, pc.precio_unit, pv.precio_unit, pfc.precio_neto)
                END AS precio_r,
            COALESCE(pfc.dto_pct, (0)::numeric) AS dto_fc,
            COALESCE(pc.cod, pv.cod) AS cod_lista,
            ((ps.precio_unit IS NULL) AND (pcl.precio_unit IS NOT NULL) AND pcl.es_final) AS precio_cliente_final,
            ((COALESCE(ps.precio_unit, pcl.precio_unit, pc.precio_unit, pv.precio_unit) IS NULL) AND (pfc.precio_neto IS NOT NULL)) AS precio_de_factura,
            COALESCE(cd.dto_vol, (0)::numeric) AS dto_cli
           FROM ((((((((base2 b
             LEFT JOIN clientes_dto cd ON (((cd.cod_cliente = b.cc) AND (cd.empresa = b.empresa))))
             LEFT JOIN "GV_Precios_Cliente" pcl ON (((pcl.empresa = b.empresa) AND (pcl.cod_cliente = b.cc) AND (canon_cod(pcl.cod) = b.cod_precio))))
             LEFT JOIN precios_venta_chef pc ON (((b.empresa_precio = 'chef'::text) AND (canon_cod(pc.cod) = b.cod_precio))))
             LEFT JOIN precios_venta pv ON ((canon_cod(pv.cod) = b.cod_precio)))
             LEFT JOIN gv_uxb_lk ux ON ((canon_cod(ux.cod) = b.cod_precio)))
             LEFT JOIN gv_uxb_emp uxe ON (((uxe.empresa_precio = b.empresa_precio) AND (uxe.cod_canon = b.cod_precio))))
             LEFT JOIN "GV_Precio_Facturado_Cache" pfc ON (((pfc.empresa = b.empresa) AND (pfc.cod_cliente = b.cc) AND (pfc.cod_canon = b.cod_precio))))
             LEFT JOIN cobranzas_precios_super ps ON (((b.super_key IS NOT NULL) AND (ps.super_key = b.super_key) AND (ps.nc = cob_norm_cod(b.cod_orig)))))
        ), val2 AS (
         SELECT v_1.np,
            v_1.cod_canon,
            v_1.cod_orig,
            v_1.cc,
            v_1.cajas_ent,
            v_1.cajas_ped,
            v_1.cajas_falto,
            v_1.empresa,
            v_1.sin_cotizador,
            v_1.es_art_lk,
            v_1.super_key,
            v_1.empresa_precio,
            v_1.cod_precio,
            v_1.uxb_r,
            v_1.precio_r,
            v_1.cod_lista,
            v_1.precio_cliente_final,
            v_1.precio_de_factura,
            v_1.dto_cli,
                CASE
                    WHEN v_1.precio_super_fc THEN (v_1.dto_fc / (100)::numeric)
                    WHEN ((v_1.super_key IS NOT NULL) OR v_1.precio_cliente_final OR v_1.precio_de_factura) THEN (0)::numeric
                    ELSE v_1.dto_cli
                END AS dto_r
           FROM val v_1
        )
 SELECT np,
    cc AS cod_cliente,
        CASE
            WHEN es_art_lk THEN cod_orig
            ELSE COALESCE(cod_lista, cod_orig)
        END AS cod,
    cajas_ped,
    cajas_ent,
    cajas_falto,
    uxb_r AS uxb,
    precio_r AS precio_lista,
    dto_r AS dto_vol,
        CASE
            WHEN ((precio_r IS NOT NULL) AND (precio_r > (0)::numeric)) THEN round((((cajas_ent * (COALESCE(uxb_r, 1))::numeric) * precio_r) * ((1)::numeric - dto_r)), 2)
            ELSE NULL::numeric
        END AS importe_ent,
        CASE
            WHEN ((precio_r IS NOT NULL) AND (precio_r > (0)::numeric)) THEN round((((cajas_ped * (COALESCE(uxb_r, 1))::numeric) * precio_r) * ((1)::numeric - dto_r)), 2)
            ELSE NULL::numeric
        END AS importe_ped,
    ((precio_r IS NULL) OR (precio_r <= (0)::numeric)) AS sin_precio,
    cod_canon,
        CASE
            WHEN ((super_key IS NOT NULL) OR precio_cliente_final OR precio_de_factura OR sin_cotizador) THEN 1.0
            ELSE 0.98
        END AS factor_web,
    (super_key IS NOT NULL) AS es_super
   FROM val2 v;

-- ── gv_conciliacion_lista: SIN el refresco adentro (v22.22) ─────────────────────────────────
-- El front ya llama gv_cruce_fc_asig_refrescar_si_viejo(180) antes (su propia llamada, su propio
-- catch). Hacerlo también acá sumaba hasta 8 s a la lista: con el statement_timeout de 8 s del rol
-- authenticator la pantalla quedaba en "Actualizando…". Se aplicó por replace() sobre la viva:
--   '  perform public.gv_cruce_fc_asig_refrescar_si_viejo(180);'  ->  comentario.
-- Medido después: lista 1.795 ms (antes 2.167 sin contar el refresco), vista neto 1.307 ms.

-- ── gv_conciliacion_motivo: nombra la diferencia REAL (v22.22) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.gv_conciliacion_motivo(p_np text)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- v22.22 (Luis): las diferencias REALES (armado ≠ facturado) se nombran con el código y las
  -- cajas, para que queden marcadas; antes caían en "dif. pareja" y parecían un error de cálculo.
  with c as (select * from public.gv_conciliacion_comparar(p_np)),
  q as (  -- mismo artículo, otra cantidad de cajas
    select cod, cajas_ges, cajas_isis from c
     where cajas_ges is not null and cajas_isis is not null and round(cajas_ges) <> round(cajas_isis)),
  a as (
    select count(*) filter (where motivo = 'sin_precio') as n_sin,
           count(*) filter (where motivo = 'descuento') as n_dto,
           sum(importe_ges)  filter (where importe_ges is not null and importe_isis is not null and motivo not in ('precio','descuento')
                                      and cod not in (select cod from q)) as sg,
           sum(importe_isis) filter (where importe_ges is not null and importe_isis is not null and motivo not in ('precio','descuento')
                                      and cod not in (select cod from q)) as si,
           (select string_agg(cod || ' ' || to_char(precio_ges,'FM999G999') || ' vs ' || to_char(precio_isis,'FM999G999'), ', ')
              from (select * from c where motivo = 'precio' order by cod limit 3) z) as precio_txt,
           (select string_agg(cod || ' ' || round(cajas_ges) || ' vs ' || round(cajas_isis), ', ') from (select * from q order by cod limit 4) z) as cant_txt,
           (select string_agg(cod || ' (' || round(cajas_ges) || ')', ', ')
              from (select * from c where motivo = 'no_facturado' and coalesce(cajas_ges,0) > 0 order by cod limit 4) z) as nofact_txt,
           (select string_agg(cod || ' (' || round(cajas_isis) || ')', ', ')
              from (select * from c where motivo = 'falta_en_gestion' order by cod limit 4) z) as falta_txt
      from c
  )
  select nullif(array_to_string(array_remove(array[
      case when cant_txt   is not null then 'armado ≠ facturado: ' || cant_txt end,
      case when nofact_txt is not null then 'armado y no facturado: ' || nofact_txt end,
      case when falta_txt  is not null then 'facturado y no armado: ' || falta_txt end,
      case when precio_txt is not null then 'precio: ' || precio_txt end,
      case when n_dto > 0 then 'descuento distinto' end,
      case when n_sin > 0 then n_sin || ' art. sin precio' end,
      case when si is not null and si <> 0 and abs(sg / si - 1/0.98::numeric) < 0.002
           then 'la factura aplicó 2 % web y Gestión no'
           when si is not null and si <> 0 and abs(sg / si - 0.98) < 0.002
           then 'Gestión aplicó 2 % web y la factura no'
           when si is not null and si <> 0 and abs(1 - sg / si) >= 0.005
           then 'dif. pareja ' || to_char((sg / si - 1) * 100, 'FM990.0') || '% (lista/descuento/factor)' end
    ], null), ' · '), '')
  from a;
$function$;

-- Chequeo: iguales hoy / con factura (188/207 antes, 195/207 después)
-- select count(*) filter (where abs(factura_neto-neto_actual)<=100), count(*) filter (where factura_neto is not null)
--   from public.gv_conciliacion_lista(300,0,null,null);
