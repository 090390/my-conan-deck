create index if not exists private_ai_battles_human_user_id_idx
  on public.private_ai_battles(human_user_id);

create index if not exists private_ai_battles_ai_user_id_idx
  on public.private_ai_battles(ai_user_id);
