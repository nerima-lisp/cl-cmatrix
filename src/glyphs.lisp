;;;; src/glyphs.lisp
;;;;
;;;; The falling-character glyph set. +DEFAULT-GLYPHS+ (plain printable
;;;; ASCII) is a completely original, simpler choice than real cmatrix's
;;;; proprietary bitmap font of half-width katakana, and remains the
;;;; default. +KATAKANA-GLYPHS+ and +BINARY-GLYPHS+ are two further built-in
;;;; sets a caller (or --charset on the CLI) may select instead; +CHARSETS+
;;;; is the name -> glyph-vector registry the CLI's --charset flag resolves
;;;; through, mirroring +COLOR-SCHEMES+' own name -> data registry in
;;;; color-scheme.lisp.

(in-package #:cl-cmatrix)

(defun %build-code-range-glyphs (from to)
  "Return a SIMPLE-VECTOR of the characters CODE-CHAR maps every code point
in [FROM, TO] (inclusive) to, in ascending order. The shared construction
+DEFAULT-GLYPHS+ and +KATAKANA-GLYPHS+ both build from, since each is exactly
one contiguous Unicode block."
  (coerce (loop for code from from to to collect (code-char code)) 'simple-vector))

(defun %build-default-glyphs ()
  (%build-code-range-glyphs #x21 #x7e))

(defparameter +default-glyphs+ (%build-default-glyphs)
  "The default glyph set: every printable ASCII character except space (94
characters, U+0021 through U+007E inclusive). Callers may pass any other
non-empty SIMPLE-VECTOR of characters to MAKE-MATRIX-STATE's :GLYPHS.")

(defun %build-katakana-glyphs ()
  (%build-code-range-glyphs #xff66 #xff9d))

(defparameter +katakana-glyphs+ (%build-katakana-glyphs)
  "Half-width katakana glyphs (U+FF66 through U+FF9D inclusive, 56
characters) -- the closest a Unicode terminal font gets to the classic
`cmatrix` bitmap font's look without depending on that non-free asset.")

(defparameter +binary-glyphs+ #(#\0 #\1)
  "A two-character glyph set of just #\\0 and #\\1, for a stark binary-rain
look.")

(defparameter +lambda-glyphs+
  (vector (code-char #x3bb) (code-char #x39b) #\l #\L)
  "A compact lambda glyph set for the classic hacker-rain look.")

(defun %build-charsets ()
  (list (cons :ascii +default-glyphs+)
        (cons :katakana +katakana-glyphs+)
        (cons :binary +binary-glyphs+)
        (cons :lambda +lambda-glyphs+)))

(defparameter +charsets+ (%build-charsets)
  "Maps a --charset CLI name to its glyph SIMPLE-VECTOR. :ASCII (the
default) maps to +DEFAULT-GLYPHS+.")

(define-registry-queries list-charsets charset-p +charsets+)

(defun charset-glyphs (name)
  "Return the glyph SIMPLE-VECTOR NAME names. Signals UNKNOWN-CHARSET when
NAME is not registered in +CHARSETS+."
  (or (cdr (assoc name +charsets+))
      (error 'unknown-charset :name name)))

(defun random-glyph (glyphs random-state)
  "Return a character drawn uniformly at random from GLYPHS (a non-empty
SIMPLE-VECTOR), using RANDOM-STATE. Injecting RANDOM-STATE rather than
consulting *RANDOM-STATE* is what makes a whole MATRIX-STATE's glyph choices
reproducible from a fixed seed."
  (aref glyphs (random (length glyphs) random-state)))

(defun %random-glyph-with-parity (glyphs random-state)
  "Return a random glyph and the upstream-compatible partial-bold bit."
  (let ((glyph (random-glyph glyphs random-state)))
    (values glyph (evenp (char-code glyph)))))
