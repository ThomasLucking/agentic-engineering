# Issue #107: Cart total is calculated in three places

## The issue
`(quantity * unit_price_cents) - discount_cents` was written out in `Cart`,
`CartController` twice over, with no single owner.

## Changes
- `app/Models/CartItem.php` — new `lineTotalCents()` holding the calculation →
  one place to change it.
- `app/Models/Cart.php` — `totalCents()` sums `lineTotalCents()` → same result,
  no duplicated arithmetic.
- `app/Http/Controllers/CartController.php` — both map callbacks call
  `lineTotalCents()` → the two remaining copies are gone.

## How it fits together
`CartItem::lineTotalCents()` is the single definition; `Cart::totalCents()` sums
it, and the controller's per-line views call it directly. No call sites left
computing it inline.
