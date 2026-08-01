;;;; t/color-scheme-test.lisp

(in-package #:cl-cmatrix/test)

(describe "list-color-schemes"
  (it "names every registered scheme, each a valid COLOR-SCHEME-P"
    (with-soft-assertions
      (expect (equal (list-color-schemes)
                     '(:green :cyan :red :blue :magenta :yellow :white))
              :to-be-truthy)
      (expect (every #'color-scheme-p (list-color-schemes)) :to-be-truthy)
      (expect (not (color-scheme-p :not-a-scheme)) :to-be-truthy))))

(describe "color-scheme-*-rgb accessors"
  (it "reads back :green's three RGB triples"
    (with-soft-assertions
      (expect (equal (color-scheme-head-rgb :green) '(255 255 255)) :to-be-truthy)
      (expect (equal (color-scheme-bright-rgb :green) '(0 255 70)) :to-be-truthy)
      (expect (equal (color-scheme-dark-rgb :green) '(0 0 0)) :to-be-truthy)))

  (it "signals UNKNOWN-COLOR-SCHEME for an unregistered name"
    (expect (signals (color-scheme-head-rgb :not-a-scheme) 'unknown-color-scheme)
            :to-be-truthy))

  (it "the condition's NAME reader returns the offending scheme name"
    (let ((name (handler-case (progn (color-scheme-head-rgb :bogus) nil)
                  (unknown-color-scheme (c) (unknown-color-scheme-name c)))))
      (expect (eq name :bogus) :to-be-truthy)))

  (it "every scheme's trail is brighter just behind the head than at its tail"
    (dolist (name (list-color-schemes))
      (expect (> (apply #'color-luminance (color-scheme-bright-rgb name))
                 (apply #'color-luminance (color-scheme-dark-rgb name)))
              :to-be-truthy))))
