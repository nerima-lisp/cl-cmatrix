;;;; t/glyphs-test.lisp
;;;;
;;;; The four built-in glyph sets and the --charset registry that resolves
;;;; names to them. Two of these tests exist to pin down a fixed bug: -c used
;;;; to draw half-width katakana, which upstream cmatrix's -c does not. The
;;;; CJK Symbols and Punctuation block is now :CLASSIC, katakana is a separate
;;;; :KATAKANA extension of ours, and the sets are asserted to be disjoint so
;;;; the two cannot be silently swapped back.

(in-package #:cl-cmatrix/test)

(defun %last-glyph (glyphs)
  "GLYPHS' final character. Indexing from the end rather than by a literal
index keeps a wrong-sized set reporting as a failed length assertion instead
of aborting the surrounding WITH-SOFT-ASSERTIONS with an out-of-bounds error."
  (aref glyphs (1- (length glyphs))))

(describe "+default-glyphs+"
  (it "has 90 distinct characters spanning U+0021..U+007A"
    (with-soft-assertions
      (expect (= (length +default-glyphs+) 90) :to-be-truthy)
      (expect (= (length (remove-duplicates +default-glyphs+)) 90) :to-be-truthy)
      (expect (every (lambda (c) (<= #x21 (char-code c) #x7a)) +default-glyphs+)
              :to-be-truthy)
      (expect (char= (aref +default-glyphs+ 0) (code-char #x21)) :to-be-truthy)
      (expect (char= (%last-glyph +default-glyphs+) (code-char #x7a)) :to-be-truthy)))

  (it "stops short of `{`, `|`, `}` and `~`, as upstream's rand() % 90 + 33 does"
    (expect (notany (lambda (c) (find c +default-glyphs+)) "{|}~") :to-be-truthy))

  (it "excludes space, so no column ever draws a blank as a glyph"
    (expect (not (find #\Space +default-glyphs+)) :to-be-truthy)))

(describe "+classic-glyphs+"
  (it "has 63 distinct characters spanning U+3000..U+303E, upstream's -c range"
    (with-soft-assertions
      (expect (= (length +classic-glyphs+) 63) :to-be-truthy)
      (expect (= (length (remove-duplicates +classic-glyphs+)) 63) :to-be-truthy)
      (expect (every (lambda (c) (<= #x3000 (char-code c) #x303e)) +classic-glyphs+)
              :to-be-truthy)
      (expect (char= (aref +classic-glyphs+ 0) (code-char #x3000)) :to-be-truthy)
      (expect (char= (%last-glyph +classic-glyphs+) (code-char #x303e)) :to-be-truthy)))

  (it "starts at U+3000 inclusive, because upstream draws rand() % 63 + 12288"
    ;; The ideographic space is the first code point of the range, and dropping
    ;; it as "not a real glyph" would leave 62 characters and shift every other
    ;; draw -- upstream keeps it, so this set keeps it.
    (expect (find (code-char #x3000) +classic-glyphs+) :to-be-truthy)))

(describe "+katakana-glyphs+"
  (it "has 56 distinct half-width katakana characters, each in U+FF66..U+FF9D"
    (with-soft-assertions
      (expect (= (length +katakana-glyphs+) 56) :to-be-truthy)
      (expect (= (length (remove-duplicates +katakana-glyphs+)) 56) :to-be-truthy)
      (expect (every (lambda (c) (<= #xff66 (char-code c) #xff9d)) +katakana-glyphs+)
              :to-be-truthy)
      (expect (char= (aref +katakana-glyphs+ 0) (code-char #xff66)) :to-be-truthy)
      (expect (char= (%last-glyph +katakana-glyphs+) (code-char #xff9d)) :to-be-truthy))))

(describe "+classic-glyphs+ versus +katakana-glyphs+"
  ;; Regression fixation: -c used to draw katakana. Upstream's -c is the CJK
  ;; Symbols and Punctuation block; katakana is ours and reachable only through
  ;; --charset katakana. Asserting the two vectors share no character is what
  ;; makes swapping them back a test failure rather than a cosmetic difference.
  (it "are disjoint: no character belongs to both sets"
    (expect (notany (lambda (c) (find c +katakana-glyphs+)) +classic-glyphs+)
            :to-be-truthy))

  (it "differ in length, so neither can stand in for the other"
    (expect (/= (length +classic-glyphs+) (length +katakana-glyphs+)) :to-be-truthy))

  (it "resolve through the names that say which is which"
    (with-soft-assertions
      (expect (eq (charset-glyphs :classic) +classic-glyphs+) :to-be-truthy)
      (expect (eq (charset-glyphs :katakana) +katakana-glyphs+) :to-be-truthy)
      (expect (every (lambda (c) (<= #x3000 (char-code c) #x303e))
                     (charset-glyphs :classic))
              :to-be-truthy)
      (expect (every (lambda (c) (<= #xff66 (char-code c) #xff9d))
                     (charset-glyphs :katakana))
              :to-be-truthy))))

(describe "+binary-glyphs+"
  (it "is exactly #\\0 and #\\1"
    (expect (equalp +binary-glyphs+ #(#\0 #\1)) :to-be-truthy)))

(describe "list-charsets"
  (it "names every registered charset, each a valid CHARSET-P"
    (with-soft-assertions
      (expect (equal (list-charsets) '(:ascii :classic :katakana :binary)) :to-be-truthy)
      (expect (every #'charset-p (list-charsets)) :to-be-truthy)
      (expect (not (charset-p :not-a-charset)) :to-be-truthy)))

  (it "registers no :lambda charset, since -m is a render mode and not a glyph set"
    ;; Upstream's -m substitutes a lambda for every non-head character at draw
    ;; time; it lives on MATRIX-STATE as LAMBDA-P and is applied by the
    ;; renderer, so no glyph vector answers to :LAMBDA here.
    (with-soft-assertions
      (expect (not (charset-p :lambda)) :to-be-truthy)
      (expect (not (member :lambda (list-charsets))) :to-be-truthy))))

(describe "charset-glyphs"
  (it "resolves :ascii to +default-glyphs+"
    (expect (eq (charset-glyphs :ascii) +default-glyphs+) :to-be-truthy))

  (it "resolves :classic to +classic-glyphs+"
    (expect (eq (charset-glyphs :classic) +classic-glyphs+) :to-be-truthy))

  (it "resolves :katakana to +katakana-glyphs+"
    (expect (eq (charset-glyphs :katakana) +katakana-glyphs+) :to-be-truthy))

  (it "resolves :binary to +binary-glyphs+"
    (expect (eq (charset-glyphs :binary) +binary-glyphs+) :to-be-truthy))

  (it-each ((:ascii) (:classic) (:katakana) (:binary))
           "returns the registry's own shared vector for ~A, not a fresh copy"
           (name)
           ;; The documented aliasing contract, pinned so it cannot be
           ;; "fixed" into a COPY-SEQ without a deliberate decision. Copying
           ;; per call was considered and rejected: the expected use hands the
           ;; result straight to MAKE-MATRIX-STATE's :GLYPHS, which only ever
           ;; reads it, so the allocation would buy nothing. What the caller
           ;; owes in return is not to mutate the result -- see the docstring
           ;; and docs/src/reference/api.md.
           (expect (eq (charset-glyphs name) (charset-glyphs name)) :to-be-truthy))

  (it "signals UNKNOWN-CHARSET for :lambda, which is no longer a charset name"
    (expect (signals unknown-charset (charset-glyphs :lambda)) :to-be-truthy))

  (it "signals UNKNOWN-CHARSET for an unregistered name"
    (expect (signals unknown-charset (charset-glyphs :not-a-charset)) :to-be-truthy))

  (it "the condition's NAME reader returns the offending charset name"
    (let ((name (handler-case (progn (charset-glyphs :bogus) nil)
                  (unknown-charset (c) (unknown-charset-name c)))))
      (expect (eq name :bogus) :to-be-truthy)))

  (it-each ((:ascii) (:classic) (:katakana) (:binary))
           "~A resolves to a non-empty SIMPLE-VECTOR of characters"
           (name)
           (let ((glyphs (charset-glyphs name)))
             (expect (typep glyphs 'simple-vector) :to-be-truthy)
             (expect (plusp (length glyphs)) :to-be-truthy)
             (expect (every #'characterp glyphs) :to-be-truthy))))

(describe "random-glyph"
  (it "always returns a member of the glyph set it is given"
    (let ((random-state (sb-ext:seed-random-state 7)))
      (expect (every (lambda (c) (find c +default-glyphs+))
                     (loop repeat 200 collect (random-glyph +default-glyphs+ random-state)))
              :to-be-truthy)))

  (it "is reproducible: the same seed draws the same sequence"
    (let ((sequence-1 (loop with rs = (sb-ext:seed-random-state 99)
                             repeat 50 collect (random-glyph +default-glyphs+ rs)))
          (sequence-2 (loop with rs = (sb-ext:seed-random-state 99)
                             repeat 50 collect (random-glyph +default-glyphs+ rs))))
      (expect (equal sequence-1 sequence-2) :to-be-truthy)))

  (it "draws from the two-character set without running off either end"
    (let ((rs (sb-ext:seed-random-state 3)))
      (expect (every (lambda (c) (find c +binary-glyphs+))
                     (loop repeat 100 collect (random-glyph +binary-glyphs+ rs)))
              :to-be-truthy)))

  (it-property "returns a member of whichever registered charset it is handed"
               ((name (gen-member (list-charsets))))
               (let* ((glyphs (charset-glyphs name))
                      (rs (sb-ext:seed-random-state 11))
                      (drawn (loop repeat 40 collect (random-glyph glyphs rs))))
                 (expect (every (lambda (c) (find c glyphs)) drawn) :to-be-truthy))))
