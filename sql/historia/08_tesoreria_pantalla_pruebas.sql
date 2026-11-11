-- Datos + resultados esperados (calculados en SQL) para probar la logica de la pantalla Tesoreria. Solo lectura.
do $$ declare j text; begin
  select json_build_object(
   'c', (select json_agg(x) from api_tesoreria_cuentas_v2() x),
   'm', (select json_agg(x) from api_tesoreria_movimientos_v2() x),
   'q', (select json_agg(x) from api_tesoreria_cheques_v2() x),
   'e', json_build_object(
     'disp', (select sum(saldo) from api_tesoreria_cuentas_v2() where es_fondo),
     'cajas', (select sum(saldo) from api_tesoreria_cuentas_v2() where grupo = 'Cajas y otros fondos'),
     'bancos', (select sum(saldo) from api_tesoreria_cuentas_v2() where grupo = 'Bancos'),
     'tarj', (select sum(saldo) from api_tesoreria_cuentas_v2() where grupo = 'Tarjetas'),
     'cartera', (select sum(importe) from api_tesoreria_cheques_v2() where estado = 'C'),
     'ing23', (select sum(n) filter (where n > 0) from (select id_sba04, sum(importe) n from api_tesoreria_movimientos_v2('2023-01-01','2023-12-31') where es_fondo group by 1) z),
     'egr23', (select -sum(n) filter (where n < 0) from (select id_sba04, sum(importe) n from api_tesoreria_movimientos_v2('2023-01-01','2023-12-31') where es_fondo group by 1) z),
     'mes23', (select json_object_agg(m, json_build_array(i, e)) from (select to_char(f,'YYYY-MM') m, sum(n) filter (where n > 0) i, -sum(n) filter (where n < 0) e from (select id_sba04, min(fecha) f, sum(importe) n from api_tesoreria_movimientos_v2('2023-01-01','2023-12-31') where es_fondo group by 1) z group by 1) w),
     'saldo_fin23', (select (select sum(saldo_inicial) from api_tesoreria_cuentas_v2() where es_fondo) + (select sum(importe) from api_tesoreria_movimientos_v2() where es_fondo and fecha <= '2023-12-31')),
     'dest23', (select json_agg(json_build_array(cod_cta, v) order by v desc) from (select m.cod_cta, round(sum(m.debe),2) v from api_tesoreria_movimientos_v2() m where not m.es_fondo and m.debe <> 0 and m.id_sba04 in (select id_sba04 from api_tesoreria_movimientos_v2('2023-01-01','2023-12-31') where es_fondo) group by 1 order by 2 desc limit 10) z),
     'orig23', (select json_agg(json_build_array(cod_cta, v) order by v desc) from (select m.cod_cta, round(sum(m.haber),2) v from api_tesoreria_movimientos_v2() m where not m.es_fondo and m.haber <> 0 and m.id_sba04 in (select id_sba04 from api_tesoreria_movimientos_v2('2023-01-01','2023-12-31') where es_fondo) group by 1 order by 2 desc limit 10) z),
     'comp23', (select json_object_agg(cod_comp, n) from (select cod_comp, count(distinct id_sba04) n from api_tesoreria_movimientos_v2('2023-01-01','2023-12-31') where es_fondo group by 1) z),
     'cheq', (select json_object_agg(estado, s) from (select estado, sum(importe) s from api_tesoreria_cheques_v2() group by 1) z),
     'cta5_23', (select count(*) from api_tesoreria_movimientos_v2('2023-01-01','2023-12-31') where cod_cta = 5),
     'txt_deud', (select count(*) from api_tesoreria_movimientos_v2() where concat_ws(' ', leyenda, cuenta, cliente, proveedor, n_comp, comprobante) ilike '%deudores%'),
     'sin_anul', (select count(*) from api_tesoreria_movimientos_v2() where es_fondo and situacion not in ('A','C')),
     'dif', (select count(*) from api_tesoreria_cuentas_v2() where es_fondo and abs(diferencia_ficha) >= 0.01)
   ))::text into j;
  raise exception 'DATOS%', j;
end $$;
