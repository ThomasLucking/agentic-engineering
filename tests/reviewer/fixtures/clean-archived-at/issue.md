title:	Let projects be archived instead of deleted
state:	OPEN
labels:	enhancement, Agent
--
Deleting a project loses its history. Add an `archived_at` timestamp so a project
can be taken out of the active list without being destroyed.

Acceptance criteria:
- `projects.archived_at` is a nullable timestamp.
- `Project::active()` excludes archived projects.
- The store/update request accepts an optional `archived_at`.
