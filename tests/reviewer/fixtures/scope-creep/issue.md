title:	Add a status filter to the projects index
state:	OPEN
labels:	enhancement, Agent
--
`GET /projects` returns every project. Add an optional `status` query parameter
that filters the list.

Acceptance criteria:
- `?status=active` returns only active projects.
- Omitting the parameter keeps today's behaviour.
- An unknown status is rejected with a 422.
