-- ════════════════════════════════════════════════════════════════════════════════════════
-- v20.62 (Thomas, 2026-09-21) — EL DESTINO DE UNA NP DE ISIS, Y LA ETIQUETA CON PARÉNTESIS
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Pregunta de Thomas: *"pero los nuevos pedidos que lleguen ya van con el banner?"*, sobre el
-- aviso de Misiones de la v20.45. Y sobre las NP de ISIS de un cliente con sucursales en
-- varias provincias: *"¿se resuelve el destino por el expreso que trae la NP, o se deja en
-- null? Hoy queda ciego."* → **Sí, resolverlo.**
--
-- ⚠ LO PRIMERO QUE SE MIDIÓ TIRA ABAJO LA PREMISA: **la NP de ISIS NO TRAE EXPRESO.**
--
--   select count(*) filas, count(*) filter (where direccion ~* '^\s*exp') con_prefijo_exp
--     from public.gv_ppp_programacion_diaria;   -- 120 filas, 0 con "Exp."
--
--   El "Exp. <nombre> — <dir> (<etiqueta>)" lo arma la PÁGINA. La NP de ISIS trae `direccion`
--   y `barrio` pelados, y nada más. Así que "por el expreso" no se puede: lo que SÍ trae y
--   desambigua es el **BARRIO**, que es la localidad de la sucursal.
--
--   Y el expreso, aunque viajara, no alcanzaría solo: de los 98 clientes con sucursales en más
--   de una provincia, 63 tienen expreso cargado en el padrón y de sus 73 combinaciones
--   (cliente, expreso) sólo **41 pintan una sola provincia**. En las otras 32 el expreso
--   entrega a dos provincias distintas del mismo cliente.
--
-- ⚠ QUÉ ESTABA ROTO, MEDIDO EL 21/09 SOBRE LAS 315 NP PROGRAMADAS DESDE EL 01/09:
--
--   | resultado    | NP  | qué significa                                                  |
--   |--------------|-----|----------------------------------------------------------------|
--   | match/unica  | 307 | resolvió (97,5 %)                                              |
--   | ambiguo      |   4 | ← las que este archivo arregla                                 |
--   | sin padrón   |   4 | el cliente no tiene dirección en la página (Matiz, Chaverim)   |
--
--   Las 4 ambiguas, una por una:
--     · **LK 0178 y LK 0179** (Multi Bazar, 02/10) — dirección
--       `Exp.  — Juan B. Justo 7594 (Río Gall (25 de mayo))`. La etiqueta de la sucursal
--       **tiene paréntesis adentro**, y el regex del label era `\(([^()]*)\)\s*$`: con el
--       paréntesis anidado no matcheaba NADA, así que la NP no encontraba su sucursal. El
--       cliente tiene sucursales en Río Negro, CABA, Buenos Aires y **Santa Cruz**, y estas
--       dos van a Río Gallegos. En pantalla se leían *"Zona 3 - CABA Oeste"*.
--     · **98620** (La Patagonia, 09/09, NP de ISIS) — `Km 10, Au Camino del Buen Ayre` /
--       barrio `Campo de Mayo`. Sus 11 sucursales están en 8 provincias y **todas tienen la
--       misma dirección y el mismo dir_key** (el galpón del expreso en Ituzaingó), así que la
--       dirección no distingue nada. El barrio sí: `Campo de Mayo` es la localidad de una
--       sola de las 11.
--     · **LK 0097** (Bazar Y Cia) — es un **Retira**. No hay expreso que entregue nada, así
--       que no hay provincia destino que resolver: hoy sale `como = 'retira'` y deja de
--       contarse como agujero.
--
-- ⚠ Y LO QUE **NO** SE TOCA: las 73 direcciones del padrón sin provincia cargada y los dos
--   clientes que no están en el padrón. Ahí el dato no existe, y no se inventa (misma regla
--   que la v20.45). Quedan a la vista en `gv_destino_sin_provincia`, ahora con `motivo`.
-- ════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. el puntaje: dos caminos, porque la NP web y la de ISIS traen cosas distintas ─────
-- ⚠ La normalización (minúsculas, sin acentos, sin dobles espacios) va ADENTRO y repetida, y
-- NO llamando a un helper. Una función SQL con `SET search_path` **no se inlinea**, y
-- llamarla 20 veces por par costaba 10× — medido el 21/09 con 4.338 pares, 3 corridas:
--
--   | variante                              | ms  |
--   |---------------------------------------|-----|
--   | v20.45 (sin normalizar)               | 321 |
--   | v20.62 llamando a un helper gv_txt_norm | 3.590 |
--   | v20.62 con la normalización adentro   | 870 |
--
-- Es feo a propósito. La vista entera mide 875 ms y la RPC la llama de a lotes de 500 NP.
create or replace function public.gv_destino_score(p_etiqueta text, p_direccion text, p_dir_key text, p_nombre_expreso text, p_dir_expreso text, p_localidad text, p_dir text, p_bar text, p_x_exp text, p_x_dirx text, p_x_lab text)
returns integer
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  with n as (select
      translate(lower(btrim(regexp_replace(coalesce(p_etiqueta,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') etq,
      translate(lower(btrim(regexp_replace(coalesce(p_direccion,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') dpad,
      translate(lower(btrim(regexp_replace(coalesce(p_nombre_expreso,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') nexp,
      translate(lower(btrim(regexp_replace(coalesce(p_dir_expreso,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') dexp,
      translate(lower(btrim(regexp_replace(coalesce(p_localidad,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') loc,
      translate(lower(btrim(regexp_replace(coalesce(p_dir,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') dir,
      translate(lower(btrim(regexp_replace(coalesce(p_bar,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') bar,
      translate(lower(btrim(regexp_replace(coalesce(p_x_exp,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') xexp,
      translate(lower(btrim(regexp_replace(coalesce(p_x_dirx,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') xdirx,
      translate(lower(btrim(regexp_replace(coalesce(p_x_lab,''),'\s+',' ','g'))),'áéíóúàèìòùâêîôûäëïöüãõñç','aeiouaeiouaeiouaeiouaonc') xlab)
  select (case when n.etq <> '' and n.etq = n.xlab then 9 else 0 end)
       + (case when n.etq <> '' and p_x_lab is null and n.etq = n.dir then 7 else 0 end)
       + (case when n.dpad <> '' and n.dpad = n.dir then 6 else 0 end)
       -- la NP de ISIS no trae etiqueta: su BARRIO es la localidad de la sucursal
       + (case when n.loc <> '' and n.loc = n.bar then 6 else 0 end)
       + (case when coalesce(p_dir_key,'') <> '' and coalesce(p_dir,'') <> ''
                and p_dir_key = public.gv_dir_key(p_dir, nullif(p_bar,'')) then 5 else 0 end)
       + (case when n.nexp <> '' and n.nexp = n.xexp then 4 else 0 end)
       + (case when n.loc <> '' and n.xlab <> '' and n.xlab like '%'||n.loc||'%' then 3 else 0 end)
       -- y la localidad nombrada en la direccion cruda ("… - Villa Rosa")
       + (case when length(n.loc) >= 4 and n.dir like '%'||n.loc||'%' then 3 else 0 end)
       + (case when n.dexp <> '' and n.dexp = n.xdirx then 2 else 0 end)
       + (case when n.etq <> '' and length(n.bar) >= 4 and n.etq like '%'||n.bar||'%' then 2 else 0 end)
    from n;
$function$;

-- ── 2. la vista: label con paréntesis anidado, y el Retira que no es un agujero ──────────
create or replace view public.gv_np_destino as
with _nd_todo as (
  select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
         lower(btrim(coalesce(w.empresa, ''))) as empresa,
         btrim(coalesce(w.cod_cliente, '')) as cod,
         w.direccion, w.barrio, w.fecha_entrega as fecha, 1 as pri, true as programada
    from public."PPP_Web_Programacion" w
  union all
  select regexp_replace(btrim(g.np), '\.0+$', ''), public.gv_emp_de_np(g.np),
         btrim(coalesce(g.cod, '')), g.direccion, g.barrio,
         case when left(btrim(coalesce(g.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(g.fecha_entrega), 10)::date else null::date end,
         2, true
    from public.gv_ppp_programacion_diaria g
  union all
  select regexp_replace(upper(btrim(f.np)), '\.0+$', ''), public.gv_emp_de_np(f.np),
         btrim(coalesce(f.cod_cliente, '')), null::text, null::text, f.fecha_salida, 3, false
    from public."Facturacion_NP" f
), _nd as (
  select distinct on (t.np) t.np, t.empresa, t.cod, t.direccion, t.barrio, t.fecha, t.pri, t.programada
    from _nd_todo t
   where coalesce(btrim(t.np), '') <> '' and t.cod <> ''
   order by t.np, t.pri, t.direccion
), _q as (
  select n.*,
         -- ⚠ v20.62: la etiqueta puede tener PARENTESIS ADENTRO ("Rio Gall (25 de mayo)").
         -- Con `\(([^()]*)\)$` esa NP no matcheaba ninguna sucursal y salia 'ambiguo'
         -- (LK 0178 y LK 0179, Santa Cruz, programadas para el 02/10).
         (regexp_match(coalesce(n.direccion, ''), '^Exp\.\s*(.+?)\s+—\s'))[1] as x_exp,
         (regexp_match(coalesce(n.direccion, ''), '—\s*(.*?)\s*\((?:[^()]|\([^()]*\))*\)\s*$'))[1] as x_dirx,
         (regexp_match(coalesce(n.direccion, ''), '\(((?:[^()]|\([^()]*\))*)\)\s*$'))[1] as x_lab
    from _nd n
), _qr as (
  -- Retira: mismo criterio que gv_ppp_web_zona (v19.86/88) — EXACTO, nunca por subcadena,
  -- porque "Retiro" es un barrio de CABA; mas el expreso "Retira" y el deposito.
  select q.*,
         (coalesce(btrim(q.direccion), '') ~* '^retira$'
          or coalesce(btrim(q.barrio), '') ~* '^retira$'
          or coalesce(btrim(q.x_exp), '') ~* '^retira$'
          or coalesce(q.direccion, '') ~* '^\s*exp\.\s*retira([^a-záéíóúñ]|$)'
          or coalesce(q.direccion, '') ~* 'virgilio\s*2788') as es_retira
    from _q q
), _c as (
  select q.np, q.empresa, q.cod, q.programada, q.fecha, q.es_retira, d.slot, d.provincia, d.localidad,
         d.nombre_expreso,
         public.gv_destino_score(d.etiqueta, d.direccion, d.dir_key, d.nombre_expreso, d.dir_expreso,
                                 d.localidad, q.direccion, q.barrio, q.x_exp, q.x_dirx, q.x_lab) as score
    from _qr q
    left join public."GV_Clientes_Direcciones" d on d.empresa = q.empresa and btrim(d.cod) = q.cod
), _a as (
  select np, max(score) as mx, count(slot) as cands,
         count(distinct coalesce(provincia, '')) filter (where slot is not null) as prov_todas
    from _c group by np
), _t as (
  select c.np, count(distinct coalesce(c.provincia, '')) as prov_top
    from _c c join _a a using (np)
   where c.slot is not null and c.score = a.mx
   group by c.np
), _p as (
  select distinct on (c.np) c.* from _c c order by c.np, c.score desc nulls last, c.slot
), _r as (
  select p.np, p.empresa, p.cod, p.programada, p.fecha, p.es_retira, a.mx, a.cands, a.prov_todas,
         t.prov_top, p.provincia, p.localidad, p.nombre_expreso,
         a.cands > 0 and (a.mx > 0 and t.prov_top = 1 or a.prov_todas = 1) as ok
    from _p p join _a a using (np) left join _t t using (np)
)
select np, empresa, cod, programada, fecha,
       case when ok then provincia end as provincia,
       case when ok then localidad end as localidad_destino,
       case when ok then nombre_expreso end as expreso,
       case when cands = 0        then 'sin padron'
            when mx > 0 and prov_top = 1 then 'match'
            when prov_todas = 1   then 'unica'
            when es_retira        then 'retira'
            else 'ambiguo' end as como,
       public.gv_provincia_alerta(case when ok then provincia end) as alerta,
       nullif(concat_ws(' · ', nullif(btrim(coalesce(case when ok then nombre_expreso end, '')), ''),
                              nullif(btrim(coalesce(case when ok then provincia end, '')), '')), '') as destino_txt
  from _r r;
-- ⚠ `create or replace view` BORRA las reloptions: sin esto la vista corre como postgres y
-- saltea la RLS del padrón (la filtración que costó caro el 04/09).
alter view public.gv_np_destino set (security_invoker = true);

-- ── 3. el centinela dice POR QUÉ falta, y el Retira ya no cuenta como agujero ────────────
create or replace view public.gv_destino_sin_provincia as
 select np, empresa, cod, como, fecha,
        case when como = 'sin padron' then 'el cliente no esta en el padron de direcciones'
             when como = 'ambiguo'    then 'tiene sucursales en varias provincias y la NP no desambigua'
             else 'la sucursal resolvio, pero esa direccion del padron no tiene provincia cargada'
        end as motivo
   from public.gv_np_destino d
  where provincia is null and programada and como <> 'retira';
alter view public.gv_destino_sin_provincia set (security_invoker = true);

-- ── 4. las tres reglas que no se pueden perder (otra sesión las pisa sin avisar) ─────────
-- ⚠ `GV_Reglas_Centinela` sólo tiene PK por `id`: un `on conflict do nothing` NO deduplica,
-- duplica. Por eso va con `where not exists`, para que reaplicar este archivo sea inocuo.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
 ('gv_destino_score','funcion','n\.loc = n\.bar',
  'La NP de ISIS no trae etiqueta ni expreso (medido 21/09: 0 de 120 filas con "Exp."): lo que desambigua la sucursal es su BARRIO contra la localidad del padron. Sin esta regla un pedido al interior de un cliente con sucursales en varias provincias sale ambiguo y no se pinta.',
  'Thomas','v20.62'),
 ('gv_np_destino','vista','\(\?:',
  'La etiqueta de la sucursal puede tener parentesis adentro ("Rio Gall (25 de mayo)"): el parentesis final se lee con un grupo que tolera un nivel de anidado. Con \(([^()]*)\)$ esas NP no matcheaban ninguna sucursal y salian ambiguo (LK 0178 y LK 0179, Santa Cruz).',
  'Thomas','v20.62'),
 ('gv_np_destino','vista','es_retira',
  'Un Retira que no resuelve provincia sale como "retira", no como "ambiguo": no hay expreso que entregue nada y el centinela gv_destino_sin_provincia tiene que quedar con lo que de verdad falta.',
  'Thomas','v20.62')
) as v(objeto, clase, patron, regla, quien_pidio, version)
 where not exists (select 1 from public."GV_Reglas_Centinela" c
                    where c.objeto = v.objeto and c.patron = v.patron);

-- ════════════════════════════════════════════════════════════════════════════════════════
-- IMPACTO MEDIDO (21/09, 1.493 NP: se recreó la vista v20.45 al lado y se comparó fila por
-- fila con un full join). **13 NP cambian, 3 ganan provincia, NINGUNA cambia de una
-- provincia a otra:**
--
--   | antes   | ahora  | provincia            | NP  | cuáles              |
--   |---------|--------|----------------------|-----|---------------------|
--   | unica   | match  | CABA → CABA          |  5  | misma, más evidencia|
--   | unica   | match  | Bs. As. → Bs. As.    |  4  | ídem                |
--   | ambiguo | match  | null → **Santa Cruz**|  2  | LK 0178, LK 0179    |
--   | ambiguo | match  | null → Buenos Aires  |  1  | 98620               |
--   | ambiguo | retira | null → null          |  1  | LK 0097             |
--
-- `ambiguo` en la PPP viva pasó de 4 a **0**. El centinela bajó de 28 a 24 filas, y las 24
-- que quedan son dato que falta en el padrón (9 de Cencosud, 4 de dos clientes que no están
-- en el padrón), no reglas sin resolver.
--
-- CHEQUEOS
--   select * from public.gv_reglas_perdidas;                                     -- vacía
--   select como, count(*) from public.gv_np_destino where programada group by 1; -- 0 ambiguos
--   select * from public.gv_destino_sin_provincia order by fecha desc;           -- con motivo
--   select np, provincia, como from public.gv_np_destino
--    where np in ('LK 0027','LK 0178','LK 0179','98620','LK 0097');
--   -- LK 0027 Misiones · LK 0178/0179 Santa Cruz · 98620 Buenos Aires · LK 0097 (retira)
--
-- ROLLBACK: `sql/gv_destino_misiones_v2045.sql` tiene el `gv_destino_score` y el
-- `gv_np_destino` anteriores. Volverlos a aplicar los dos juntos (el score viejo con la
-- vista nueva anda, pero deja de resolver las de ISIS) + borrar las 3 filas de
-- `GV_Reglas_Centinela` con version = 'v20.62'.
-- ════════════════════════════════════════════════════════════════════════════════════════
