-- Paso 4g: Activo Fijo para la pantalla interactiva. Dos funciones nuevas; no se toca nada existente.
-- Saldos de cada bien: saldo_bien (valor de origen, mejoras, revaluos, amortizacion acumulada) segun la valoracion principal.
-- Valor residual = origen + mejoras + revaluos - amortizacion acumulada. Vida util y metodo: bien_tipo_valoracion, valoracion 1.
-- Movimientos: renglones de los comprobantes de activo fijo (carga inicial, activacion, transferencia, revaluo, mejora, depreciacion, bajas).
-- En la carga inicial Tango guarda la amortizacion acumulada anterior en depreciacion_acumulada_moneda_bien; se devuelve como amortizacion_inicial.
create or replace function public.api_activo_bienes_v2()
returns table (id_bien integer, cod_bien text, bien text, detalle text, rubro text, tipo_bien text, estado text, ubicacion text,
  departamento text, responsable text, fecha_alta date, fecha_activacion date, fecha_baja date, origen text,
  valor_origen numeric, valor_mejora numeric, valor_revaluo numeric, valor_total numeric, amort_acumulada numeric, rdo_baja numeric,
  valor_residual numeric, porc_amortizado numeric, vida_util integer, unidad_vida_util text, vida_util_meses integer,
  porc_depreciable numeric, metodo text, frecuencia text, ultima_amortizacion date, amortizacion_ultimo_anio numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  with d as (
    select r.id_bien, max(c.fecha_comprobante::date) ult
    from public.renglon_comprobante_af r join public.comprobante_af c on c.id_comprobante_af = r.id_comprobante_af
    where c.id_tipo_comprobante_af = 12 and coalesce(r.depreciacion_moneda_bien, 0) <> 0 group by 1),
  u as (
    select r.id_bien, sum(r.depreciacion_moneda_bien) s
    from public.renglon_comprobante_af r join public.comprobante_af c on c.id_comprobante_af = r.id_comprobante_af
    join d on d.id_bien = r.id_bien
    where c.id_tipo_comprobante_af = 12 and c.fecha_comprobante::date > (d.ult - interval '1 year')::date group by 1)
  select b.id_bien::integer, trim(b.cod_bien)::text, trim(b.desc_bien)::text, nullif(trim(b.desc_detallada), '')::text,
         (select trim(x.desc_rubro_bien) from public.rubro_bien x where x.id_rubro_bien = b.id_rubro_bien limit 1)::text,
         (select trim(x.desc_tipo_bien) from public.tipo_bien x where x.id_tipo_bien = b.id_tipo_bien limit 1)::text,
         (select trim(x.desc_estado_bien) from public.estado_bien x where x.id_estado_bien = b.id_estado_bien limit 1)::text,
         (select trim(x.desc_ubicacion_bien) from public.ubicacion_bien x where x.id_ubicacion_bien = b.id_ubicacion_bien limit 1)::text,
         (select to_jsonb(x) ->> 'desc_departamento' from public.departamento x where x.id_departamento = b.id_departamento limit 1)::text,
         (select coalesce(to_jsonb(x) ->> 'desc_responsable', to_jsonb(x) ->> 'nombre_responsable', to_jsonb(x) ->> 'nombre', to_jsonb(x) ->> 'cod_responsable')
            from public.responsable x where x.id_responsable = b.id_responsable limit 1)::text,
         nullif(b.fecha_alta::date, date '1800-01-01'), nullif(b.fecha_activacion::date, date '1800-01-01'), nullif(b.fecha_baja::date, date '1800-01-01'),
         nullif(trim(b.origen_bien), '')::text,
         round(coalesce(s.valor_origen, 0), 2), round(coalesce(s.valor_mejora, 0), 2), round(coalesce(s.valor_revaluo, 0), 2),
         round(coalesce(s.valor_origen, 0) + coalesce(s.valor_mejora, 0) + coalesce(s.valor_revaluo, 0), 2),
         round(coalesce(s.depreciacion_acumulada, 0), 2), round(coalesce(s.rdo_baja, 0), 2),
         round(coalesce(s.valor_origen, 0) + coalesce(s.valor_mejora, 0) + coalesce(s.valor_revaluo, 0) - coalesce(s.depreciacion_acumulada, 0), 2),
         case when coalesce(s.valor_origen, 0) + coalesce(s.valor_mejora, 0) + coalesce(s.valor_revaluo, 0) <> 0
              then round(coalesce(s.depreciacion_acumulada, 0) / (coalesce(s.valor_origen, 0) + coalesce(s.valor_mejora, 0) + coalesce(s.valor_revaluo, 0)) * 100, 1) end,
         v.vida_util::integer,
         (select trim(m.desc_medida) from public.medida m where m.id_medida = v.id_medida_vida_util limit 1)::text,
         case when v.id_medida_vida_util = 10 then v.vida_util * 12 when v.id_medida_vida_util = 9 then v.vida_util end::integer,
         v.porc_depreciacion,
         (select trim(m.desc_metodo_depreciacion) from public.metodo_depreciacion m where m.id_metodo_depreciacion = v.id_metodo_depreciacion limit 1)::text,
         nullif(trim(v.frecuencia_depreciacion), '')::text,
         d.ult, round(coalesce(u.s, 0), 2)
  from public.bien b
  left join public.saldo_bien s on s.id_bien = b.id_bien
  left join lateral (select * from public.bien_tipo_valoracion t where t.id_bien = b.id_bien order by t.id_tipo_valoracion limit 1) v on true
  left join d on d.id_bien = b.id_bien
  left join u on u.id_bien = b.id_bien
  order by 2;
$$;

create or replace function public.api_activo_movimientos_v2(p_desde date default null, p_hasta date default null)
returns table (id_renglon bigint, id_comprobante bigint, fecha date, cod_tipo text, tipo text, nro_comprobante text, estado text,
  id_bien integer, cod_bien text, bien text, valor_origen numeric, valor_mejora numeric, valor_revaluo numeric,
  amortizacion numeric, amortizacion_inicial numeric, rdo_baja numeric, importe_venta numeric, observaciones text)
language sql stable security definer set search_path = public, pg_temp as $$
  select r.id_renglon_comprobante_af::bigint, c.id_comprobante_af::bigint, c.fecha_comprobante::date,
         trim(t.cod_tipo_comprobante_af)::text, trim(t.desc_tipo_comprobante_af)::text,
         coalesce(nullif(trim(c.nro_comprobante::text), ''), c.nro_comprobante_interno::text)::text, trim(c.estado_comprobante_af)::text,
         r.id_bien::integer, trim(b.cod_bien)::text, trim(b.desc_bien)::text,
         round(coalesce(r.valor_origen_moneda_bien, 0), 2), round(coalesce(r.valor_mejora_moneda_bien, 0), 2), round(coalesce(r.valor_revaluo_moneda_bien, 0), 2),
         round(coalesce(r.depreciacion_moneda_bien, 0), 2),
         round(case when t.cod_tipo_comprobante_af = 'CARGA_INI' then coalesce(r.depreciacion_acumulada_moneda_bien, 0) else 0 end, 2),
         round(coalesce(r.rdo_baja_moneda_bien, 0), 2), round(coalesce(r.imp_comprobante_venta, 0), 2),
         nullif(trim(c.observaciones), '')::text
  from public.renglon_comprobante_af r
  join public.comprobante_af c on c.id_comprobante_af = r.id_comprobante_af
  left join public.tipo_comprobante_af t on t.id_tipo_comprobante_af = c.id_tipo_comprobante_af
  left join public.bien b on b.id_bien = r.id_bien
  where (p_desde is null or c.fecha_comprobante::date >= p_desde)
    and (p_hasta is null or c.fecha_comprobante::date <= p_hasta)
  order by 3, 2, 1;
$$;

revoke all on function public.api_activo_bienes_v2(), public.api_activo_movimientos_v2(date, date) from public, anon;
grant execute on function public.api_activo_bienes_v2(), public.api_activo_movimientos_v2(date, date) to authenticated;
comment on function public.api_activo_bienes_v2() is 'Bienes de uso con saldos, vida util y valor residual. 26/09/2026.';
comment on function public.api_activo_movimientos_v2(date, date) is 'Renglones de comprobantes de activo fijo. 26/09/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;
