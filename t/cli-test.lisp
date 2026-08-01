;;;; t/cli-test.lisp
;;;;
;;;; Flag parsing only: the handler calls RUN-MATRIX, which takes over a real
;;;; terminal, so these tests never invoke it (never RUN-APP without --help
;;;; or --version).

(in-package #:cl-cmatrix/test)

(describe "the cl-cmatrix app spec: flag parsing round-trips"
  (it "defaults --speed to 1.0"
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix"))))
      (expect (= (option-value invocation :speed) 1.0d0) :to-be-truthy)))

  (it "parses --speed/-s as a float"
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-s" "2.5"))))
      (expect (= (option-value invocation :speed) 2.5d0) :to-be-truthy)))

  (it "rejects a --speed below the 0.1 minimum"
    (expect (signals (parse-argv (make-cmatrix-app) '("cl-cmatrix" "--speed" "0"))
                     'cli-invalid-option-value)
            :to-be-truthy))

  (it "defaults --color to \"green\""
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix"))))
      (expect (string= (option-value invocation :color) "green") :to-be-truthy)))

  (it "parses --color/-c"
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-c" "cyan"))))
      (expect (string= (option-value invocation :color) "cyan") :to-be-truthy)))

  (it "rejects an unknown --color value"
    (expect (signals (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-c" "not-a-color"))
                     'cli-invalid-option-value)
            :to-be-truthy)))

(describe "the cl-cmatrix app spec: --help and --version"
  (it "exits 0 on --help without invoking the handler"
    (let ((output (with-output-to-string (out)
                    (expect (= (run-app (make-cmatrix-app) :argv '("cl-cmatrix" "--help")
                                        :stdout out)
                              0)
                            :to-be-truthy))))
      (expect (search "cl-cmatrix" output) :to-be-truthy)))

  (it "exits 0 on --version and prints the app's version"
    (let ((output (with-output-to-string (out)
                    (expect (= (run-app (make-cmatrix-app) :argv '("cl-cmatrix" "--version")
                                        :stdout out)
                              0)
                            :to-be-truthy))))
      (expect (search "cl-cmatrix" output) :to-be-truthy))))
