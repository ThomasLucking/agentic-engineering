# Issue #101: Order export runs out of memory on large accounts

## The issue
`ExportService::rowsFor()` called `->get()` on an unbounded query, so a 50k-order
account materialised 50k models at once. Root cause: no pagination.

## Changes
- `app/Services/ExportService.php` — page the query with `forPage()` in 500-row
  chunks → memory stays flat regardless of account size.

## How it fits together
Caller → `rowsFor()` counts the result set → loops page by page → maps each page
through `toRow()` → concatenates into one collection the caller consumes as before.
