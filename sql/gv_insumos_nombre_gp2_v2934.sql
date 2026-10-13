-- v29.34 (Thomas, 09/10): «lo válido es lo de GP2 en todos los casos». El nombre de cada insumo de Virgilio
-- vinculado a un componente de GP2 pasa a ser la descripción de GP2. El CÓDIGO no cambia (el stock vive por código).
-- Flejes NO: su nombre en Virgilio es la medida (84 X 1,75) y el orden del operario la lee (_insMedida); el número
-- de fleje ya es el código. El stock se corrige con el conteo del martes 13/10.

-- BACKUP (restore-ready): nombres antes del cambio
-- update public."Insumos" set nombre = v.n from (values
--  (209,'Caja Nº 1'),(253,'Caja Nº 10'),(210,'Caja Nº 12'),(254,'Caja Nº 13'),(255,'Caja Nº 15'),(256,'Caja Nº 16'),
--  (250,'Caja Nº 2'),(46,'Caja Nº 22'),(257,'Caja Nº 29'),(251,'Caja Nº 6'),(252,'Caja Nº 7'),
--  (94,'ABS'),(95,'ALTO IMPACTO'),(97,'NYLON CON CARGA AL 25'),(100,'PE POLIETILENO (if33)'),
--  (101,'POLIPROPILENO (2630)'),(102,'PS POLIESTIRENO (h555)'),
--  (174,'C Sacacorcho 520 Crom'),(184,'Manija  Redonda Crom.'),
--  (176,'Cpo Uña Crom. LK C/M'),(196,'Batidor pera crudo'),(197,'Mango plano 501 p/ cromar')
-- ) v(id,n) where "Insumos".id = v.id;

with src as (
  select i.id, c.descripcion
    from public."Insumos" i
    join "GP2".importado_virgilio_componente m on m.cod_virgilio = upper(btrim(i.cod))
    join "GP2".componente c on c.id = m.componente_id
   where i.id in (209,253,210,254,255,256,250,46,257,251,252,94,95,97,100,101,102,174,184)
  union all
  select i.id, c.descripcion
    from public."Insumos" i
    join (values (176,86),(196,4),(197,5)) v(iid, comp) on v.iid = i.id
    join "GP2".componente c on c.id = v.comp
), u as (
  update public."Insumos" i set nombre = s.descripcion from src s
   where i.id = s.id and i.nombre is distinct from s.descripcion
  returning i.id, i.cod, i.nombre
) select * from u order by id;
