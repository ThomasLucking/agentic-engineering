# Issue #106: Let projects be archived instead of deleted

## The issue
Removing a project from the active list meant deleting the row, losing its
history. No column existed to mark a project archived.

## Changes
- `database/migrations/2024_05_10_000000_add_archived_at_to_projects.php` —
  nullable `archived_at` timestamp → archived state without deletion.
- `app/Models/Project.php` — cast `archived_at`, and `scopeActive()` now also
  requires it to be null → archived projects drop out of the active list.
- `app/Http/Requests/StoreProjectRequest.php` — optional `archived_at` date rule
  → the field can be set through the existing endpoint.
- `database/factories/ProjectFactory.php` — default null plus an `archived()`
  state → tests can build either case.

## How it fits together
Request → `StoreProjectRequest` validates `archived_at` → model casts it to a
Carbon instance → `scopeActive()` filters on it wherever the active list is built.
