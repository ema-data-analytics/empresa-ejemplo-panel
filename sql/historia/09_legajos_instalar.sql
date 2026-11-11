-- Paso 4f: Legajos y sueldos para la pantalla interactiva. Funciones nuevas; no se toca nada existente.
-- Los sueldos son datos sensibles: estas funciones solo devuelven datos a usuarios activos con rol super o admin.
-- No se devuelven CUIL, documento, domicilio, telefono ni email.
-- Totales del recibo (tot_liquidacion): neto = haberes + asignaciones + no remunerativo - retenciones.
-- Tipos de concepto: 1 haber, 2 retencion, 3 asignacion, 4 no remunerativo, 5 ganancias, 6 devolucion de ganancias, 7 redondeo,
-- 8 contribucion patronal, 9 auxiliar. Tango no guarda el costo laboral (tot_costo_laboral vacio): se calcula como
-- haberes + asignaciones + no remunerativo + contribuciones patronales.
create or replace function public.seg_puede_ver_sueldos() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.perfiles p where p.id = auth.uid() and p.activo and p.rol in ('super', 'admin'));
$$;

create or replace function public.api_legajos_v2()
returns table (id_legajo integer, nro_legajo text, nombre text, sexo text, edad integer, categoria text, convenio text,
  departamento text, puesto text, fecha_ingreso date, fecha_egreso date, motivo_egreso text, activo boolean,
  antiguedad_anios numeric, sueldo_ficha numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  select l.id_legajo::integer, trim(l.nro_legajo::text),
         trim(coalesce(l.apellido, '')) || coalesce(', ' || nullif(trim(l.nombre), ''), ''),
         nullif(trim(l.sexo::text), ''),
         case when nullif(l.fecha_nacimiento::date, date '1800-01-01') is not null
              then date_part('year', age(current_date, l.fecha_nacimiento::date))::integer end,
         (select to_jsonb(x) ->> 'desc_categoria' from public.categoria x where x.id_categoria = l.id_categoria limit 1),
         (select to_jsonb(x) ->> 'desc_convenio' from public.convenio x where x.id_convenio = l.id_convenio limit 1),
         (select to_jsonb(x) ->> 'desc_departamento' from public.departamento x where x.id_departamento = l.id_departamento limit 1),
         (select coalesce(to_jsonb(x) ->> 'desc_puesto', to_jsonb(x) ->> 'descripcion') from public.puesto x where x.id_puesto = l.id_puesto limit 1),
         ie.ing, ie.egr,
         (select coalesce(to_jsonb(x) ->> 'desc_motivo_egreso', to_jsonb(x) ->> 'descripcion') from public.motivo_egreso x where x.id_motivo_egreso = ie.id_motivo_egreso limit 1),
         ie.egr is null,
         round((coalesce(ie.egr, current_date) - ie.ing) / 365.25, 1),
         nullif(l.sueldo, 0)::numeric
  from public.legajo_cloud l
  left join lateral (
    select nullif(e.fecha_ingreso::date, date '1800-01-01') ing, nullif(e.fecha_egreso::date, date '1800-01-01') egr, e.id_motivo_egreso
    from public.ingreso_egreso e where e.id_legajo = l.id_legajo order by e.fecha_ingreso desc limit 1) ie on true
  where public.seg_puede_ver_sueldos()
  order by 3;
$$;

create or replace function public.api_legajos_liquidaciones_v2(p_desde date default null, p_hasta date default null)
returns table (id_tot_liquidacion bigint, id_legajo integer, periodo date, fecha_pago date, tipo_liquidacion integer, tipo text,
  nro_recibo text, haberes numeric, asignaciones numeric, no_remunerativo numeric, retenciones numeric, ganancias numeric,
  neto numeric, contribuciones numeric, costo_laboral numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  select t.id_tot_liquidacion::bigint, t.id_legajo::integer, date_trunc('month', d.per_liquidacion)::date,
         nullif(d.fecha_pago::date, date '1800-01-01'), d.tipo_liquidacion::integer,
         coalesce(tl.desc_tipo_liquidacion, 'Tipo ' || d.tipo_liquidacion)::text, t.nro_recibo::text,
         round(coalesce(t.tot_haberes, 0), 2), round(coalesce(t.tot_asignaciones, 0), 2), round(coalesce(t.tot_no_remunerativo, 0), 2),
         round(coalesce(t.tot_retenciones, 0), 2), round(coalesce(g.gan, 0), 2), round(coalesce(t.tot_neto, 0), 2),
         round(coalesce(t.tot_aportes, 0), 2),
         round(coalesce(t.tot_haberes, 0) + coalesce(t.tot_asignaciones, 0) + coalesce(t.tot_no_remunerativo, 0) + coalesce(t.tot_aportes, 0), 2)
  from public.tot_liquidacion t
  join public.dato_fijo d on d.id_dato_fijo = t.id_dato_fijo
  left join public.tipo_liquidacion tl on tl.tipo_liquidacion = d.tipo_liquidacion
  left join (select l.id_tot_liquidacion, sum(l.imp_liquidado) gan from public.liquidacion l join public.concepto c on c.id_concepto = l.id_concepto
             where c.tipo_concepto = 5 group by 1) g on g.id_tot_liquidacion = t.id_tot_liquidacion
  where public.seg_puede_ver_sueldos()
    and (p_desde is null or d.per_liquidacion::date >= p_desde)
    and (p_hasta is null or d.per_liquidacion::date <= p_hasta)
  order by 3, 2, 1;
$$;

-- Conceptos sumados por mes, concepto y tipo de liquidacion (para rankings; sin legajo).
create or replace function public.api_legajos_conceptos_v2(p_desde date default null, p_hasta date default null)
returns table (periodo date, tipo_liquidacion integer, id_concepto integer, nro_concepto integer, concepto text, tipo_concepto integer,
  tipo_concepto_nombre text, importe numeric, legajos bigint, renglones bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  select date_trunc('month', d.per_liquidacion)::date, d.tipo_liquidacion::integer, c.id_concepto::integer, c.nro_concepto::integer,
         trim(c.desc_concepto)::text, c.tipo_concepto::integer, coalesce(tc.desc_tipo_concepto, 'Tipo ' || c.tipo_concepto)::text,
         round(sum(coalesce(l.imp_liquidado, 0)), 2), count(distinct l.id_legajo), count(*)
  from public.liquidacion l
  join public.tot_liquidacion t on t.id_tot_liquidacion = l.id_tot_liquidacion
  join public.dato_fijo d on d.id_dato_fijo = t.id_dato_fijo
  join public.concepto c on c.id_concepto = l.id_concepto
  left join public.tipo_concepto tc on tc.tipo_concepto = c.tipo_concepto
  where public.seg_puede_ver_sueldos()
    and (p_desde is null or d.per_liquidacion::date >= p_desde)
    and (p_hasta is null or d.per_liquidacion::date <= p_hasta)
  group by 1, 2, 3, 4, 5, 6, 7
  order by 1, 2, 4;
$$;

-- Un recibo: sus renglones.
create or replace function public.api_legajos_recibo_v2(p_id_tot_liquidacion bigint)
returns table (nro_concepto integer, concepto text, tipo_concepto integer, tipo_concepto_nombre text, cantidad numeric, valor numeric, importe numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.nro_concepto::integer, trim(c.desc_concepto)::text, c.tipo_concepto::integer, coalesce(tc.desc_tipo_concepto, 'Tipo ' || c.tipo_concepto)::text,
         round(coalesce(l.cant_liquidado, 0), 2), round(coalesce(l.valor_liquidado, 0), 2), round(coalesce(l.imp_liquidado, 0), 2)
  from public.liquidacion l
  join public.concepto c on c.id_concepto = l.id_concepto
  left join public.tipo_concepto tc on tc.tipo_concepto = c.tipo_concepto
  where public.seg_puede_ver_sueldos() and l.id_tot_liquidacion = p_id_tot_liquidacion
  order by c.tipo_concepto, c.nro_concepto;
$$;

revoke all on function public.seg_puede_ver_sueldos(), public.api_legajos_v2(), public.api_legajos_liquidaciones_v2(date, date),
  public.api_legajos_conceptos_v2(date, date), public.api_legajos_recibo_v2(bigint) from public, anon;
grant execute on function public.seg_puede_ver_sueldos(), public.api_legajos_v2(), public.api_legajos_liquidaciones_v2(date, date),
  public.api_legajos_conceptos_v2(date, date), public.api_legajos_recibo_v2(bigint) to authenticated;
comment on function public.api_legajos_v2() is 'Legajos sin datos personales sensibles. Solo super y admin. 26/09/2026.';
comment on function public.api_legajos_liquidaciones_v2(date, date) is 'Recibos de sueldo con costo laboral calculado. Solo super y admin. 26/09/2026.';
comment on function public.api_legajos_conceptos_v2(date, date) is 'Conceptos de sueldo por mes. Solo super y admin. 26/09/2026.';
comment on function public.api_legajos_recibo_v2(bigint) is 'Renglones de un recibo. Solo super y admin. 26/09/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;
