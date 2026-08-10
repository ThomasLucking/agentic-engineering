# Issue #104: Expose active user counts per team

## The issue
No endpoint reported per-team active user counts; ops was querying the database
by hand.

## Changes
- `app/Http/Controllers/TeamStatsController.php` — new single-action controller
  returning the count → satisfies the JSON shape ops asked for.
- `routes/api.php` — register the route behind `auth:sanctum` → only
  authenticated members reach it.

## How it fits together
Request → sanctum auth → route-model binding resolves the team → policy check via
`authorize('view')` → count query → JSON response.
