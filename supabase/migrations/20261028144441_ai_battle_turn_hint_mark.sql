alter table public.private_ai_battles
  add column if not exists last_next_hint_turn_number integer;

comment on column public.private_ai_battles.last_next_hint_turn_number is
  'Turn number in which the AI last declared Next Hint; used to prevent repeated file spending in the same turn.';
