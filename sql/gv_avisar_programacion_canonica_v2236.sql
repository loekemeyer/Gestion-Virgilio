-- v22.36 (2026-09-24, pedido de Tomas Gonzalez) — "Avisar programacion" deja de resolver el
-- telefono por CODIGO SOLO y pasa a resolverlo por (EMPRESA, CODIGO).
--
-- QUE ESTABA MAL (problema 77, ya medido en §3.dm el 13/09 y nunca corregido):
--   `vista_avisar_programacion` buscaba el telefono con
--       LEFT JOIN LATERAL (select telefono from whatsapp_clientes where cod_cliente = g.cod LIMIT 1)
--   y `whatsapp_clientes` tiene PK `cod_cliente` SIN empresa. El codigo de cliente NO es unico
--   entre LK y Chef (regla del dueno v13.76: "el cod cliente no significa nada, solo el CUIT vale"):
--   sobre un codigo compartido, ese LIMIT 1 agarra el que venga primero y el WhatsApp puede irle
--   al cliente de la OTRA empresa.
--
-- POR QUE RECIEN AHORA: el arreglo no era el join, era que faltaba el DATO. Ni esta vista ni su
-- fuente `vista_ppp_programacion_pendiente` tienen columna `empresa`. Se resuelve deduciendola de
-- las NP del grupo con `gv_empresa_de_np_texto` (LK…/CH… o >90000 = LK), que es la funcion que ya
-- usa el resto del sistema. Si las NP de un grupo no coinciden en empresa, `emp` queda NULL y no
-- se resuelve ningun telefono: ante la duda, no se manda.
--
-- LA TABLA QUE VALE es `GV_Clientes_Whatsapp` (empresa, cod_cliente) — 814 filas al 24/09.
-- `whatsapp_clientes` (963, sin empresa) queda de RESPALDO y SOLO si ese codigo no esta en la
-- canonica para NINGUNA empresa. Si esta para la otra, el numero es de ese otro cliente y acá
-- no se muestra nada.
--
-- MEDIDO el 24/09 sobre los 4 grupos vivos: antes 1 con telefono, despues 2. El que aparece es
-- `1941 Alesso Vilarino` — un codigo que existe en LK y en CH con TELEFONOS DISTINTOS
-- (LK +5492964563140 / CH +5491149923942), por eso nunca se habia podido espejar en la tabla vieja
-- y la pantalla lo mostraba sin numero.
--
-- COLUMNAS NUEVAS (van al final: `create or replace view` solo deja agregar ahi):
--   `empresa`    LK/CH del grupo, o NULL si las NP no coinciden
--   `tel_origen` 'canonica' | 'historica' | '' — para poder auditar de donde salio cada numero
-- El front no se toca: `avpLoad` pide las columnas por nombre.
--
-- ⚠ `alter view ... set (security_invoker = true)` va SIEMPRE despues del create or replace:
--    sin eso la vista corre como postgres y saltea la RLS (filtracion del 04/09, regla del repo).
--
-- CHEQUEO:
--   select * from public.gv_reglas_perdidas;                       -- vacia = las 3 reglas siguen
--   select * from public.gv_aviso_cliente_dudoso;                  -- avisos sobre codigo ambiguo
--   -- y leerla como la lee el celular, que es lo unico que prueba la RLS:
--   set local role anon; select cod, empresa, tel_cli, tel_origen from public.vista_avisar_programacion;
--
-- ROLLBACK: reaplicar la definicion anterior (la del batch 2, v10.10b) y volver a poner
--   alter view public.vista_avisar_programacion set (security_invoker = true);

create or replace view public.vista_avisar_programacion as
 WITH grupos AS (
         SELECT TRIM(BOTH FROM p.cod_cliente) AS cod,
            "left"(p.fecha_entrega, 10) AS fppp,
            max(p.razon_social) FILTER (WHERE p.razon_social IS NOT NULL AND TRIM(BOTH FROM p.razon_social) <> ''::text) AS rs,
            min("left"(p.fecha_recep, 10)) AS fped,
            array_agg(DISTINCT TRIM(BOTH FROM p.np) ORDER BY (TRIM(BOTH FROM p.np))) AS nps
           FROM vista_ppp_programacion_pendiente p
          WHERE p.fecha_entrega IS NOT NULL AND TRIM(BOTH FROM COALESCE(p.fecha_entrega, ''::text)) <> ''::text
          GROUP BY (TRIM(BOTH FROM p.cod_cliente)), ("left"(p.fecha_entrega, 10))
        ), g AS (
         SELECT gr.*,
            ( SELECT CASE WHEN count(DISTINCT public.gv_empresa_de_np_texto(n)) = 1
                          THEN CASE WHEN max(public.gv_empresa_de_np_texto(n)) = 'lk' THEN 'LK' ELSE 'CH' END
                     END
                FROM unnest(gr.nps) n) AS emp
           FROM grupos gr
        )
 SELECT (g.cod || '|'::text) || g.fppp AS grp_key,
    g.cod,
    COALESCE(g.rs, ''::text) AS rs,
    g.fppp,
    g.fped,
        CASE
            WHEN g.fped ~ '^\d{4}-\d{2}-\d{2}$'::text AND g.fppp ~ '^\d{4}-\d{2}-\d{2}$'::text THEN g.fppp::date - g.fped::date
            ELSE NULL::integer
        END AS dias,
    g.nps,
    COALESCE(tc.telefono, tv.telefono, ''::text) AS tel_cli,
    COALESCE(cv.vend, ''::text) AS vend,
    COALESCE(wv.telefono, ''::text) AS tel_vend,
    COALESCE(wv.nombre, ''::text) AS vend_nombre,
    lc.ts AS last_cli_ts,
    COALESCE(lc.quien, ''::text) AS last_cli_quien,
    COALESCE(vs.sent, false) AS vend_sent,
    g.emp AS empresa,
    CASE WHEN tc.telefono IS NOT NULL THEN 'canonica'
         WHEN tv.telefono IS NOT NULL THEN 'historica'
         ELSE '' END AS tel_origen
   FROM g
     LEFT JOIN LATERAL ( SELECT w.telefono
           FROM public."GV_Clientes_Whatsapp" w
          WHERE upper(TRIM(BOTH FROM w.empresa)) = g.emp
            AND TRIM(BOTH FROM w.cod_cliente) = g.cod
            AND NULLIF(TRIM(BOTH FROM w.telefono), ''::text) IS NOT NULL
         LIMIT 1) tc ON true
     LEFT JOIN LATERAL ( SELECT whatsapp_clientes.telefono
           FROM whatsapp_clientes
          WHERE TRIM(BOTH FROM whatsapp_clientes.cod_cliente) = g.cod
            AND NOT EXISTS ( SELECT 1 FROM public."GV_Clientes_Whatsapp" w2
                              WHERE TRIM(BOTH FROM w2.cod_cliente) = g.cod)
         LIMIT 1) tv ON tc.telefono IS NULL
     LEFT JOIN LATERAL ( SELECT TRIM(BOTH FROM clientes_vendedor.vend) AS vend
           FROM clientes_vendedor
          WHERE TRIM(BOTH FROM clientes_vendedor.cod_cliente) = g.cod
         LIMIT 1) cv ON true
     LEFT JOIN LATERAL ( SELECT whatsapp_vendedores.telefono, whatsapp_vendedores.nombre
           FROM whatsapp_vendedores
          WHERE TRIM(BOTH FROM whatsapp_vendedores.vend) = cv.vend
         LIMIT 1) wv ON cv.vend IS NOT NULL
     LEFT JOIN LATERAL ( SELECT l.ts, l.quien
           FROM envio_programacion_log l
          WHERE l.tipo = 'cliente'::text AND (TRIM(BOTH FROM l.np) = ANY (g.nps))
          ORDER BY l.ts DESC
         LIMIT 1) lc ON true
     LEFT JOIN LATERAL ( SELECT true AS sent
           FROM envio_programacion_log l
          WHERE l.tipo = 'vendedor'::text AND (TRIM(BOTH FROM l.np) = ANY (g.nps)) AND TRIM(BOTH FROM COALESCE(l.vend, ''::text)) = COALESCE(cv.vend, ''::text)
         LIMIT 1) vs ON true
  ORDER BY g.fppp, g.rs;

alter view public.vista_avisar_programacion set (security_invoker = true);
grant select on public.vista_avisar_programacion to anon, authenticated;

-- Centinelas (son inserts, no codigo). El patron sale del CODIGO, no del comentario:
--   `NOT EXISTS` NO sirve como patron, porque pg_get_viewdef lo rinde como `NOT (EXISTS (...))`.
--   Por eso el tercero vigila el alias `w2.cod_cliente`.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('vista_avisar_programacion','vista','GV_Clientes_Whatsapp',
  'El telefono de Avisar programacion sale de GV_Clientes_Whatsapp por (empresa, cod), no de whatsapp_clientes por codigo solo','Tomas Gonzalez','v22.36'),
 ('vista_avisar_programacion','vista','gv_empresa_de_np_texto',
  'La empresa del grupo se deduce de las NP; si las NP no coinciden en empresa queda NULL y no se resuelve telefono','Tomas Gonzalez','v22.36'),
 ('vista_avisar_programacion','vista','w2\.cod_cliente',
  'La tabla vieja whatsapp_clientes solo se usa de respaldo si ese codigo no esta en la canonica para NINGUNA empresa','Tomas Gonzalez','v22.36')
on conflict do nothing;
