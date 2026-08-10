# Issue #103: Reports should cover an explicit date range

## The issue
`ReportBuilder::build()` hard-coded a 30-day window, so the dashboard could not
report on a user-chosen range.

## Changes
- `app/Services/ReportBuilder.php` — `build()` now takes a `CarbonPeriod` instead
  of deriving one → the caller owns the range.
- `app/Http/Controllers/ReportController.php` — build the period from `from`/`to`
  query params, defaulting to the previous 30 days → existing URLs behave as before.

## How it fits together
Request (`?from=&to=`) → controller builds a `CarbonPeriod` → `ReportBuilder`
filters orders by that period → view renders the totals.
