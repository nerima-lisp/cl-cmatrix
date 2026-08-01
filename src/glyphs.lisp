;;;; src/glyphs.lisp
;;;;
;;;; The falling-character glyph set. Real cmatrix draws from a proprietary
;;;; bitmap font of half-width katakana; this project deliberately does not
;;;; reproduce that or any other specific "digital rain" asset. Plain
;;;; printable ASCII is a completely original, simpler choice that still
;;;; produces the classic dense-noise look once it is falling and dimming.

(in-package #:cl-cmatrix)

(defparameter +default-glyphs+
  (coerce (loop for code from #x21 to #x7e collect (code-char code)) 'simple-vector)
  "The default glyph set: every printable ASCII character except space (94
characters, U+0021 through U+007E inclusive). Callers may pass any other
non-empty SIMPLE-VECTOR of characters to MAKE-MATRIX-STATE's :GLYPHS.")

(defun random-glyph (glyphs random-state)
  "Return a character drawn uniformly at random from GLYPHS (a non-empty
SIMPLE-VECTOR), using RANDOM-STATE. Injecting RANDOM-STATE rather than
consulting *RANDOM-STATE* is what makes a whole MATRIX-STATE's glyph choices
reproducible from a fixed seed."
  (aref glyphs (random (length glyphs) random-state)))
