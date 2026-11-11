-- Paso 6: Cobranzas · antigüedad de deuda de clientes. Solo agrega objetos nuevos; no toca nada existente.
-- Datos de Tango:
--   gva46 = cuotas (vencimientos) de cada comprobante; gva07 = cobros aplicados a cada cuota (por comprobante + fecha de vencimiento);
--   gva12 = comprobantes de cuenta corriente; gva14 = ficha del cliente; gva23 = vendedores.
-- Lo pendiente de una cuota = importe de la cuota − lo aplicado A ESA CUOTA (mismo comprobante y misma fecha de vencimiento).
--   (La función vieja api_cartera_por_cliente, copiada de DISSAN, restaba a cada cuota todo lo cobrado del comprobante: con
--    facturas en varias cuotas da menos deuda de la que hay. No se toca; esta es la correcta.)
-- Cada cobro trae su fecha (f_comp_can): la pantalla reconstruye la deuda a cualquier fecha de corte (mes anterior, año anterior).
-- Saldo de cuenta corriente = débitos − créditos de gva12 sin anulados (ANU) ni contado (***). Coincide con saldo_cc de la ficha.

create or replace function public.api_cobranzas_v2()
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  with comp as (
    select g.t_comp, g.n_comp, g.cod_client, g.cod_vended, g.fecha_emis::date fecha_emis, g.estado, g.tcomp_in_v,
           case when upper(trim(coalesce(g.tcomp_in_v, ''))) in ('CC', 'RC', 'NC') then -1 else 1 end signo,
           coalesce(g.importe, 0) importe
    from public.gva12 g
    where coalesce(g.estado, '') <> 'ANU'),
  cuo as (
    select v.id_gva46, v.t_comp, v.n_comp, c.cod_client, c.cod_vended, c.fecha_emis, v.fecha_vto::date fecha_vto,
           coalesce(v.importe_vt, 0) importe_vt, v.estado_vto, c.estado estado_comp,
           row_number() over (partition by v.t_comp, v.n_comp order by v.fecha_vto, v.id_gva46) cuota,
           count(*) over (partition by v.t_comp, v.n_comp) cuotas
    from public.gva46 v
    join comp c on c.t_comp = v.t_comp and c.n_comp = v.n_comp),
  apl as (
    select a.t_comp, a.n_comp, a.fecha_vto::date fecha_vto, sum(coalesce(a.import_can, 0)) aplicado, max(a.f_comp_can::date) ultimo,
           jsonb_agg(jsonb_build_array(a.f_comp_can::date, round(coalesce(a.import_can, 0), 2), trim(a.t_comp_can), trim(a.n_comp_can))
                     order by a.f_comp_can, a.n_comp_can) lista
    from public.gva07 a group by 1, 2, 3),
  cli as (
    select x.cod_client from comp x group by 1
    union select k.cod_client from public.gva14 k)
  select jsonb_build_object(
    'generado', now(),
    'clientes', (select coalesce(jsonb_agg(jsonb_build_object(
        'cod_client', c.cod_client,
        'cliente', coalesce(nullif(trim(k.razon_soci), ''), case when c.cod_client = '000000' then 'Clientes ocasionales' else 'Cliente ' || c.cod_client end),
        'cuit', nullif(trim(k.cuit), ''),
        'telefono', nullif(trim(k.telefono_1), ''),
        'email', nullif(trim(k.e_mail), ''),
        'cod_vended', nullif(trim(k.cod_vended), ''),
        'vendedor', (select trim(y.nombre_ven) from public.gva23 y where y.cod_vended = k.cod_vended limit 1),
        'saldo_ficha', round(k.saldo_cc, 2),
        'tiene_ficha', k.cod_client is not null) order by c.cod_client), '[]'::jsonb)
      from cli c left join public.gva14 k on k.cod_client = c.cod_client),
    'cuotas', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', q.id_gva46, 't_comp', trim(q.t_comp), 'n_comp', trim(q.n_comp), 'cod_client', q.cod_client,
        'cod_vended', nullif(trim(q.cod_vended), ''),
        'vendedor', (select trim(y.nombre_ven) from public.gva23 y where y.cod_vended = q.cod_vended limit 1),
        'cuota', q.cuota, 'cuotas', q.cuotas, 'fecha_emis', q.fecha_emis, 'fecha_vto', q.fecha_vto,
        'importe_vt', round(q.importe_vt, 2), 'estado_vto', q.estado_vto, 'estado_comp', q.estado_comp,
        'aplicado', round(coalesce(a.aplicado, 0), 2), 'ultimo_cobro', a.ultimo, 'cobros', coalesce(a.lista, '[]'::jsonb))
        order by q.fecha_vto, q.t_comp, q.n_comp, q.cuota), '[]'::jsonb)
      from cuo q left join apl a on a.t_comp = q.t_comp and a.n_comp = q.n_comp and a.fecha_vto = q.fecha_vto),
    'comprobantes', (select coalesce(jsonb_agg(jsonb_build_object(
        't_comp', trim(c.t_comp), 'n_comp', trim(c.n_comp), 'cod_client', c.cod_client, 'fecha', c.fecha_emis,
        'tipo_interno', trim(c.tcomp_in_v), 'estado', c.estado, 'importe', round(c.signo * c.importe, 2))
        order by c.fecha_emis, c.t_comp, c.n_comp), '[]'::jsonb)
      from comp c where coalesce(c.estado, '') <> '***'),
    'ventas', (select coalesce(jsonb_agg(jsonb_build_object('cod_client', z.cod_client, 'mes', z.mes, 'venta', z.venta) order by z.cod_client, z.mes), '[]'::jsonb)
      from (select v.cod_client, date_trunc('month', v.fecha)::date mes, round(sum(v.importe_con_signo), 2) venta
            from public.vista_venta_linea_v2 v where v.estado_comprobante <> 'ANU' group by 1, 2) z)
  );
$$;
revoke all on function public.api_cobranzas_v2() from public, anon;
grant execute on function public.api_cobranzas_v2() to authenticated;
comment on function public.api_cobranzas_v2() is 'Cobranzas: clientes, cuotas con sus cobros fechados, comprobantes de cuenta corriente y ventas netas por mes. 07/10/2026.';

-- Seguimiento de cobranza: cada gestión queda atada al CÓDIGO del cliente, con fecha, responsable, estado y compromiso de pago.
-- No se borra: si algo se cargó mal, se agrega una gestión nueva que lo corrige.
create table if not exists public.cobranza_seguimiento (
  id               bigserial primary key,
  cod_client       text not null check (length(trim(cod_client)) between 1 and 20),
  fecha            date not null,
  responsable      text check (responsable is null or length(responsable) <= 60),
  estado           text not null check (estado in ('En gestión', 'Compromiso de pago', 'Plan de pagos', 'Pago sin imputar', 'Intimación / legal', 'Cancelado')),
  texto            text not null check (length(trim(texto)) between 1 and 1000),
  compromiso_fecha date,
  compromiso_monto numeric(18,2) check (compromiso_monto is null or compromiso_monto >= 0),
  creado           timestamptz not null default now(),
  creado_por       uuid default auth.uid());
alter table public.cobranza_seguimiento enable row level security;
revoke all on public.cobranza_seguimiento from public, anon, authenticated;
revoke all on sequence public.cobranza_seguimiento_id_seq from public, anon, authenticated;

create or replace function public.api_cobranzas_seguimiento_v2()
returns table (id bigint, cod_client text, fecha date, responsable text, estado text, texto text,
  compromiso_fecha date, compromiso_monto numeric, creado timestamptz, cargado_por text)
language sql stable security definer set search_path = public, pg_temp as $$
  select s.id, s.cod_client, s.fecha, s.responsable, s.estado, s.texto, s.compromiso_fecha, s.compromiso_monto, s.creado,
         coalesce(p.nombre, 'sistema')
  from public.cobranza_seguimiento s left join public.perfiles p on p.id = s.creado_por
  order by s.fecha desc, s.id desc;
$$;

create or replace function public.api_cobranzas_seguimiento_agregar_v2(p_cod_client text, p_fecha date, p_responsable text, p_estado text,
  p_texto text, p_compromiso_fecha date default null, p_compromiso_monto numeric default null)
returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare nuevo bigint;
begin
  if not exists (select 1 from public.perfiles p where p.id = auth.uid() and p.activo) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if nullif(trim(coalesce(p_texto, '')), '') is null then raise exception 'Falta el comentario'; end if;
  if not exists (select 1 from public.gva14 k where k.cod_client = p_cod_client)
     and not exists (select 1 from public.gva12 g where g.cod_client = p_cod_client) then
    raise exception 'No existe el cliente %', p_cod_client;
  end if;
  insert into public.cobranza_seguimiento (cod_client, fecha, responsable, estado, texto, compromiso_fecha, compromiso_monto)
  values (p_cod_client, coalesce(p_fecha, current_date), nullif(trim(coalesce(p_responsable, '')), ''), p_estado, trim(p_texto),
          p_compromiso_fecha, p_compromiso_monto)
  returning id into nuevo;
  return nuevo;
end $$;

revoke all on function public.api_cobranzas_seguimiento_v2(), public.api_cobranzas_seguimiento_agregar_v2(text, date, text, text, text, date, numeric) from public, anon;
grant execute on function public.api_cobranzas_seguimiento_v2(), public.api_cobranzas_seguimiento_agregar_v2(text, date, text, text, text, date, numeric) to authenticated;
comment on function public.api_cobranzas_seguimiento_v2() is 'Seguimiento de cobranza por cliente. 07/10/2026.';
comment on function public.api_cobranzas_seguimiento_agregar_v2(text, date, text, text, text, date, numeric) is 'Agrega una gestión de cobranza (usuario activo). 07/10/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;
