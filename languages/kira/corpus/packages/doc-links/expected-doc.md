# Links

Shapes and their areas. This module links [`Shape`](#struct-Shape), [`Shape.area`](#struct-Shape) and
[`Links::Unit`](#enum-Unit), and names [`hidden`], which is private.

## Public API

- `enum Unit`: The unit a shape's area is measured in.
- `struct Shape`: A square of [`Unit`](#enum-Unit)s, the one that [`area_of`](#function-area_of) measures.
- `function area_of`: The area of a square of side `side`, the same as [`Shape.area`](#struct-Shape) gives.

## `enum Unit`

The unit a shape's area is measured in.

### `Metres`

Square metres.

### `Feet`

Square feet.

## `struct Shape`

A square of [`Unit`](#enum-Unit)s, the one that [`area_of`](#function-area_of) measures.

Its area comes from [`Shape.area`](#struct-Shape). The link [`Links::Unit`](#enum-Unit) names the same
unit through the package's path.

# Examples

```kira
let shape = Shape { sides = 2 }
```

### `sides`

The length of one side.

### `area`

The area in square units: the side squared.

The helper [`hidden`] is private, so its link shows as written.

## `function area_of`

The area of a square of side `side`, the same as [`Shape.area`](#struct-Shape) gives.

# Examples

```compile_fail
let side: String = area_of(2)
```
