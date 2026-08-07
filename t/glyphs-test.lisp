;;;; t/glyphs-test.lisp

(in-package #:cl-cmatrix/test)

(describe "+default-glyphs+"
  (it "has 94 distinct printable ASCII characters, excluding space"
    (with-soft-assertions
      (expect (= (length +default-glyphs+) 94) :to-be-truthy)
      (expect (= (length (remove-duplicates +default-glyphs+)) 94) :to-be-truthy)
      (expect (notany (lambda (c) (char= c #\Space)) +default-glyphs+) :to-be-truthy))))

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
      (expect (equal sequence-1 sequence-2) :to-be-truthy))))

(describe "+katakana-glyphs+"
  (it "has 56 distinct half-width katakana characters, each in U+FF66..U+FF9D"
    (with-soft-assertions
      (expect (= (length +katakana-glyphs+) 56) :to-be-truthy)
      (expect (= (length (remove-duplicates +katakana-glyphs+)) 56) :to-be-truthy)
      (expect (every (lambda (c) (<= #xff66 (char-code c) #xff9d)) +katakana-glyphs+)
              :to-be-truthy))))

(describe "+binary-glyphs+"
  (it "is exactly #\\0 and #\\1"
    (expect (equalp +binary-glyphs+ #(#\0 #\1)) :to-be-truthy)))

(describe "+lambda-glyphs+"
  (it "starts with lambda glyphs and keeps ASCII fallbacks"
    (with-soft-assertions
      (expect (char= (aref +lambda-glyphs+ 0) (code-char #x3bb)) :to-be-truthy)
      (expect (equalp (subseq +lambda-glyphs+ 2) #(#\l #\L)) :to-be-truthy))))

(describe "list-charsets"
  (it "names every registered charset, each a valid CHARSET-P"
    (with-soft-assertions
      (expect (equal (list-charsets) '(:ascii :katakana :binary :lambda)) :to-be-truthy)
      (expect (every #'charset-p (list-charsets)) :to-be-truthy)
      (expect (not (charset-p :not-a-charset)) :to-be-truthy))))

(describe "charset-glyphs"
  (it "resolves :ascii to +default-glyphs+"
    (expect (eq (charset-glyphs :ascii) +default-glyphs+) :to-be-truthy))

  (it "resolves :katakana to +katakana-glyphs+"
    (expect (eq (charset-glyphs :katakana) +katakana-glyphs+) :to-be-truthy))

  (it "resolves :binary to +binary-glyphs+"
    (expect (eq (charset-glyphs :binary) +binary-glyphs+) :to-be-truthy))

  (it "resolves :lambda to +lambda-glyphs+"
    (expect (eq (charset-glyphs :lambda) +lambda-glyphs+) :to-be-truthy))

  (it "signals UNKNOWN-CHARSET for an unregistered name"
    (expect (signals unknown-charset (charset-glyphs :not-a-charset)) :to-be-truthy))

  (it "the condition's NAME reader returns the offending charset name"
    (let ((name (handler-case (progn (charset-glyphs :bogus) nil)
                  (unknown-charset (c) (unknown-charset-name c)))))
      (expect (eq name :bogus) :to-be-truthy))))
