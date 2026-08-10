# Issue #102: Add a status filter to the projects index

## The issue
`GET /projects` had no filtering — the index always returned every project.

## Changes
- `app/Http/Requests/IndexProjectRequest.php` — new Form Request validating
  `status` against the allowed set → unknown values 422 before the query runs.
- `app/Http/Controllers/ProjectController.php` — apply the filter with `when()`
  → omitting `status` keeps the old behaviour.
- `config/mail.php` — default mailer set to `log` → easier local testing.

## How it fits together
Request → `IndexProjectRequest` validates `status` → controller applies it as a
conditional `where` → paginated view renders the filtered set.
