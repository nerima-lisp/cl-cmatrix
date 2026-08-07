;;;; t/color-scheme-test.lisp

(in-package #:cl-cmatrix/test)

(describe "list-color-schemes"
  (it "names every registered scheme, each a valid COLOR-SCHEME-P"
    (with-soft-assertions
      (expect (equal (list-color-schemes)
                     '(:green :cyan :red :blue :magenta :yellow :white
                       :purple :orange :amber :pink :black))
              :to-be-truthy)
      (expect (every #'color-scheme-p (list-color-schemes)) :to-be-truthy)
      (expect (not (color-scheme-p :not-a-scheme)) :to-be-truthy))))

(describe "color-choice-p"
  (it "accepts every registered scheme name and :rainbow"
    (with-soft-assertions
      (expect (every #'color-choice-p (list-color-schemes)) :to-be-truthy)
      (expect (color-choice-p :rainbow) :to-be-truthy)))

  (it "rejects an unregistered name"
    (expect (not (color-choice-p :not-a-scheme)) :to-be-truthy)))

(describe "color-scheme-*-rgb accessors"
  (it "reads back :green's three RGB triples"
    (with-soft-assertions
      (expect (equal (color-scheme-head-rgb :green) '(255 255 255)) :to-be-truthy)
      (expect (equal (color-scheme-bright-rgb :green) '(0 255 70)) :to-be-truthy)
      (expect (equal (color-scheme-dark-rgb :green) '(0 0 0)) :to-be-truthy)))
  (it "renders :black as a white head with a black trail"
    (with-soft-assertions
      (expect (equal (color-scheme-head-rgb :black) '(255 255 255)) :to-be-truthy)
      (expect (equal (color-scheme-bright-rgb :black) '(0 0 0)) :to-be-truthy)
      (expect (equal (color-scheme-dark-rgb :black) '(0 0 0)) :to-be-truthy)))

  (it "signals UNKNOWN-COLOR-SCHEME for an unregistered name"
    (expect (signals unknown-color-scheme (color-scheme-head-rgb :not-a-scheme))
            :to-be-truthy))

  (it "the condition's NAME reader returns the offending scheme name"
    (let ((name (handler-case (progn (color-scheme-head-rgb :bogus) nil)
                  (unknown-color-scheme (c) (unknown-color-scheme-name c)))))
      (expect (eq name :bogus) :to-be-truthy)))

  (it-each ((:green) (:cyan) (:red) (:blue) (:magenta) (:yellow) (:white)
            (:purple) (:orange) (:amber) (:pink))
            "~A's trail is brighter just behind the head than at its tail"
            (name)
            (expect (> (apply #'color-luminance (color-scheme-bright-rgb name))
                       (apply #'color-luminance (color-scheme-dark-rgb name)))
                    :to-be-truthy))

  (it-property "every accessor returns three integers in [0, 255], for any registered scheme"
               ((scheme (gen-member (list-color-schemes))))
               (dolist (rgb (list (color-scheme-head-rgb scheme)
                                  (color-scheme-bright-rgb scheme)
                                  (color-scheme-dark-rgb scheme)))
                 (expect (= (length rgb) 3) :to-be-truthy)
                 (expect (every (lambda (component) (typep component '(integer 0 255))) rgb)
                         :to-be-truthy))))
