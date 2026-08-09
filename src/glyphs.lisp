;;;; src/glyphs.lisp
;;;;
;;;; The falling-character glyph sets, and the name -> glyph-vector registry
;;;; the CLI's --charset flag resolves through, mirroring +COLOR-SCHEMES+'
;;;; own name -> data registry in color-scheme.lisp.
;;;;
;;;; Two of the four sets are upstream cmatrix's own, reproduced by code
;;;; point rather than approximated. +DEFAULT-GLYPHS+ is upstream's default
;;;; draw and +CLASSIC-GLYPHS+ is what its -c selects. +KATAKANA-GLYPHS+ and
;;;; +BINARY-GLYPHS+ are extensions of ours with no upstream equivalent,
;;;; reachable only through --charset.
;;;;
;;;; Half-width katakana is deliberately NOT what -c selects, however much
;;;; more like the film it looks. Upstream's -c is the CJK Symbols and
;;;; Punctuation block, and treating the two as the same thing is the mistake
;;;; this file previously made -- so both sets exist here, under names that
;;;; say which is which.
;;;;
;;;; There is no lambda glyph set. Upstream's -m is a render mode that
;;;; substitutes a lambda for every non-head character at draw time, not a
;;;; character set columns draw from; it lives on MATRIX-STATE as LAMBDA-P
;;;; and is applied in render.lisp.

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
reproduced exactly -- which means it deliberately stops short of the four
printable ASCII characters above `z`, excluding `{`, `|`, `}` and `~`.
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

The returned vector is the registry's own, SHARED between every caller and
not a fresh copy: two calls with the same NAME return EQ vectors. Treat it as
read-only. Destructively modifying it -- (SETF (AREF ...)) -- corrupts the
charset for every later caller in the process, permanently, since nothing
rebuilds +CHARSETS+ after load.

Copying on every call was considered and rejected. The expected use is to
hand the result straight to MAKE-MATRIX-STATE's :GLYPHS, which stores the
vector and only ever reads it; charging that path an allocation proportional
to the glyph set, on every call, to defend against a mutation no correct
caller performs is the wrong trade. A caller that genuinely wants a vector it
may modify should ask for one explicitly with COPY-SEQ."
  (or (cdr (assoc name +charsets+))
      (error 'unknown-charset :name name)))

(defun random-glyph (glyphs random-state)
  "Return a character drawn uniformly at random from GLYPHS (a non-empty
SIMPLE-VECTOR), using RANDOM-STATE. Injecting RANDOM-STATE rather than
consulting *RANDOM-STATE* is what makes a whole MATRIX-STATE's glyph choices
reproducible from a fixed seed."
  (aref glyphs (random (length glyphs) random-state)))
