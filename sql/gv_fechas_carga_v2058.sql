-- v20.58 (2026-09-21, pedido de Elías) — que una fecha sucia no apague una pantalla,
-- y que nadie tenga que descubrirla de casualidad.
--
-- QUÉ PASÓ. La vista "Entregas_Tallerista_Excel" castea "Fecha"::date para calcular Dia y
-- Mes. Una sola fila con Fecha = '|||' (id 876, Lucho, cod 186, 39 cajas, cargada el
-- 21/04/2026) hacía que CUALQUIER select de sus columnas devolviera 22007 y la vista se
-- viera vacía en el Table Editor: 1.409 filas invisibles por culpa de una. Estuvo así
-- cinco meses. "Entregas_Tall_Todas" no castea, por eso las 14 pantallas del admin de
-- Cervantes nunca se enteraron.
--
-- LAS DOS MITADES, Y VAN JUNTAS. Blindar solo tapa el síntoma: la pantalla deja de
-- romperse y el dato sucio pasa sin que nadie lo vea. Por eso el CASE viene con centinela.
-- (Elías, 21/09: "pero cómo nos daríamos cuenta que entró una vacía?")
--
-- Y la tercera mitad vive en el front: recepcion.js ya no deja grabar sin fecha, y el
-- Dia_mes de "Entregas Prov AT" se guarda con año. Lo sostiene tests/recepcion-fecha-anio.cjs.

-- 1) La vista, blindada. Conserva security_invoker (un CREATE OR REPLACE VIEW sin WITH
--    borra las reloptions y la vista pasaría a correr como postgres, salteando la RLS).
create or replace view public."Entregas_Tallerista_Excel" as
 select id,
        "Fecha",
        "Nombre_Tall",
        "Cod",
        "Cajas",
        "Remito",
        case when "Fecha" ~ '^\d{4}-\d{2}-\d{2}$'
             then extract(day from "Fecha"::date)::integer end as "Dia",
        left("Fecha", 7) as "Mes"
   from "Entregas Tallerista Virgilio";

alter view public."Entregas_Tallerista_Excel" set (security_invoker = true);

-- 2) El centinela. VACÍA = todo bien.
--    select * from public.gv_fechas_carga_invalidas;
create or replace view public.gv_fechas_carga_invalidas as
with f as (
  select 'Entregas Tallerista Virgilio'::text tabla, id, "Fecha"::text valor, 'iso'::text formato_esperado
    from public."Entregas Tallerista Virgilio"
  union all
  select 'Entregas Tallerista Cervantes', id, "Fecha", 'iso'
    from public."Entregas Tallerista Cervantes"
  union all
  select 'Entregas Prov AT', id, "Dia_mes", 'dd/mm/aa'
    from public."Entregas Prov AT"
  union all
  select 'Envios a Talleristas', id, "Dia-mes", 'dd/mm/aa'
    from public."Envios a Talleristas"
  union all
  select 'Envios a PS', id, "Dia-mes", 'dd/mm/aa'
    from public."Envios a PS"
  union all
  -- Entregas PS convive a propósito con dos formatos: 253 en dd/mm/aa y 66 en ISO, que las
  -- escribe arDateISO() del admin. Las ISO tienen año, así que no son un problema: los
  -- lectores (mmDe/ddDe de EnviosPS.js) soportan los dos desde hace rato.
  select 'Entregas PS', id, "Dia-mes", 'dd/mm/aa o iso'
    from public."Entregas PS")
select tabla, id, valor,
       case
         when valor is null or btrim(valor) = '' then 'fecha VACIA'
         when formato_esperado = 'iso' and valor !~ '^\d{4}-\d{2}-\d{2}$' then 'no es una fecha'
         when formato_esperado <> 'iso' and valor ~ '^\d{1,2}[-/]\d{1,2}$' then 'sin año'
         when formato_esperado = 'dd/mm/aa' and valor !~ '^\d{1,2}/\d{1,2}/\d{2,4}$' then 'no es una fecha'
         when formato_esperado = 'dd/mm/aa o iso'
              and valor !~ '^(\d{1,2}/\d{1,2}/\d{2,4}|\d{4}-\d{2}-\d{2})$' then 'no es una fecha'
       end as motivo
  from f
 where valor is null or btrim(valor) = ''
    or (formato_esperado = 'iso' and valor !~ '^\d{4}-\d{2}-\d{2}$')
    or (formato_esperado = 'dd/mm/aa' and valor !~ '^\d{1,2}/\d{1,2}/\d{2,4}$')
    or (formato_esperado = 'dd/mm/aa o iso'
        and valor !~ '^(\d{1,2}/\d{1,2}/\d{2,4}|\d{4}-\d{2}-\d{2})$');

alter view public.gv_fechas_carga_invalidas set (security_invoker = true);

-- 3) "Entregas Prov AT" no tenía cómo saber cuándo se cargó una fila: por eso el año de las
--    41 hubo que reconstruirlo. Ahora queda registrado. La columna va SIN default primero,
--    así las 162 filas viejas quedan en NULL — no se les inventa una fecha de carga.
alter table public."Entregas Prov AT" add column if not exists created_at timestamptz;
alter table public."Entregas Prov AT" alter column created_at set default now();

-- PRUEBAS QUE SE CORRIERON (no alcanza con leer la vista):
--   insert into public."Entregas Tallerista Virgilio" ("Fecha","Codigo_Tall","Nombre_Tall","Cod","Cajas")
--   values ('__PRUEBA__','0000','__PRUEBA__','000',0);
--   select count(*) from public."Entregas_Tallerista_Excel";            -- 1410, NO error
--   select count(*) from public.gv_fechas_carga_invalidas
--    where valor = '__PRUEBA__';                                        -- 1, la caza
--   delete from public."Entregas Tallerista Virgilio" where "Nombre_Tall" = '__PRUEBA__';
--
--   insert into public."Entregas Prov AT" ("Dia_mes","Proveedor","Cod_Art","Descripcion","Cantidad","Remito")
--   values ('__PRUEBA__','__PRUEBA__','__PRUEBA__','__PRUEBA__',0,'__PRUEBA__');
--   select created_at from public."Entregas Prov AT" where "Proveedor" = '__PRUEBA__';  -- now()
--   delete from public."Entregas Prov AT" where "Proveedor" = '__PRUEBA__';
