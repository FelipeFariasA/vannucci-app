-- Soldadura entregada: gramos de soldadura que el supervisor entrega al orfebre al registrar una pieza.
-- Cada entrega abre un período que dura hasta la siguiente entrega al mismo orfebre; el indicador
-- cuenta las piezas registradas a ese orfebre en el período.
-- Aditiva: no modifica datos existentes.

alter table public.piezas add column if not exists soldadura_entregada numeric
  check (soldadura_entregada is null or soldadura_entregada > 0);
comment on column public.piezas.soldadura_entregada is 'Gramos de soldadura que el supervisor entregó al orfebre al registrar esta pieza. Marca el inicio de un período de consumo de soldadura.';
create index if not exists piezas_soldadura_idx on public.piezas (orfebre_id, fecha) where soldadura_entregada is not null;

-- El orfebre no puede cambiar la soldadura entregada (igual que el peso objetivo).
create or replace function private.piezas_proteger()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  new.actualizado_en := now();
  if coalesce(private.rol_actual(), '') = 'supervisor' then
    if tg_op = 'UPDATE' and new.estado is distinct from old.estado and new.estado in ('aprobada', 'rechazada') then
      new.revisado_por := (select auth.uid());
      new.revisado_en := now();
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' then
    raise exception 'Solo el supervisor registra piezas.' using errcode = '42501';
  end if;
  new.estado := case when new.estado = 'pendiente' and old.estado in ('asignada', 'rechazada') then 'pendiente' else old.estado end;
  new.orfebre_id := old.orfebre_id;
  new.autor := old.autor;
  new.fecha := old.fecha;
  new.modelo := old.modelo;
  new.modelo_id := old.modelo_id;
  new.codigo_producto := old.codigo_producto;
  new.tono := old.tono;
  new.tipo := old.tipo;
  new.cotizacion := old.cotizacion;
  new.peso_obj := old.peso_obj;
  new.soldadura_entregada := old.soldadura_entregada;
  new.garantia := old.garantia;
  new.cantidad_piedras := old.cantidad_piedras;
  new.comentario := old.comentario;
  new.corregida := old.corregida;
  new.revisado_por := old.revisado_por;
  new.revisado_en := old.revisado_en;
  new.origen := old.origen;
  new.calidad_forzada := old.calidad_forzada;
  new.creado_en := old.creado_en;
  new.oro_devuelto := coalesce(new.oro_devuelto, 0);
  new.maquina_pulido := coalesce(new.maquina_pulido, 0);
  return new;
end;
$function$;
