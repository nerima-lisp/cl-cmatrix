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
