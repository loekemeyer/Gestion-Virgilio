-- v22.64 (Luis, 25/09/26): el panel «Ajustes manuales en ISIS» es SÓLO para
-- Cencosud (Chef 2444) y Tierra del Fuego (GV_Cliente_Isis motivo='tierra_del_fuego').
-- Dorinka (Chef 2686) salía porque traía 439EL y códigos sin precio en la lista de Chef.
-- Se agrega el filtro `alcance` sobre por_np; el resto de la vista, igual a la viva.
-- anon (el panel lee con la clave publishable) NO ve GV_Cliente_Isis (RLS): por eso el filtro
-- va por una función SECURITY DEFINER que devuelve sólo los códigos.
create or replace function public.gv_ajustes_isis_clientes_chef()
returns setof text language sql stable security definer set search_path = public as $f$
  select '2444'::text   -- Cencosud
  union
  select btrim(cod_isis) from "GV_Cliente_Isis" where motivo = 'tierra_del_fuego' and isis_empresa = 'chef'
$f$;
revoke all on function public.gv_ajustes_isis_clientes_chef() from public;
grant execute on function public.gv_ajustes_isis_clientes_chef() to anon, authenticated, service_role;

create or replace view public.gv_fac_ajustes_isis with (security_invoker = true) as
 WITH lk_only AS (
         SELECT canon_cod(precios_venta.cod) AS c FROM precios_venta
        EXCEPT
         SELECT canon_cod(precios_venta_chef.cod) AS canon_cod FROM precios_venta_chef
        ), ent AS (
         SELECT DISTINCT ON ((regexp_replace(e.np, '\.0+$'::text, ''::text)), (upper(btrim(e.cod_art)))) regexp_replace(e.np, '\.0+$'::text, ''::text) AS np,
            upper(btrim(e.cod_art)) AS cod_art,
            COALESCE(e.cajas_entregadas, 0::numeric) AS cajas,
            e.cod_cliente, e.tanda, e.creado
           FROM "Entregas_Virgilio" e
          WHERE e.creado >= (now() - '60 days'::interval) AND (e.cod_art ~* '^[0-9]+E?L$'::text OR gv_empresa_de_np_texto(e.np) = 'chef'::text AND (canon_cod(e.cod_art) IN ( SELECT lk_only.c FROM lk_only)))
          ORDER BY (regexp_replace(e.np, '\.0+$'::text, ''::text)), (upper(btrim(e.cod_art))), e.id DESC
        ), por_np AS (
         SELECT ent.np,
            max(ent.cod_cliente) AS cod_cliente,
            max(ent.tanda) AS tanda,
            max(ent.creado) AS armada_at,
            sum(ent.cajas) AS cajas,
            jsonb_agg(jsonb_build_object('art_ch', ent.cod_art, 'art_lk', regexp_replace(ent.cod_art, '([0-9E])L$'::text, '\1'::text), 'sin_l', ent.cod_art !~* '[0-9E]L$'::text, 'cajas', ent.cajas) ORDER BY ent.cod_art) AS articulos
           FROM ent
          WHERE ent.cajas > 0::numeric
          GROUP BY ent.np
        ), alcance AS (   -- v22.64: sólo Cencosud y Tierra del Fuego
         SELECT p.* FROM por_np p
          WHERE gv_empresa_de_np_texto(p.np) = 'lk'   -- NP LK con L = Tierra del Fuego
             OR btrim(p.cod_cliente::text) IN (SELECT public.gv_ajustes_isis_clientes_chef())  -- Cencosud + TdF (Chef)
        )
 SELECT p.np, p.cod_cliente, p.tanda, p.armada_at, p.cajas, p.articulos,
    f.razon_social, f.facturado_at,
    a1.hecho_at AS lk_neg_at, a1.legajo AS lk_neg_por,
    a2.hecho_at AS ch_pos_at, a2.legajo AS ch_pos_por,
    a1.np IS NOT NULL AND a2.np IS NOT NULL AS completo
   FROM alcance p
     LEFT JOIN "Facturacion_NP" f ON f.np = p.np
     LEFT JOIN "GV_Fac_Ajustes_ISIS" a1 ON a1.np = p.np AND a1.paso = 'lk_neg'::text
     LEFT JOIN "GV_Fac_Ajustes_ISIS" a2 ON a2.np = p.np AND a2.paso = 'ch_pos'::text;
alter view public.gv_fac_ajustes_isis set (security_invoker = true);
