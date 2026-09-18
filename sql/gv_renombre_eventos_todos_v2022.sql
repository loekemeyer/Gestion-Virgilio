-- ============================================================================
-- QUE EL RENOMBRE DE TANDA DEJE DE ROMPER  (v20.22)
--
-- Pedido de Thomas el 18/09, despues de E12K: "fijate que renombre deje de
-- romper". Se barrieron TODOS los eventos de los ultimos 90 dias contra el
-- regex de tanda ('^[A-Z][0-9]{2}[A-Z]$' — 4 caracteres: E12K, D71B) y se
-- comparo campo por campo contra lo que gv_evento_tanda_campo mapea. Aparecieron
-- CINCO agujeros, ninguno de los cuales se ve leyendo el codigo:
--
--   CP  -> tanda en el campo 3, pero SOLO en su forma de 3 campos
--          ('CH 0010|920|E44A'). La forma de 5 ('LK 0043|591|1|GONDOLA|NUEVA')
--          tiene una CANTIDAD ahi. No hace falta distinguirlas: el renombrador
--          matchea por VALOR, y una cantidad nunca tiene forma de tanda.
--          Medido: 0 de 224 eventos de 5 campos con forma de tanda en el campo 3.
--   PKA -> campo 1 ('E51A|360E|0').
--   PGE -> campo 2 ('505|D11F'), 20 eventos.
--   FAL -> ADEMAS del campo 5, tiene forma CORTA de 3 campos ('LK 0035|958E|E29D')
--   NPD -> ADEMAS del campo 7, la misma forma corta.
--
-- ⚠ LA LECCION: el mapeo por INDICE FIJO no alcanza, porque varias opciones
-- tienen DOS FORMATOS bajo el mismo codigo. En la forma corta el indice largo
-- no existe, gv_evento_set_tanda devolvia null y el evento se quedaba con el
-- codigo VIEJO — en silencio.
--
-- LA SOLUCION es gv_evento_tanda_idx(opcion, texto), que resuelve el indice
-- REAL de ese texto. Fallback CONSERVADOR a proposito: si el campo mapeado
-- EXISTE se usa ese, asi que no cambia nada de lo que hoy anda. Solo cuando el
-- texto es mas corto busca el UNICO campo con forma de tanda; si hay mas de uno
-- es ambiguo y devuelve null (mejor no renombrar que renombrar mal).
--
-- ⚠ Y EL CANDADO VIEJO. `Tandas_Lock` (la que usan tanda_reservar y
-- tanda_liberar, con movimientos del 15/09) no la tocaba el renombrador. Un
-- candado que se queda con el codigo viejo deja la tanda IMPICKEABLE para
-- siempre: es lo que le paso a LK 0043 con E12L. Mismo PK (tanda, fase) que
-- GV_Tandas_Lock, mismo tratamiento: primero el DELETE del origen que choca,
-- despues el UPDATE.
--
-- EL CENTINELA, para no volver a barrer a mano:
--   select * from public.gv_renombre_eventos_sin_mapear;   -- vacia = todo bien
-- Fue el que encontro PGE y las formas cortas de FAL/NPD DESPUES de que el
-- barrido a mano diera por cerrado el tema con CP y PKA.
--
-- PROBADO PUNTA A PUNTA (transaccion abortada) con una tanda de descarte Z90Z y
-- los 10 formatos de evento: los 10 viajaron a Z91Z, los DOS candados se
-- movieron, no quedo nada en Z90Z, y el CP de 5 campos quedo intacto.
-- ⚠ Ojo al probar: la tanda de descarte tiene que tener forma de tanda REAL
-- (4 caracteres). Con 'ZZ90Z' (5) el regex no la reconoce y la prueba miente.
-- ============================================================================

create or replace function public.gv_evento_tanda_campo(p_opcion text)
 returns integer language sql immutable as $f$
  select case upper(btrim(coalesce(p_opcion, '')))
           when 'CCN' then 2 when 'CCR' then 2 when 'CRN' then 2 when 'FSS' then 2
           when 'CRA' then 2 when 'FCO' then 2 when 'ENT' then 2
           when 'TAL' then 3 when 'FAL' then 5 when 'NPD' then 7
           when 'PKC' then 1 when 'PSP' then 1 when 'FGU' then 1
           when 'SSG' then 1 when 'RAG' then 1
           when 'CP'  then 3 when 'PKA' then 1 when 'PGE' then 2   -- v20.22
           else null end;
$f$;

-- v20.22 — EL INDICE REAL DE LA TANDA EN ESTE TEXTO (ver el encabezado).
create or replace function public.gv_evento_tanda_idx(p_opcion text, p_texto text)
 returns integer language sql immutable as $f$
  with m as (select public.gv_evento_tanda_campo(p_opcion) i,
                    string_to_array(coalesce(p_texto,''),'|') p),
       cand as (select g.i idx from m, generate_subscripts(m.p,1) g(i)
                 where upper(btrim(m.p[g.i])) ~ '^[A-Z][0-9]{2}[A-Z]$')
  select case
           when (select i from m) is null then null
           when coalesce(array_length((select p from m),1),0) >= (select i from m)
             then (select i from m)                                  -- conservador
           when (select count(*) from cand) = 1 then (select idx from cand)
           else null end;                                            -- ambiguo: no tocar
$f$;

create or replace function public.gv_evento_tanda(p_opcion text, p_texto text)
 returns text language sql immutable as $f$
  select case when public.gv_evento_tanda_idx(p_opcion, p_texto) is null then null
              else nullif(upper(btrim(split_part(coalesce(p_texto,''),'|',
                          public.gv_evento_tanda_idx(p_opcion, p_texto)))),'') end;
$f$;

create or replace function public.gv_evento_set_tanda(p_opcion text, p_texto text, p_tanda text)
 returns text language plpgsql immutable as $f$
declare v_i int := public.gv_evento_tanda_idx(p_opcion, p_texto);
        v_t text := upper(btrim(coalesce(p_tanda,''))); v_p text[];
begin
  if v_i is null or v_t = '' or coalesce(btrim(p_texto),'') = '' then return null; end if;
  v_p := string_to_array(p_texto,'|');
  if coalesce(array_length(v_p,1),0) < v_i then return null; end if;
  if upper(btrim(coalesce(v_p[v_i],''))) = v_t then return null; end if;
  v_p[v_i] := v_t; return array_to_string(v_p,'|');
end $f$;

-- ⚠ El candado VIEJO. Va DENTRO de gv_ppp_tanda_renombrar, justo despues del
-- bloque de GV_Tandas_Lock. Mismo PK (tanda, fase): DELETE del que choca y
-- despues UPDATE, o el update viola el unique.
--   delete from public."Tandas_Lock" l
--    where upper(btrim(l.tanda)) = v_a
--      and exists (select 1 from public."Tandas_Lock" d
--                   where upper(btrim(d.tanda)) = v_b and d.fase = l.fase);
--   update public."Tandas_Lock" l set tanda = v_b where upper(btrim(l.tanda)) = v_a;

-- EL CENTINELA
create or replace view public.gv_renombre_eventos_sin_mapear as
with e as (
  select opcion, texto, ts_cliente from public."Registros_Produccion_Virgilio"
   where ts_cliente >= now() - interval '90 days' and coalesce(texto,'') <> ''
     and strpos(texto,'|') > 0          -- el texto que ES la tanda sola lo agarra el 1er UPDATE
), c as (
  select e.opcion, i campo, upper(btrim(split_part(e.texto,'|',i))) val, e.texto, e.ts_cliente
    from e, generate_series(1,8) i where split_part(e.texto,'|',i) <> ''
)
select c.opcion, c.campo campo_con_tanda,
       public.gv_evento_tanda_idx(c.opcion, c.texto) campo_que_se_renombra,
       count(*) eventos, min(c.ts_cliente)::date desde, max(c.ts_cliente)::date hasta,
       (array_agg(c.texto order by c.ts_cliente desc))[1] ejemplo,
       case when public.gv_evento_tanda_idx(c.opcion, c.texto) is null
            then 'NO SE RENOMBRA: el evento se queda con el codigo viejo'
            else 'SE RENOMBRA EL CAMPO EQUIVOCADO' end problema
  from c
 where c.val ~ '^[A-Z][0-9]{2}[A-Z]$'
   and public.gv_evento_tanda_idx(c.opcion, c.texto) is distinct from c.campo
 group by 1,2,3 order by 4 desc;
alter view public.gv_renombre_eventos_sin_mapear set (security_invoker = true);

-- chequeo
-- select * from public.gv_renombre_eventos_sin_mapear;   -- vacia = todo bien
