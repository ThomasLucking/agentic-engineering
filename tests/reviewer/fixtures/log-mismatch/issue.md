title:	The same email can be invited to a team twice
state:	OPEN
labels:	bug, Agent
--
Inviting an address that already has a pending invite for the team creates a
second row, and the invitee gets two emails.

Acceptance criteria:
- A second invite for the same email + team is rejected.
- The constraint holds even when two invites are submitted at the same moment.
