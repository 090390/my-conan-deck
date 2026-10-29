-- The DSL runner is an internal helper invoked by SECURITY DEFINER turn/effect functions.
-- Clients must never call it directly with an arbitrary room ID.
REVOKE ALL ON FUNCTION public.private_card_effect_run_v1(uuid) FROM PUBLIC, anon, authenticated;
