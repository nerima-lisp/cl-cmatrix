
(in-package #:cl-cmatrix)

(defconstant +min-trail-length+ 3
  "The shortest trail a freshly spawned COLUMN may have. Upstream cmatrix
draws a stream length of `rand() % (LINES - 3) + 3`, so 3 is both the floor
and the amount subtracted from the height before the draw.")

(defconstant +max-update-threshold+ 3
  "Exclusive upper bound of the per-column async update threshold draw.
Upstream cmatrix's `updates[j] = rand() % 3 + 1` gives every column a
threshold in 1..3; a column advances on a tick only when the shared cycling
counter exceeds its own threshold, which is what makes -a look ragged.")

(defconstant +async-count-cycle+ 4
  "The period of MATRIX-STATE's ASYNC-COUNT counter, which cycles 1..4.
Upstream cmatrix's `count` wraps at 4 while thresholds are drawn from 1..3,
so every column advances at least once per cycle and the fastest advances on
three ticks out of four.")

(defconstant +base-tick-seconds+ 1/100
  "The fixed real-time tick period the driver loop runs at, in seconds.
CL-TTY-KIT:TICK-LOOP-RUN-REALTIME binds its :INTERVAL once for the whole loop
(src/tick-loop.lisp:117-118 in cl-tty-kit), so a runtime -u change cannot
alter it. The loop therefore always ticks at this base rate and advances the
matrix once every UPDATE-DELAY ticks, which reproduces upstream cmatrix's
`napms(update * 10)` semantics while leaving -u adjustable at runtime.")

(defconstant +default-speed+ 1
  "Default fall-speed multiplier.")

(defconstant +default-color+ :green
  "Default matrix color.")

(defconstant +default-bold+ nil
  "Default glyph weight setting.")

(defconstant +default-fps+ 30
  "Default tick rate, in ticks per second, for RUN-MATRIX.")

(defconstant +default-update-delay+ 4
  "Default upstream-compatible update delay in 10 millisecond units.")

(defconstant +default-workers+ 4
  "Default number of worker threads used by RUN-MATRIX.")

(defconstant +default-fd+ 0
  "Default file descriptor used for terminal input polling.")

(defconstant +parallel-column-threshold+ 2048
  "Minimum matrix width at which MATRIX-ADVANCE uses its executor.")
