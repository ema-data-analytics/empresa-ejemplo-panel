-- Datos + resultados esperados (calculados en SQL) para probar la logica de la pantalla IVA. Solo lectura.
do $$ declare j text; begin
  create temp table _v on commit drop as select * from api_iva_ventas_v2();
  create temp table _c on commit drop as select * from api_iva_compras_v2();
  select json_build_object(
   'v', (select json_agg(x) from _v x), 'c', (select json_agg(x) from _c x),
   'e', json_build_object(
     'k', json_build_array((select sum(iva) from _v), (select sum(iva) from _c), (select sum(gravado) from _v), (select sum(neto) from _c), (select sum(otros) from _c),
                           (select count(*) from _v where regexp_replace(coalesce(cuit, ''), '[^0-9]', '', 'g') !~ '[1-9]')),
     'anio', (select json_object_agg(a, json_build_array(d, c)) from (select a, sum(d) d, sum(c) c from (select to_char(fecha, 'YYYY') a, iva d, 0 c from _v union all select to_char(fecha, 'YYYY'), 0, iva from _c) x group by 1) y),
     'mes23', (select json_object_agg(a, json_build_array(d, c)) from (select a, sum(d) d, sum(c) c from (select to_char(fecha, 'YYYY-MM') a, iva d, 0 c from _v where fecha between '2023-01-01' and '2023-12-31' union all select to_char(fecha, 'YYYY-MM'), 0, iva from _c where fecha between '2023-01-01' and '2023-12-31') x group by 1) y),
     'cli', (select json_agg(json_build_array(k, s) order by s desc) from (select coalesce(cod_client, cliente, 'Sin nombre') k, sum(iva) s from _v group by 1 having sum(iva) <> 0 order by 2 desc limit 10) z),
     'alic', json_build_array((select sum(iva_21) from _c), (select sum(iva_105) from _c), (select sum(iva_27) from _c), (select sum(iva_otras) from _c)),
     'tipo', (select json_object_agg(k, json_build_array(n, s)) from (select 'ventas:' || t_comp k, count(*) n, sum(iva) s from _v group by 1 union all select 'compras:' || t_comp, count(*), sum(iva) from _c group by 1) z),
     'v23', (select count(*) from _v where fecha between '2023-01-01' and '2023-12-31'),
     'nc', (select count(*) from _c where t_comp = 'N/C')
   ))::text into j;
  raise exception 'DATOS%', j;
end $$;
