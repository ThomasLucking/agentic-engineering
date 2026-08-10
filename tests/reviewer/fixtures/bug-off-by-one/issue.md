title:	Order export runs out of memory on large accounts
state:	OPEN
labels:	bug, Agent
--
Exporting an account with 50k+ orders exhausts PHP's memory limit — `ExportService::rowsFor()`
loads every order into a single collection.

Page through the query instead of loading it all at once.

Acceptance criteria:
- Memory stays flat regardless of account size.
- Every order that appeared in the old export still appears in the new one — the
  export must not lose rows at the end of the result set.
