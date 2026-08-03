# Conditions

Every error `cl-cmatrix` signals is a subclass of `cl-cmatrix-error`, defined
in `src/conditions.lisp`. Catching that one base condition with a single
`handler-case` clause catches everything the library can signal; each
subclass carries structured, reader-exposed slots instead of only a message
string, so a caller can recover programmatically rather than parsing text.

Every subclass besides the base itself is defined through the same
`define-cl-cmatrix-condition` macro, so adding one is a single form rather
than hand-written `:report` boilerplate.

## Hierarchy

```text
error
└── cl-cmatrix-error              (base for everything below)
    ├── invalid-dimensions
    ├── invalid-speed
    ├── unknown-color-scheme
    └── unknown-charset
```

The hierarchy is flat: every concrete condition inherits `cl-cmatrix-error`
directly, with no further subclassing between them.

## `cl-cmatrix-error`

The base condition. No slots of its own; its only role is to give every
error `cl-cmatrix` signals a common supertype to catch.

## `invalid-dimensions`

Signaled by [`make-matrix-state`](api.md#make-matrix-state) or
[`matrix-resize`](api.md#matrix-resize) when a width or height is not a
positive integer.

| Slot | Reader | Value |
|---|---|---|
| `width` | `invalid-dimensions-width` | The offending width. |
| `height` | `invalid-dimensions-height` | The offending height. |

## `invalid-speed`

Signaled by [`make-matrix-state`](api.md#make-matrix-state) when `speed` is
not a positive real number.

| Slot | Reader | Value |
|---|---|---|
| `speed` | `invalid-speed-speed` | The offending speed. |

## `unknown-color-scheme`

Signaled by [`make-matrix-state`](api.md#make-matrix-state) when `color`
names no scheme registered in [`list-color-schemes`](api.md#list-color-schemes)
and is not `:rainbow`.

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
