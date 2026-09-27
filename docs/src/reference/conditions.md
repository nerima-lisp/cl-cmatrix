# Conditions

Library-specific errors `cl-cmatrix` signals are subclasses of
`cl-cmatrix-error`, defined in `src/conditions.lisp`. Invalid `workers` and
`random-state` values use `invalid-argument-type`, which also inherits the
standard `type-error` for compatibility with existing callers. Each condition
carries structured readers instead of only a message string.

The ordinary library conditions are defined through the same
`define-cl-cmatrix-condition` macro, so adding one is a single form rather
than hand-written `:report` boilerplate. `invalid-argument-type` is the
intentional multiple-inheritance exception for standard `type-error`
compatibility.

## Hierarchy

```text
error
└── cl-cmatrix-error              (base for everything below)
    ├── invalid-dimensions
    ├── invalid-glyphs
    ├── invalid-speed
    ├── invalid-fps
    ├── invalid-update-delay
    ├── unknown-color-scheme
    ├── unknown-charset
    └── invalid-argument-type     (also a type-error)
```

The library-specific hierarchy is flat except for `invalid-argument-type`,
which additionally inherits the standard `type-error`.

## `cl-cmatrix-error`

The base condition. No slots of its own; its only role is to give every
error `cl-cmatrix` signals a common supertype to catch.

## `invalid-argument-type`

Signals when `workers` is not a positive integer or `random-state` is not a
`random-state`. This condition has both `cl-cmatrix-error` and `type-error` as
supertypes, so either kind of handler continues to work. Its standard readers
`type-error-datum` and `type-error-expected-type` identify the bad value and
the required type.

## `invalid-dimensions`

Signaled by [`make-matrix-state`](api.md#make-matrix-state) or
[`matrix-resize`](api.md#matrix-resize) when a width or height is not a
positive integer.

| Slot | Reader | Value |
|---|---|---|
| `width` | `invalid-dimensions-width` | The offending width. |
| `height` | `invalid-dimensions-height` | The offending height. |

## `invalid-glyphs`

Signaled by [`make-matrix-state`](api.md#make-matrix-state) when `glyphs` is
not a non-empty `simple-vector` every element of which is a character.
[`run-matrix`](api.md#run-matrix) raises it through that same check, since it
builds its initial state with `make-matrix-state`.

| Slot | Reader | Value |
|---|---|---|
| `glyphs` | `invalid-glyphs-glyphs` | The offending glyph set. |

A vector obtained from [`charset-glyphs`](api.md#charset-glyphs) always
satisfies the contract, so a caller reaching a glyph set by name can never see
this condition; it is reachable only by passing a vector of one's own.

The check runs at *construction*. Without it an empty
`glyphs` was accepted by `make-matrix-state` and failed several
[`matrix-advance`](api.md#matrix-advance) calls later with a raw `type-error`
-- which is not a `cl-cmatrix-error`, and so escaped the single
`handler-case` clause this page promises catches everything. A vector holding
non-characters was worse: it survived construction and dozens of advances and
only failed in the renderer.

## `invalid-speed`

Signaled by [`run-matrix`](api.md#run-matrix) when `speed` is not a positive
real number. `make-matrix-state` neither signals it nor takes a `speed`
argument at all: fall speed is the driver loop's concern, not a
`matrix-state` slot, so `run-matrix` is the only place it can be rejected.

| Slot | Reader | Value |
|---|---|---|
| `speed` | `invalid-speed-speed` | The offending speed. |

## `invalid-fps`

Signaled by [`run-matrix`](api.md#run-matrix) when `fps` is not a positive
real number. Validation happens before terminal setup, so programmatic callers
get the same input contract as the command-line front end.

| Slot | Reader | Value |
|---|---|---|
| `fps` | `invalid-fps-fps` | The offending frame rate. |

## `invalid-update-delay`

Signaled by [`run-matrix`](api.md#run-matrix) when `update-delay` is not an
integer from 0 through 10. The value is measured in 10 millisecond units,
matching upstream `cmatrix`; validation happens before terminal setup.

| Slot | Reader | Value |
|---|---|---|
| `delay` | `invalid-update-delay-delay` | The offending update delay. |

## `unknown-color-scheme`

Signaled by [`make-matrix-state`](api.md#make-matrix-state) when `color`
names no scheme registered in [`list-color-schemes`](api.md#list-color-schemes)
and is not `:rainbow`. [`run-matrix`](api.md#run-matrix) raises it through
that same check, since it builds its initial state with `make-matrix-state`.

| Slot | Reader | Value |
|---|---|---|
| `name` | `unknown-color-scheme-name` | The offending color name. |

## `unknown-charset`

Signaled by [`charset-glyphs`](api.md#charset-glyphs) when `name` names no
charset registered in [`list-charsets`](api.md#list-charsets).

| Slot | Reader | Value |
|---|---|---|
| `name` | `unknown-charset-name` | The offending charset name. |

## See also

- [API reference](api.md) for the full lambda list of every signaling
  function.
- [Getting started](../getting-started.md) for the command-line flags
  (`--color`, `--charset`) that route user input through these same
  conditions.
