# Private match v8 backend notes

## Migration added

The branch now includes `supabase/migrations/202610160001_match_v8_gameplay_fixes.sql`. It reads the current definition of `public.perform_private_turn_action_v2`, checks expected source fragments, and replaces only those fragments. If any required block has drifted, the migration raises an exception instead of silently applying a partial patch.

It updates the gameplay handler to:

- allow characters as well as events to be set;
- add an action to return an owned nested set card to hand;
- allow an owned hand card to become face-up or face-down evidence;
- allow an owned evidence card to return to hand;
- permit manual stunned-to-sleep conversion;
- allow the contact defender to replace the current target with a disguise character from hand, putting the replaced target at the bottom of their deck;
- let each contact participant use at most one cut-in, so the defender's cut-in no longer immediately resolves the contact and the attacker still receives a decision window.

This is a draft migration and has not been executed against a Supabase database. Test it on a staging database first.

## Remaining evidence-area data requirement

The current UI gets face-up cards from `evidence_public_cards` and only a count of face-down evidence. As a result, it cannot render individual action buttons beside each face-down card without additional private data. To complete the requested vertical list for every evidence card, the state getter must expose card instance IDs / face-up flags to the owner only, while continuing to expose no hidden card identity to the opponent.

Run this query in the Supabase SQL Editor and share the function definition:

```sql
select pg_get_functiondef('public.get_private_turn_state_v2(uuid)'::regprocedure);
```

That definition is not in the repository, so the data contract for private evidence cannot safely be patched by guessing.

## Validation status

- JSX edits were checked for the intended source anchors.
- No production Vite build, two-client game test, or database migration execution was available from this environment.
- Do not merge or deploy the branch until the SQL migration has been reviewed and tested on staging, and the evidence getter/UI privacy behavior is finished.
