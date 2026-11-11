-- PRUEBAS Stock (solo lectura: todo se deshace al final)
do $$
declare res text := ''; n numeric; m numeric; k numeric; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  select count(*), sum(cantidad) into k, m from public.api_stock_saldos_v2();
  select count(*), sum(cant_stock) into n, t from public.sta19;
  res := res || 'S01 saldos = filas de sta19 (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'S02 unidades = suma de sta19 (' || t || '): ' || m || case when m = t::numeric then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from (select cod_deposi, sum(cantidad) q from public.api_stock_saldos_v2() group by 1) a
    join (select cod_deposi::text d, sum(cant_stock) q from public.sta19 group by 1) b on b.d = a.cod_deposi where a.q <> b.q;
  res := res || 'S03 unidades por deposito = sta19 (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_stock_saldos_v2() s
    left join (select cod_articu, cod_deposi, sum(cantidad) q from public.api_stock_movimientos_v2() group by 1, 2) m
      on m.cod_articu = s.cod_articu and m.cod_deposi = s.cod_deposi
    where abs(s.cantidad - coalesce(m.q, 0)) >= 0.001;
  res := res || 'S04 cada saldo = suma de sus movimientos (0 diferencias en 113): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*), count(*) filter (where t_comp is null) into k, n from public.api_stock_movimientos_v2();
  res := res || 'S05 movimientos = filas de sta20 (' || (select count(*) from public.sta20) || '): ' || k || ', sin comprobante: ' || n || case when k = (select count(*) from public.sta20) and n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*), count(*) filter (where lleva) into k, n from (select m.cod_articu, m.cod_deposi, bool_or(m.lleva_stock) lleva from public.api_stock_movimientos_v2() m
    where not exists (select 1 from public.api_stock_saldos_v2() s where s.cod_articu = m.cod_articu and s.cod_deposi = m.cod_deposi) group by 1, 2) x;
  res := res || 'S06 pares con movimientos y sin saldo: ' || k || ', de articulos que llevan stock: ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from (select distinct cod_articu, costo_vigente from public.api_stock_saldos_v2() where origen_costo = 'ultima compra real') s
    join (select distinct on (cod_articu) cod_articu, precio_unitario from public.api_compras_articulos_v2() where t_comp <> 'N/C' and coalesce(precio_unitario, 0) > 0 order by cod_articu, fecha desc, n_comp desc) c
      on c.cod_articu = s.cod_articu where c.precio_unitario <> s.costo_vigente;
  res := res || 'S07 costo de ultima compra = ultimo precio de la pantalla Compras (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select string_agg(origen_costo || ':' || c, ', ') into t from (select origen_costo, count(distinct cod_articu) c from public.api_stock_saldos_v2() group by 1 order by 2 desc) x;
  res := res || 'S08 origen del costo vigente (articulos): ' || t || chr(10);
  select count(*) into n from (select distinct s.cod_articu from public.api_stock_saldos_v2() s join public.vista_costo_articulo v using (cod_articu)
    where coalesce(v.costo_unitario, 0) <> coalesce(s.costo_vigente, 0)) x;
  res := res || 'S09 articulos donde el costo vigente corregido difiere de la vista vieja: ' || n || chr(10);
  select round(sum(cantidad * costo_vigente), 2), round(sum(cantidad * costo_ficha), 2), round(sum(cantidad * costo_ppp), 2) into k, m, n from public.api_stock_saldos_v2();
  res := res || 'S10 valorizado: vigente ' || k || ' | ficha ' || m || ' | ppp ' || n || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into k from public.api_stock_saldos_v2();
  select count(*) into m from public.api_stock_movimientos_v2();
  reset role;
  res := res || 'S11 con usuario logueado (' || k || ' saldos, ' || m || ' movimientos): ' || case when k = 113 and m = (select count(*) from public.sta20) then 'PASA' else 'FALLA' end || chr(10);
  res := res || 'S12 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon', 'public.api_stock_saldos_v2()', 'execute') and not has_function_privilege('anon', 'public.api_stock_movimientos_v2(date,date)', 'execute') then 'PASA' else 'FALLA' end || chr(10);
  select count(*) into k from public.api_stock_movimientos_v2('2023-01-01', '2023-12-31');
  select count(*) into n from public.sta20 where fecha_mov::date between '2023-01-01' and '2023-12-31';
  res := res || 'S13 filtro 2023 = sta20 2023 (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) filter (where cantidad < 0), count(*) filter (where stock_min is not null and cantidad < stock_min), count(*) filter (where stock_max is not null and cantidad > stock_max) into k, m, n from public.api_stock_saldos_v2();
  res := res || 'S14 saldos negativos: ' || k || ' | bajo minimo: ' || m || ' | sobre maximo: ' || n || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;
