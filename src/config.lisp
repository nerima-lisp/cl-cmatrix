;;;; src/config.lisp

(in-package #:cl-cmatrix)

(defconstant +min-trail-length+ 3
  "The shortest trail a freshly spawned COLUMN may have.")

(defconstant +max-trail-length+ 12
  "The longest trail a freshly spawned COLUMN may have.")

(defconstant +max-raw-interval+ 3
  "The upper bound (inclusive) of the ticks-per-row advance before SPEED scaling.")

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
