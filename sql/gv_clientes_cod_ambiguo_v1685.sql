-- =====================================================================================
-- COD_CLIENTE SIN EMPRESA: dos clientes distintos con el mismo numero (problema 77)
-- v16.85, 2026-09-13. DOS CENTINELAS, de solo lectura. NO se toco el camino del WhatsApp.
--
-- QUE PASA. `whatsapp_clientes` (942 filas: cod_cliente, telefono) y `clientes_vendedor`
-- (1.245: cod_cliente, vend) tienen el codigo como UNICA clave, sin empresa. Y el codigo de
-- cliente NO es unico entre LK y Chef -- es la propia regla del dueno (v13.76): "el cod
-- cliente no significa nada, solo el CUIT vale".
--
-- MEDIDO EL 13/09 contra los documentos de ISIS, que es el padron que factura de verdad:
--   1.640 codigos en LK, 406 en Chef, 86 en las dos, y 85 de esos 86 con RAZON SOCIAL
--   DISTINTA. O sea: casi todo lo que se solapa es gente diferente.
--   Sobre esos 85 codigos caen 71 filas de whatsapp_clientes y 84 de clientes_vendedor.
--
-- POR QUE NO ALCANZA CON ARREGLAR EL JOIN. `vista_avisar_programacion` busca el telefono
-- asi: LEFT JOIN LATERAL (select telefono from whatsapp_clientes where cod_cliente = g.cod
-- LIMIT 1). Solo el codigo, y con LIMIT 1: sobre un codigo ambiguo agarra el que venga
-- primero. Pero el problema de fondo es peor: NI `vista_avisar_programacion` NI su fuente
-- `vista_ppp_programacion_pendiente` llevan columna `empresa`. El dato no esta en el camino,
-- asi que no hay join que lo salve; hay que hacerlo viajar desde arriba. Eso toca vistas
-- COMPARTIDAS y cambia A QUIEN LE LLEGA UN WHATSAPP, o sea que va con el visto del dueno.
--
-- LO QUE SI EXISTE Y ESTA BIEN: `GV_Clientes_Whatsapp` (358 filas) tiene empresa +
-- cod_cliente + telefono + razon_social. Es la fuente correcta el dia que se rewiree.
--
-- MIENTRAS TANTO, estos dos centinelas hacen que deje de ser silencioso:
--   gv_clientes_cod_ambiguo   -- los 85 codigos, con las dos razones sociales
--   gv_aviso_cliente_dudoso   -- los avisos de HOY que caen sobre uno de esos codigos
-- MIRAR gv_aviso_cliente_dudoso ANTES DE MANDAR LOS AVISOS. Vacia = todo bien.
--
-- Al 13/09 daba TRES filas, y ninguna es teorica:
--   1792  aviso "Pettish Villa Crespo"  | LK DAPELO CLAUDIO MARCELO | CH SUPERTEXTIL S.R.L
--         el telefono que saldria (+5491161687948) es de LK/Dapelo segun GV_Clientes_Whatsapp,
--         y el nombre del aviso no coincide con NINGUNO de los dos. 18 NP colgando.
--   2191  aviso "Romagessi Antonio"     | LK ROMAGESSI ANTONIO (coincide) | CH GARCIA ALBERTO JUAN
--   2393  aviso "MIGUEL ADDOUMIE SRL"   | LK FORRAJERIA TRELEW | CH MIGUEL ADDOUMIE SRL (coincide)
--
-- ROLLBACK: drop view public.gv_aviso_cliente_dudoso; drop view public.gv_clientes_cod_ambiguo;
-- =====================================================================================

create or replace view public.gv_clientes_cod_ambiguo
with (security_invoker = true) as
with lk as (
  select distinct on (btrim(contraparte_codigo)) btrim(contraparte_codigo) cod,
         upper(btrim(contraparte_nombre)) nom
    from isis_lk.documentos where contraparte_codigo is not null
   order by btrim(contraparte_codigo), fecha desc),
ch as (
  select distinct on (btrim(contraparte_codigo)) btrim(contraparte_codigo) cod,
         upper(btrim(contraparte_nombre)) nom
    from isis_ch.documentos where contraparte_codigo is not null
   order by btrim(contraparte_codigo), fecha desc)
select lk.cod cod_cliente, lk.nom razon_lk, ch.nom razon_ch,
       (select count(*) from public.whatsapp_clientes w where btrim(w.cod_cliente) = lk.cod) filas_telefono,
       (select count(*) from public.clientes_vendedor c where btrim(c.cod_cliente) = lk.cod) filas_vendedor
  from lk join ch on ch.cod = lk.cod
 where lk.nom <> ch.nom;

create or replace view public.gv_aviso_cliente_dudoso
with (security_invoker = true) as
select v.cod cod_cliente,
       v.rs   razon_en_el_aviso,
       a.razon_lk, a.razon_ch,
       case
         when upper(btrim(v.rs)) = a.razon_lk then 'LK'
         when upper(btrim(v.rs)) = a.razon_ch then 'CH'
         else 'NO SE SABE'
       end empresa_probable,
       nullif(btrim(v.tel_cli), '') telefono_que_saldria,
       (select btrim(g.empresa) from public."GV_Clientes_Whatsapp" g
         where g.cod_cliente = v.cod and btrim(coalesce(g.telefono,'')) = btrim(coalesce(v.tel_cli,''))
         limit 1) empresa_de_ese_telefono,
       v.fppp fecha_entrega, v.nps
  from public.vista_avisar_programacion v
  join public.gv_clientes_cod_ambiguo a on a.cod_cliente = v.cod;

-- chequeo
-- select * from public.gv_aviso_cliente_dudoso order by cod_cliente;   -- vacia = todo bien
