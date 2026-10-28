# Documentation

Prices for the shop: the units every price is quoted in.

## Public API

- `struct Price`: The price of one item, in the shop's currency.
- `enum Display`: How a price is shown to the customer.
- `let limit`: The largest amount a single price may hold.

## `struct Price`

The price of one item, in the shop's currency.

A price is never negative. Use `discounted` to take a fraction off it.

### `amount`

The amount, in whole units.

### `currency`

The currency code, such as `EUR`.

### `discounted`

The amount with `rate` taken off.

# Returns

The reduced amount. A `rate` of `0` returns the amount unchanged.

## `enum Display`

How a price is shown to the customer.

### `Full`

Shown with the currency code.

### `Bare`

Shown as the amount alone.

## `let limit`

The largest amount a single price may hold.
