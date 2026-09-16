-- v18.86 — el GUARDADO a góndola hereda la empresa del montón que está en A Guardar.
--
-- POR QUÉ. El 16/09 "Mover a Góndola" mostraba 475 cajas que no existen, repartidas en 10
-- códigos (026 70 · 027 53 · 031 133 · 103 73 · 312 7 · 562 54 · 564 17 · 735 41 · 859 21 ·
-- 862 6). Ninguno tenía saldo real: el neto de `a_guardar` de los 10 era CERO. Lo que había
-- era un saldo PARTIDO POR EMPRESA — entraron a A Guardar como LK (7) o CH (3), y salieron
-- como 'Mixto', así que el − no cancelaba al +:
--
--     026 → a_guardar LK +70 · a_guardar Mixto −70 · total 0
--
-- La salida en 'Mixto' la escribe este trigger: el front manda `empresa: null` cuando el
-- renglón de MG no pudo resolver la empresa (el desglose `gv_saldos_stock_emp` viene con el
-- código PELADO —"26"— y `vista_saldos_stock` con el código CRUDO —"026"—, así que para los
-- códigos con cero adelante y para los duales el detalle nunca se engancha), y hasta acá
-- `empresa IS NULL` caía derecho en 'Mixto' sin mirar de dónde salía la mercadería.
--
-- QUÉ HACE. Mismo patrón que el bloque v18.24 de más abajo (que ya resuelve la empresa de un
-- `separar_pedidos`/`a_facturar`/`terminado` mirando el picking de esa tanda): un movimiento
-- de tipo `guardado*` sin empresa explícita hereda la empresa con la que ese artículo ENTRÓ a
-- A Guardar, **si entró con una sola**. Se mira el historial completo de entradas
-- (`deposito='a_guardar' and delta > 0`), no el saldo del momento, por dos razones:
--   1) es independiente del ORDEN de las filas dentro del mismo INSERT — el tramo que baja de
--      A Guardar y el que sube a góndola/excedente viajan juntos y tienen que quedar con la
--      MISMA empresa, si no el problema se repite del otro lado;
--   2) es el mismo criterio con el que se corrigieron las 475 cajas, así que no inventa una
--      regla nueva.
-- Si el artículo entró con DOS empresas distintas (o con Mixto y con LK, como el 355: 133 LK
-- + 40 Mixto) NO se adivina: queda como estaba. Conservador a propósito.
--
-- ROLLBACK: volver a aplicar sql/backups/trg_normalizar_empresa_stock_pre_v1886.sql.

create or replace function public.trg_normalizar_empresa_stock()
 returns trigger
 language plpgsql
as $function$
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

  -- v18.86: un `guardado` SIN empresa hereda la del montón que está en A Guardar, si ese
  -- artículo entró con UNA sola empresa. Las tres filas del mismo guardado (−a_guardar,
  -- +terminado, +excedente) resuelven igual porque se mira el historial de ENTRADAS, no el
  -- saldo del momento: si no, la que baja el montón dejaría a las otras dos sin referencia.
  IF NOT v_explicita
     AND NEW.tipo LIKE 'guardado%'
     AND NEW.deposito IN ('a_guardar','terminado','excedente') THEN
    SELECT CASE WHEN count(*) = 1 THEN max(q.emp) END INTO v_emp2 FROM (
      SELECT COALESCE(NULLIF(m.empresa,''),'Mixto') AS emp
        FROM public."Movimientos_Stock" m
       WHERE m.deposito = 'a_guardar' AND m.delta > 0
         AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
       GROUP BY 1
    ) q;
    IF v_emp2 IN ('LK','CH') THEN
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
