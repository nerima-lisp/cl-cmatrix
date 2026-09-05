
(in-package #:cl-cmatrix)

(defun %build-code-range-glyphs (from to)
  "Return a SIMPLE-VECTOR of the characters CODE-CHAR maps every code point
in [FROM, TO] (inclusive) to, in ascending order. The shared construction
every built-in set except +BINARY-GLYPHS+ builds from, since each of those is
exactly one contiguous run of code points."
  (coerce (loop for code from from to to collect (code-char code)) 'simple-vector))

(defun %build-default-glyphs ()
  (%build-code-range-glyphs #x21 #x7a))

(defparameter +default-glyphs+ (%build-default-glyphs)
  "The default glyph set: U+0021 through U+007A inclusive, 90 characters,
`!` through `z`. This is upstream cmatrix's default draw, `rand() % 90 + 33`,
so it excludes `{`, `|`, `}` and `~`.
Callers may pass any other non-empty SIMPLE-VECTOR of characters to
MAKE-MATRIX-STATE's :GLYPHS.")

(defun %build-classic-glyphs ()
  (%build-code-range-glyphs #x3000 #x303e))

(defparameter +classic-glyphs+ (%build-classic-glyphs)
  "The CJK Symbols and Punctuation glyphs upstream cmatrix's -c selects:
U+3000 through U+303E inclusive, 63 characters -- 、。〆〇「」【】〒 and the
rest of that block. Upstream sets `randmin = 12288` and draws
`rand() % 63 + 12288`, which is this range and no other. Note that this is
NOT half-width katakana; see +KATAKANA-GLYPHS+ for that.")

(defun %build-katakana-glyphs ()
  (%build-code-range-glyphs #xff66 #xff9d))

(defparameter +katakana-glyphs+ (%build-katakana-glyphs)
  "Half-width katakana glyphs (U+FF66 through U+FF9D inclusive, 56
characters). An extension of ours, not upstream's -c: it is the closest a
Unicode terminal font gets to the film's look without depending on cmatrix's
non-free bitmap font, but upstream's own -c draws +CLASSIC-GLYPHS+ instead.
Reachable through --charset katakana.")

(defparameter +binary-glyphs+ #(#\0 #\1)
  "A two-character glyph set of just #\\0 and #\\1, for a stark binary-rain
look. An extension of ours; upstream has no equivalent. Reachable through
--charset binary.")

(defun %build-charsets ()
  (list (cons :ascii +default-glyphs+)
        (cons :classic +classic-glyphs+)
        (cons :katakana +katakana-glyphs+)
        (cons :binary +binary-glyphs+)))

(defparameter +charsets+ (%build-charsets)
  "Maps a --charset CLI name to its glyph SIMPLE-VECTOR. :ASCII (the
default) maps to +DEFAULT-GLYPHS+ and :CLASSIC to the set upstream's -c
selects; :KATAKANA and :BINARY are ours.")

(define-registry-queries list-charsets charset-p +charsets+)

(defun charset-glyphs (name)
  "Return the glyph SIMPLE-VECTOR NAME names. Signals UNKNOWN-CHARSET when
NAME is not registered in +CHARSETS+.

The returned vector is shared by every caller and must be treated as
read-only. Two calls with the same NAME return the same vector. Use COPY-SEQ
when a mutable copy is needed."
  (or (cdr (assoc name +charsets+))
      (error 'unknown-charset :name name)))

(defun random-glyph (glyphs random-state)
  "Return a character drawn uniformly at random from GLYPHS (a non-empty
SIMPLE-VECTOR), using RANDOM-STATE. Injecting RANDOM-STATE rather than
consulting *RANDOM-STATE* is what makes a whole MATRIX-STATE's glyph choices
reproducible from a fixed seed."
  (aref glyphs (random (length glyphs) random-state)))
