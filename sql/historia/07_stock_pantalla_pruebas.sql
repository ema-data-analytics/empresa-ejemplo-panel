-- Datos + resultados esperados (calculados en SQL) para probar la logica de la pantalla Stock. Solo lectura.
do $$ declare j text; begin
  select json_build_object(
   's', (select json_agg(x) from api_stock_saldos_v2() x),
   'm', (select json_agg(x) from api_stock_movimientos_v2() x),
   'e', json_build_object(
     'unidades', (select sum(cantidad) from api_stock_saldos_v2()),
     'dep', (select json_object_agg(cod_deposi, q) from (select cod_deposi, sum(cantidad) q from api_stock_saldos_v2() group by 1) z),
     'v_vig', (select round(sum(cantidad * costo_vigente), 2) from api_stock_saldos_v2()),
     'v_fic', (select round(sum(cantidad * costo_ficha), 2) from api_stock_saldos_v2()),
     'v_ppp', (select round(sum(cantidad * costo_ppp), 2) from api_stock_saldos_v2()),
     'art_con', (select count(distinct cod_articu) from api_stock_saldos_v2() where cantidad > 0),
     'neg', (select count(*) from api_stock_saldos_v2() where cantidad < 0),
     'bajo', (select count(*) from api_stock_saldos_v2() where stock_min is not null and cantidad < stock_min),
     'sobre', (select count(*) from api_stock_saldos_v2() where stock_max is not null and cantidad > stock_max),
     'comp', (select sum(comprometida) from api_stock_saldos_v2()),
     'pend', (select sum(pendiente) from api_stock_saldos_v2()),
     'sinsal23', (select count(*) from api_stock_saldos_v2() s left join (select cod_articu, cod_deposi, -sum(cantidad) q from api_stock_movimientos_v2('2023-01-01','2023-12-31') where cod_mov in ('FR','RE','DC','CC') group by 1,2) c using (cod_articu, cod_deposi) where s.cantidad > 0 and not (coalesce(c.q,0) > 0)),
     'cons23', (select -sum(cantidad) from api_stock_movimientos_v2('2023-01-01','2023-12-31') where cod_mov in ('FR','RE','DC','CC')),
     'mes23', (select json_object_agg(m, json_build_array(e, s)) from (select to_char(fecha,'YYYY-MM') m, sum(cantidad) filter (where cantidad >= 0) e, -sum(cantidad) filter (where cantidad < 0) s from api_stock_movimientos_v2('2023-01-01','2023-12-31') group by 1) z),
     'tipo23', (select json_object_agg(cod_mov, n) from (select cod_mov, count(*) n from api_stock_movimientos_v2('2023-01-01','2023-12-31') group by 1) z),
     'rank', (select json_agg(json_build_array(cod_articu, v) order by v desc) from (select cod_articu, round(sum(cantidad * costo_vigente), 2) v from api_stock_saldos_v2() where costo_vigente > 0 group by 1 having round(sum(cantidad * costo_vigente), 2) <> 0 order by 2 desc limit 10) z),
     'dep1', (select count(*) from api_stock_saldos_v2() where cod_deposi = '1'),
     'fr23', (select count(*) from api_stock_movimientos_v2('2023-01-01','2023-12-31') where cod_mov = 'FR'),
     'torn', (select count(*) from api_stock_movimientos_v2() where (articulo || ' ' || cod_articu || ' ' || coalesce(n_comp,'') || ' ' || coalesce(t_comp,'')) ilike '%tornillo%'),
     'cob_vig', (select round(1000 * sum(abs(cantidad)) filter (where costo_vigente > 0) / sum(abs(cantidad))) / 10 from api_stock_saldos_v2())
   ))::text into j;
  raise exception 'DATOS%', j;
end $$;
