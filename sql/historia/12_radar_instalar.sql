-- Paso 5: Radar (tablero central). Dos funciones nuevas de resumen; no se toca nada existente.
-- Leen de las funciones _v2 ya probadas de cada modulo, asi las cifras son las mismas que en cada pantalla.
-- Los datos de sueldos solo salen para usuarios super o admin (seg_puede_ver_sueldos); para el resto vienen vacios (null).

-- 1) Foto de hoy: una sola fila.
create or replace function public.api_radar_hoy_v2()
returns table (disponibilidades numeric, cajas numeric, bancos numeric, valores_depositar numeric, tarjetas numeric, cheques_cartera numeric, n_cheques_cartera bigint,
  cheques_rechazados numeric, n_cheques_rechazados bigint, cuentas_ficha_distinta bigint,
  stock_valorizado numeric, stock_unidades numeric, stock_negativos bigint, stock_bajo_minimo bigint, stock_sin_costo bigint,
  af_valor_origen numeric, af_amortizado numeric, af_residual numeric, af_ultima_amortizacion date, af_bienes bigint,
  puede_ver_sueldos boolean, dotacion_activa bigint, ultimo_mes_sueldos date,
  iva_ventas_sin_cuit bigint, afip_comprobantes bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  with c as (select * from public.api_tesoreria_cuentas_v2()),
       q as (select * from public.api_tesoreria_cheques_v2()),
       s as (select * from public.api_stock_saldos_v2()),
       b as (select * from public.api_activo_bienes_v2()),
       v as (select * from public.api_iva_ventas_v2(null, null))
  select round((select coalesce(sum(saldo), 0) from c where es_fondo), 2),
         round((select coalesce(sum(saldo), 0) from c where grupo = 'Cajas y otros fondos'), 2),
         round((select coalesce(sum(saldo), 0) from c where grupo = 'Bancos'), 2),
         round((select coalesce(sum(saldo), 0) from c where grupo = 'Valores a depositar'), 2),
         round((select coalesce(sum(saldo), 0) from c where grupo = 'Tarjetas'), 2),
         round((select coalesce(sum(importe), 0) from q where estado = 'C'), 2), (select count(*) from q where estado = 'C'),
         round((select coalesce(sum(importe), 0) from q where estado = 'R'), 2), (select count(*) from q where estado = 'R'),
         (select count(*) from c where abs(diferencia_ficha) >= 0.01),
         round((select coalesce(sum(cantidad * costo_vigente), 0) from s where costo_vigente is not null), 2),
         round((select coalesce(sum(cantidad), 0) from s), 2),
         (select count(*) from s where cantidad < 0),
         (select count(*) from s where stock_min is not null and cantidad < stock_min),
         (select count(*) from s where cantidad <> 0 and costo_vigente is null),
         round((select coalesce(sum(valor_total), 0) from b), 2), round((select coalesce(sum(amort_acumulada), 0) from b), 2),
         round((select coalesce(sum(valor_residual), 0) from b), 2), (select max(ultima_amortizacion) from b), (select count(*) from b),
         public.seg_puede_ver_sueldos(),
         case when public.seg_puede_ver_sueldos() then (select count(*) from public.api_legajos_v2() where activo) end,
         (select max(periodo) from public.api_legajos_liquidaciones_v2(null, null)),
         (select count(*) from v where regexp_replace(coalesce(cuit, ''), '[^0-9]', '', 'g') !~ '[1-9]'),
         (select count(*) from public.comprobante_afip_compras);
$$;

-- 2) Mes a mes: sueldos, amortizaciones, IVA y movimiento de fondos (ingresos y egresos netos por comprobante, como en Tesoreria).
create or replace function public.api_radar_mensual_v2()
returns table (mes date, costo_laboral numeric, neto_sueldos numeric, personas bigint, amortizacion numeric,
  iva_debito numeric, iva_credito numeric, ingresos_fondos numeric, egresos_fondos numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  with l as (select date_trunc('month', periodo)::date m, sum(costo_laboral) cl, sum(neto) ne,
                    count(distinct id_legajo) filter (where tipo_liquidacion <> 9) pe
             from public.api_legajos_liquidaciones_v2(null, null) group by 1),
       a as (select date_trunc('month', fecha)::date m, sum(amortizacion) am from public.api_activo_movimientos_v2(null, null) where cod_tipo = 'DEPRECIA' group by 1),
       iv as (select date_trunc('month', fecha)::date m, sum(iva) d from public.api_iva_ventas_v2(null, null) group by 1),
       ic as (select date_trunc('month', fecha)::date m, sum(iva) c from public.api_iva_compras_v2(null, null) group by 1),
       fc as (select id_sba04, min(fecha) f, sum(importe) n from public.api_tesoreria_movimientos_v2(null, null) where es_fondo group by 1),
       t as (select date_trunc('month', f)::date m, sum(n) filter (where n > 0) ing, -sum(n) filter (where n < 0) egr from fc group by 1),
       meses as (select m from l union select m from a union select m from iv union select m from ic union select m from t)
  select meses.m, round(l.cl, 2), round(l.ne, 2), l.pe, round(a.am, 2), round(iv.d, 2), round(ic.c, 2), round(t.ing, 2), round(t.egr, 2)
  from meses
  left join l on l.m = meses.m left join a on a.m = meses.m left join iv on iv.m = meses.m left join ic on ic.m = meses.m left join t on t.m = meses.m
  order by 1;
$$;

revoke all on function public.api_radar_hoy_v2(), public.api_radar_mensual_v2() from public, anon;
grant execute on function public.api_radar_hoy_v2(), public.api_radar_mensual_v2() to authenticated;
comment on function public.api_radar_hoy_v2() is 'Radar: foto de hoy de todos los modulos. Sueldos solo super/admin. 26/09/2026.';
comment on function public.api_radar_mensual_v2() is 'Radar: sueldos, amortizaciones, IVA y fondos por mes. Sueldos solo super/admin. 26/09/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;
