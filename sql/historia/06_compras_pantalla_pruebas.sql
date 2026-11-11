-- Datos + resultados esperados (calculados en SQL) para probar la logica de la pantalla Compras. Solo lectura.
do $$ declare j text; a text; pv text; begin
  select cod_articu into a from api_compras_articulos_v2() where t_comp <> 'N/C' group by 1 order by count(*) desc, 1 limit 1;
  select cod_provee into pv from api_compras_comprobantes_v2() group by 1 order by sum(total) desc limit 1;
  select json_build_object(
   'c', (select json_agg(x) from api_compras_comprobantes_v2() x),
   'l', (select json_agg(x) from api_compras_articulos_v2() x),
   'art', a, 'prov', pv,
   'e', json_build_object(
     'total', (select round(sum(total),2) from api_compras_comprobantes_v2()),
     'neto', (select round(sum(neto),2) from api_compras_comprobantes_v2()),
     'exento', (select round(sum(exento),2) from api_compras_comprobantes_v2()),
     'iva', (select round(sum(iva),2) from api_compras_comprobantes_v2()),
     'otros', (select round(sum(total-neto-exento-iva),2) from api_compras_comprobantes_v2()),
     'n', (select count(*) from api_compras_comprobantes_v2()),
     'proveedores', (select count(distinct cod_provee) from api_compras_comprobantes_v2()),
     'pendiente', (select round(sum(total),2) from api_compras_comprobantes_v2() where estado = 'PEN'),
     'nc', (select round(sum(total),2) from api_compras_comprobantes_v2() where signo < 0),
     't2023', (select round(sum(total),2) from api_compras_comprobantes_v2('2023-01-01','2023-12-31')),
     'n2023', (select count(*) from api_compras_comprobantes_v2('2023-01-01','2023-12-31')),
     'tprov', (select round(sum(total),2) from api_compras_comprobantes_v2() where cod_provee = pv),
     'meses', (select json_object_agg(m, t) from (select to_char(fecha,'YYYY-MM') m, round(sum(total),2) t from api_compras_comprobantes_v2() group by 1) z),
     'rprov', (select json_agg(json_build_array(cod_provee, t) order by t desc) from (select cod_provee, round(sum(total),2) t from api_compras_comprobantes_v2() group by 1 order by 2 desc limit 10) z),
     'rart', (select json_agg(json_build_array(cod_articu, t) order by t desc) from (select cod_articu, round(sum(importe),2) t from api_compras_articulos_v2() group by 1 order by 2 desc limit 10) z),
     'estados', (select json_object_agg(estado, t) from (select estado, round(sum(total),2) t from api_compras_comprobantes_v2() group by 1) z),
     'art_ncomp', (select count(distinct id_cpa04) from api_compras_articulos_v2() where cod_articu = a),
     'art_nlin', (select count(*) from api_compras_articulos_v2() where cod_articu = a),
     'sin_n', (select count(*) from api_compras_comprobantes_v2() c where not exists (select 1 from api_compras_articulos_v2() l where l.id_cpa04 = c.id_cpa04)),
     'sin_t', (select round(sum(total),2) from api_compras_comprobantes_v2() c where not exists (select 1 from api_compras_articulos_v2() l where l.id_cpa04 = c.id_cpa04)),
     'p_n', (select count(*) from api_compras_articulos_v2() where cod_articu = a and t_comp <> 'N/C'),
     'p_pri', (select precio_unitario from api_compras_articulos_v2() where cod_articu = a and t_comp <> 'N/C' order by fecha, n_comp limit 1),
     'p_ult', (select precio_unitario from api_compras_articulos_v2() where cod_articu = a and t_comp <> 'N/C' order by fecha desc, n_comp desc limit 1),
     'p_min', (select min(precio_unitario) from api_compras_articulos_v2() where cod_articu = a and t_comp <> 'N/C'),
     'p_max', (select max(precio_unitario) from api_compras_articulos_v2() where cod_articu = a and t_comp <> 'N/C'),
     'n_var', (select count(distinct cod_articu) from api_compras_articulos_v2() where t_comp <> 'N/C'),
     'n_exterior', (select count(*) from api_compras_comprobantes_v2() where provincia = 'EXTERIOR'),
     'n_messina', (select count(*) from api_compras_comprobantes_v2() c where c.proveedor ilike '%messina%' or c.n_comp ilike '%messina%'
                     or exists (select 1 from api_compras_articulos_v2() l where l.id_cpa04 = c.id_cpa04 and (l.articulo ilike '%messina%' or l.cod_articu ilike '%messina%'))),
     't_2023_pen', (select round(sum(total),2) from api_compras_comprobantes_v2('2023-01-01','2023-12-31') where estado = 'PEN')
   ))::text into j;
  raise exception 'DATOS%', j;
end $$;
