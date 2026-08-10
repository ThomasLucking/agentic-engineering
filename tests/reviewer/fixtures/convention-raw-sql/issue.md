title:	Expose active user counts per team
state:	OPEN
labels:	enhancement, Agent
--
Ops needs a JSON endpoint returning how many active users each team has.

Acceptance criteria:
- `GET /api/teams/{team}/stats` returns `{"active_users": <int>}`.
- Only members of the team may call it.
- A user is "active" when `last_seen_at` is within the last 30 days.
