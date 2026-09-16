-- Backup de public.trg_normalizar_empresa_stock() tal como estaba ANTES de la v18.86
-- (tomado con pg_get_functiondef el 2026-09-16). Ejecutar este archivo es el rollback
-- exacto de sql/trg_normalizar_empresa_stock_v1886.sql.

CREATE OR REPLACE FUNCTION public.trg_normalizar_empresa_stock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_base text; v_dual boolean; v_np text; v_emp2 text; v_explicita boolean; v_tanda text;
BEGIN
  IF NEW.deposito = 'insumos' THEN
    NEW.cod_art := regexp_replace(NEW.cod_art,'\s+(LK|CH|LOKE)$','');
    RETURN NEW;
  END IF;

  v_explicita := NEW.empresa IS NOT NULL AND NEW.empresa IN ('LK','CH');

  IF NEW.cod_art ~ '\s+(LK|LOKE)$' THEN NEW.empresa:='LK'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+(LK|LOKE)$','');
  ELSIF NEW.cod_art ~ '\s+CH$' THEN NEW.empresa:='CH'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+CH$',''); END IF;
  IF NEW.cod_art ~ '[0-9E]L$' THEN
    NEW.empresa := 'LK';
    NEW.cod_art := regexp_replace(NEW.cod_art,'([0-9E])L$','\1');
    v_explicita := true;
  END IF;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)),'^0+(?=.)','');
  SELECT true INTO v_dual FROM public.codigos_duales WHERE regexp_replace(upper(btrim(cod)),'^0+(?=.)','')=v_base LIMIT 1;

  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa
  -- de ESE picking (si es una sola). Si no, cae en 'Mixto' y no se netea.
  v_tanda := upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)));
  IF NOT v_explicita
     AND NEW.deposito IN ('separar_pedidos','a_facturar','terminado')
     AND v_tanda ~ '^[A-Z][0-9]{2}[A-Z]$' THEN
    SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
      INTO v_emp2
      FROM public."Movimientos_Stock" m
     WHERE m.tipo='picking' AND m.deposito='separar_pedidos'
       AND m.empresa IN ('LK','CH')
       AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
       AND upper(btrim(split_part(m.ref,'|',1))) = v_tanda;
    IF v_emp2 IS NOT NULL THEN
      NEW.empresa := v_emp2;
      RETURN NEW;
    END IF;
  END IF;

  IF NOT COALESCE(v_dual,false) THEN
    IF NOT v_explicita THEN NEW.empresa := 'Mixto'; END IF;
  ELSE
    IF NEW.empresa IS NULL OR NEW.empresa = 'Mixto' THEN
      v_np := nullif(regexp_replace(split_part(coalesce(NEW.ref,''),'|',2),'\D','','g'),'');
      IF v_np IS NOT NULL THEN NEW.empresa := public.empresa_de_np(v_np); END IF;
      IF (NEW.empresa IS NULL OR NEW.empresa = '' OR NEW.empresa = 'Mixto')
         AND NEW.deposito = 'a_facturar' AND NEW.tipo = 'facturado' THEN
        SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
          INTO v_emp2
          FROM public."Movimientos_Stock" m
         WHERE m.deposito='a_facturar' AND m.tipo='separado'
           AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
           AND upper(btrim(split_part(m.ref,'|',1))) = upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)))
           AND m.empresa IN ('LK','CH');
        IF v_emp2 IS NOT NULL THEN NEW.empresa := v_emp2; END IF;
      END IF;
      IF NEW.empresa IS NULL OR NEW.empresa = '' THEN NEW.empresa := 'Mixto'; END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
