# Private match v8 backend notes

## Migrations added

Apply and review the two migrations in filename order on a staging database before production:

1. `supabase/migrations/202610160001_match_v8_gameplay_fixes.sql`
   - Patches `public.perform_private_turn_action_v2` using expected source fragments.
   - Allows characters as well as events to be set.
   - Adds actions to return an owned nested set card to hand, transfer an owned hand card to evidence face-up/down, and return owned evidence to hand.
   - Allows manual stunned-to-sleep conversion.
   - Adds defender-side disguise during the contact-guard window, moving the replaced target to the defender's deck bottom.
   - Lets attacker and defender each use at most one cut-in, leaving the pending contact open for the attacker's decision after the defender uses a cut-in.

2. `supabase/migrations/202610160002_match_v8_private_evidence.sql`
   - Patches `public.get_private_turn_state_v2` to return `evidence_private_cards` only on the signed-in user's own board. The opponent board receives an empty array so hidden card identities are not leaked.
   - Allows face-down evidence to move to deck bottom or remove only when the current player owns that evidence. Opponent evidence remains movable only when face-up/public.

The migration scripts check expected source fragments and stop with an exception if the source shape has drifted. They have not been executed against a Supabase database.

## Evidence UI

`src/components/MatchTurnBoard.jsx` now renders the owner's full evidence list from top to bottom using consistent card dimensions. Face-down cards remain visually hidden but have their own action buttons. Opponent face-down evidence remains represented only by anonymous backs and a count; opponent public evidence retains its available actions.

## Validation status

- Relevant JSX source anchors and migration insertions were checked after writing the files.
- No production Vite build, two-client game test, or database migration execution was available from this environment.
- Review both migrations and test them on staging before merging or deploying. In particular, confirm your existing `resolve_private_character_contact` function still accepts the updated pending-action JSON fields and compare the final AP results for all four cut-in combinations (neither player, defender only, attacker only, both players).
