-- ROLLBACK: stocks_carga_rapida → Stock_Saldos
-- Fecha: 2026-08-13
-- Revierte la migración de Stock_Saldos a stocks_carga_rapida

-- 1. Recrear Stock_Saldos
CREATE TABLE IF NOT EXISTS public."Stock_Saldos" (
  cod              text PRIMARY KEY,
  cod_base         text,
  descripcion      text,
  linea            text,
  familia_principal text,
  es_secundario    boolean DEFAULT false,
  terminado        numeric DEFAULT 0,
  excedente        numeric DEFAULT 0,
  separar_pedidos  numeric DEFAULT 0,
  a_facturar       numeric DEFAULT 0,
  a_guardar        numeric DEFAULT 0,
  racks            numeric DEFAULT 0,
  racks_ch         numeric DEFAULT 0,
  para_envasar     numeric DEFAULT 0,
  insumos_dep      numeric DEFAULT 0,
  stock_total      numeric DEFAULT 0,
  cajas_pedidas    numeric DEFAULT 0,
  proy_cajas_mes   numeric DEFAULT 0,
  capacidad_gondola numeric DEFAULT 0,
  es_insumo        boolean DEFAULT false,
  visible_en_stock boolean DEFAULT true
);

-- 2. Poblar desde stocks_carga_rapida
INSERT INTO public."Stock_Saldos"
SELECT cod,cod_base,descripcion,linea,familia_principal,es_secundario,
  terminado,excedente,separar_pedidos,a_facturar,a_guardar,racks,racks_ch,
  para_envasar,insumos_dep,stock_total,cajas_pedidas,proy_cajas_mes,
  capacidad_gondola,es_insumo,visible_en_stock
FROM public.stocks_carga_rapida;

-- 3. Reapuntar trigger a Stock_Saldos
CREATE OR REPLACE FUNCTION public.actualizar_saldo_trigger()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  WITH saldos_por_dep AS (
    SELECT
      cod_art,
      deposito,
      SUM(CAST(delta AS NUMERIC)) as saldo
    FROM "Movimientos_Stock"
    WHERE cod_art = NEW.cod_art
    GROUP BY cod_art, deposito
  )
  UPDATE "Stock_Saldos"
  SET
    terminado = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'terminado'), 0),
    excedente = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'excedente'), 0),
    separar_pedidos = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'separar_pedidos'), 0),
    a_facturar = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'a_facturar'), 0),
    a_guardar = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'a_guardar'), 0),
    racks = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'racks'), 0),
    racks_ch = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'racks_ch'), 0),
    para_envasar = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'para_envasar'), 0),
    insumos_dep = COALESCE((SELECT saldo FROM saldos_por_dep WHERE deposito = 'insumos_dep'), 0),
    stock_total = (SELECT SUM(CAST(delta AS NUMERIC)) FROM "Movimientos_Stock" WHERE cod_art = NEW.cod_art)
  WHERE cod = NEW.cod_art;
  RETURN NEW;
END;
$$;

-- 4. RLS para Stock_Saldos
ALTER TABLE public."Stock_Saldos" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_read_stock_saldos" ON public."Stock_Saldos"
  FOR SELECT TO anon USING (true);

-- 5. Borrar stocks_carga_rapida
DROP TABLE IF EXISTS public.stocks_carga_rapida;

-- 6. En index.html: revertir commit v10.41 (git revert)
