-- ============================================================================
-- BACKUP · las 54 filas con "L" de Volumen_Articulos cuyo m³ contradecía a su base
-- 2026-09-04, ANTES de alinearlas
-- ============================================================================
-- Estos son los valores VIEJOS. Son los que se consideraron mal cargados: ocho de
-- ellos son la coma corrida diez lugares (523L 0,0510 contra 523 0,0051 · 531L
-- 0,0240 contra 531 0,0024 · 560L 0,0512 contra 560 0,0051 · 521L 0,0024 contra
-- 521 0,0240 · 366EL 0,0016 contra 366E 0,0160 · 539EL · 404EL · 580EL).
--
-- La vista `vista_volumen_articulo_resuelto` ya los ignoraba (el base manda), así
-- que alinearlos NO cambia ningún m³ que la app calcule: sólo deja de haber un
-- número malo en la tabla cruda para el que la consulte directo.
--
-- RESTORE: ejecutar estos updates tal cual.
-- ============================================================================

update public."Volumen_Articulos" set m3=0.003900 where upper(trim(codigo))='027L';
update public."Volumen_Articulos" set m3=0.007800 where upper(trim(codigo))='028L';
update public."Volumen_Articulos" set m3=0.005900 where upper(trim(codigo))='056EL';
update public."Volumen_Articulos" set m3=0.024000 where upper(trim(codigo))='123EL';
update public."Volumen_Articulos" set m3=0.006600 where upper(trim(codigo))='221L';
update public."Volumen_Articulos" set m3=0.006800 where upper(trim(codigo))='222L';
update public."Volumen_Articulos" set m3=0.013600 where upper(trim(codigo))='225L';
update public."Volumen_Articulos" set m3=0.013300 where upper(trim(codigo))='248L';
update public."Volumen_Articulos" set m3=0.008100 where upper(trim(codigo))='260EL';
update public."Volumen_Articulos" set m3=0.006800 where upper(trim(codigo))='312L';
update public."Volumen_Articulos" set m3=0.006700 where upper(trim(codigo))='323L';
update public."Volumen_Articulos" set m3=0.006800 where upper(trim(codigo))='337L';
update public."Volumen_Articulos" set m3=0.011800 where upper(trim(codigo))='355L';
update public."Volumen_Articulos" set m3=0.001600 where upper(trim(codigo))='366EL';
update public."Volumen_Articulos" set m3=0.018500 where upper(trim(codigo))='367EL';
update public."Volumen_Articulos" set m3=0.018500 where upper(trim(codigo))='368EL';
update public."Volumen_Articulos" set m3=0.005100 where upper(trim(codigo))='369EL';
update public."Volumen_Articulos" set m3=0.006800 where upper(trim(codigo))='390L';
update public."Volumen_Articulos" set m3=0.011100 where upper(trim(codigo))='391L';
update public."Volumen_Articulos" set m3=0.006800 where upper(trim(codigo))='393L';
update public."Volumen_Articulos" set m3=0.006800 where upper(trim(codigo))='394L';
update public."Volumen_Articulos" set m3=0.064500 where upper(trim(codigo))='404EL';
update public."Volumen_Articulos" set m3=0.009300 where upper(trim(codigo))='437EL';
update public."Volumen_Articulos" set m3=0.009300 where upper(trim(codigo))='438EL';
update public."Volumen_Articulos" set m3=0.056100 where upper(trim(codigo))='439EL';
update public."Volumen_Articulos" set m3=0.007500 where upper(trim(codigo))='503EL';
update public."Volumen_Articulos" set m3=0.002400 where upper(trim(codigo))='510L';
update public."Volumen_Articulos" set m3=0.005900 where upper(trim(codigo))='514EL';
update public."Volumen_Articulos" set m3=0.002400 where upper(trim(codigo))='521L';
update public."Volumen_Articulos" set m3=0.051000 where upper(trim(codigo))='523L';
update public."Volumen_Articulos" set m3=0.006800 where upper(trim(codigo))='525EL';
update public."Volumen_Articulos" set m3=0.003300 where upper(trim(codigo))='525L';
update public."Volumen_Articulos" set m3=0.024000 where upper(trim(codigo))='531L';
update public."Volumen_Articulos" set m3=0.005900 where upper(trim(codigo))='536EL';
update public."Volumen_Articulos" set m3=0.006300 where upper(trim(codigo))='538EL';
update public."Volumen_Articulos" set m3=0.063000 where upper(trim(codigo))='539EL';
update public."Volumen_Articulos" set m3=0.008100 where upper(trim(codigo))='541EL';
update public."Volumen_Articulos" set m3=0.006700 where upper(trim(codigo))='548L';
update public."Volumen_Articulos" set m3=0.006700 where upper(trim(codigo))='556L';
update public."Volumen_Articulos" set m3=0.004500 where upper(trim(codigo))='558L';
update public."Volumen_Articulos" set m3=0.051200 where upper(trim(codigo))='560L';
update public."Volumen_Articulos" set m3=0.006600 where upper(trim(codigo))='562L';
update public."Volumen_Articulos" set m3=0.002500 where upper(trim(codigo))='564L';
update public."Volumen_Articulos" set m3=0.024000 where upper(trim(codigo))='580EL';
update public."Volumen_Articulos" set m3=0.003300 where upper(trim(codigo))='580L';
update public."Volumen_Articulos" set m3=0.009300 where upper(trim(codigo))='584EL';
update public."Volumen_Articulos" set m3=0.005000 where upper(trim(codigo))='585EL';
update public."Volumen_Articulos" set m3=0.003300 where upper(trim(codigo))='586L';
update public."Volumen_Articulos" set m3=0.005100 where upper(trim(codigo))='598EL';
update public."Volumen_Articulos" set m3=0.009300 where upper(trim(codigo))='601EL';
update public."Volumen_Articulos" set m3=0.003300 where upper(trim(codigo))='814EL';
update public."Volumen_Articulos" set m3=0.005000 where upper(trim(codigo))='816EL';
update public."Volumen_Articulos" set m3=0.004900 where upper(trim(codigo))='817EL';
update public."Volumen_Articulos" set m3=0.011900 where upper(trim(codigo))='870EL';
