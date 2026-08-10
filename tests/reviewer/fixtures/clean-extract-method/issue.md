title:	Cart total is calculated in three places
state:	OPEN
labels:	refactor, Agent
--
The line-item total (`quantity * unit_price_cents`, minus the discount) is
duplicated in `Cart`, `CartController` and the checkout summary. They have already
drifted once.

Acceptance criteria:
- One method owns the calculation.
- Behaviour is unchanged.
