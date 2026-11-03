-- Solea : ordre des pièces propre à chaque utilisateur (section 'rooms' de device_layouts).
-- La suppression d'une pièce reste réservée aux gestionnaires (RLS existante sur rooms) ;
-- ses appareils passent « sans pièce » (room_id on delete set null) ou sont déplacés avant.
do $$
declare c text;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.device_layouts'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%section%'
  loop
    execute format('alter table public.device_layouts drop constraint %I', c);
  end loop;
end $$;

alter table public.device_layouts
  add constraint device_layouts_section_check
  check (section ~ '^(favorites|devices|scenes|rooms|room:(none|[0-9a-f-]{36}))$');

-- Une pièce supprimée disparaît des ordres enregistrés.
create or replace function public.cleanup_room_layouts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.device_layouts where home_id = old.home_id and section = 'room:' || old.id::text;
  update public.device_layouts set item_ids = array_remove(item_ids, old.id), updated_at = now()
    where home_id = old.home_id and section = 'rooms' and old.id = any(item_ids);
  return old;
end $$;

drop trigger if exists trg_room_layouts_cleanup on public.rooms;
create trigger trg_room_layouts_cleanup after delete on public.rooms
  for each row execute function public.cleanup_room_layouts();
