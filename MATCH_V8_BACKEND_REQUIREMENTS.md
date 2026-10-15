# Private match RPC work still required

This UI branch is based on `main` and updates `src/components/MatchTurnBoard.jsx`.

The repository does not contain the SQL definition for `public.perform_private_turn_action_v2`; the UI calls it through Supabase. The controls below call these action names, which must be implemented/verified in that function before this draft can be merged or deployed:

- `move_set_card_to_hand`: detach the selected nested set card from its host and return it to the correct owner's hand.
- `move_evidence_to_hand`: move a face-up evidence card into its owner's hand.
- `move_hand_card_to_evidence`: move a hand card into evidence, respecting the `face_up` flag and evidence count.
- `contact_use_disguise`: during a character contact, verify a disguise character in the target player's hand, put that character on the field as the contact target, and put the replaced target on the bottom of that player's deck.
- `contact_use_cutin`: after the defender uses a cut-in, keep the contact pending and set the attacker as the next responder; determine the result only after the attacker uses/passes cut-in.
- `rest_character_manual`: confirm that the existing activate-then-rest UI sequence works for stunned characters without violating other state constraints.
- `set_card_to_field`: confirm that character cards can be set from hand, remove, and deck, not only events.

The UI action names above are explicit integration points, not a claim that the deployed RPC already accepts them. Please do not merge this draft until the RPC behavior is implemented or confirmed.

## Retrieve the existing RPC definition without attaching files

In the Supabase Dashboard's SQL Editor, run:

```sql
select pg_get_functiondef(p.oid)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'perform_private_turn_action_v2';
```

Copy the result into a migration file in the repository (be careful not to include any project secrets). That lets the RPC changes be based on the exact deployed function rather than guessing its existing game-state logic.
