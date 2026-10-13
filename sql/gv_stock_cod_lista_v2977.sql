/* v29.77 (Luis, 13/10): «mas que candado, solo debería dar opciones de poner un codigo ya existente.
   a medida que se escribe se sugiere el codigo».

   El campo Código de Ingreso a racks (modo Importación) pasa a SUGERIR códigos. El universo es el
   MISMO que ya decide gv_stock_cod_conocido (el candado de la v29.67) — así la pantalla no puede
   sugerir un código que después el candado rechaza —, con dos diferencias a propósito:
     · sin los dados de baja (GV_Codigo_Baja), igual que el candado;
     · SIN «Insumos»: acá se ingresan ARTÍCULOS, y los códigos de insumos son justo los que se
       confunden con una posición de rack (A1 es insumo Y posición). El insumo importado (323ES)
       entra igual, porque está en Importados.
   El código se devuelve como lo escriben los maestros (CON el cero adelante: 026, no 26), que es
   como se escribe en Movimientos_Stock / GV_Lugar_Item / Importados / OC_Maximos.

   Rollback: drop function public.gv_stock_cod_lista();
*/
create or replace function public.gv_stock_cod_lista()
returns table (cod text, nombre text, importado boolean)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with todos as (
    select v.cod::text c from public.vista_nombres_articulos v
    union all select v.cod::text from public.vista_uxb_articulo v
    union all select v.cod::text from public."OC_Maximos" v
    union all select v.cod::text from public."GV_Lugar_Item" v
    union all select v.cod::text from public."Capacidad_Sector" v
    union all select v.cod::text from public.proyeccion_madre v
    union all select i.cod_art::text from public."Importados" i
  ), n as (
    select upper(regexp_replace(regexp_replace(btrim(c), '\s+(LK|CH|LOKE)$', '', 'i'), '^0+(?=.)', '')) k,
           upper(regexp_replace(btrim(c), '\s+(LK|CH|LOKE)$', '', 'i')) c
      from todos
     where coalesce(btrim(c), '') <> ''
  ), u as (
    select k, (array_agg(c order by length(c) desc, c))[1] cod from n group by k
  )
  select u.cod,
         coalesce((select v.descripcion from public.vista_nombres_articulos v
                    where upper(regexp_replace(v.cod, '^0+(?=.)', '')) = u.k limit 1), '')::text,
         exists (select 1 from public."Importados" i
                  where upper(regexp_replace(i.cod_art, '^0+(?=.)', '')) = u.k)
    from u
   where not exists (select 1 from public."GV_Codigo_Baja" b
                      where upper(regexp_replace(b.cod, '^0+(?=.)', '')) = u.k)
   order by 1;
$function$;
grant execute on function public.gv_stock_cod_lista() to anon, authenticated, service_role;

/* centinelas (aplicados: ids 403 y 404) */
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_stock_cod_lista','funcion','GV_Codigo_Baja','v29.77: la lista de códigos que sugiere Ingreso a racks NO ofrece un código dado de baja (865ED -> 865E), igual que el candado gv_stock_cod_conocido.','Luis','v29.77'),
  ('gv_stock_cod_lista','funcion','length\(c\) desc','v29.77: el código se devuelve como lo escriben los maestros (026, no 26): es como se escribe en Movimientos_Stock / GV_Lugar_Item / Importados / OC_Maximos.','Luis','v29.77')
) v(objeto, clase, patron, regla, quien_pidio, version)
 where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);
-- chequeo: select * from public.gv_reglas_perdidas where objeto = 'gv_stock_cod_lista';   -- vacía = todo bien
