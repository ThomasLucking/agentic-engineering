# Issue #105: The same email can be invited to a team twice

## The issue
Nothing stopped a duplicate invite — no validation rule and no database
constraint, so concurrent submissions both inserted.

## Changes
- `app/Http/Requests/StoreInviteRequest.php` — scoped `Rule::unique` on
  email + team → duplicates rejected with a 422.
- `database/migrations/2024_05_02_000000_add_unique_index_to_invites.php` — unique
  index on `(team_id, email)` → closes the race two simultaneous requests could
  otherwise slip through.

## How it fits together
Request → `StoreInviteRequest` rejects a duplicate before the insert → the unique
index backstops the validation for concurrent writes → controller stores the invite.
