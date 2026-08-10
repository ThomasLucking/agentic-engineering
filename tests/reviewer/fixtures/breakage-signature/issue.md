title:	Reports should cover an explicit date range
state:	OPEN
labels:	enhancement, Agent
--
`ReportBuilder::build()` always reports on the last 30 days, hard-coded. The
dashboard needs to request an arbitrary range.

Acceptance criteria:
- `build()` takes the period to report on rather than deriving it internally.
- The dashboard passes the range the user picked.
- Existing callers keep working.
