;;;; t/cli-test.lisp
;;;;
;;;; Flag parsing only: the handler calls RUN-MATRIX, which takes over a real
;;;; terminal, so these tests never invoke it (never RUN-APP without --help
;;;; or --version). The IT-ISOLATED cases at the bottom exercise MAIN and
;;;; IMAGE-ENTRY-POINT for real, in a subprocess, for the same reason they
;;;; are never called directly above: both end in HOST-KIT:QUIT, a genuine
;;;; process exit that would kill this test runner if called in-process.
;;;; SB-COVER's coverage data is per-process, so this subprocess's execution
;;;; is invisible to CL-WEAVE:COVERAGE-STATISTICS in the parent regardless --
;;;; these are here for their value as real execution tests, not for
;;;; coverage percentage (see scripts/coverage-entry.lisp's header comment).

(in-package #:cl-cmatrix/test)

(defmacro define-option-round-trip (option-key default args parses-to &optional rejects)
  "Define the IT cases every --OPTION-KEY flag needs against MAKE-CMATRIX-APP:
that parsing bare \"cl-cmatrix\" leaves OPTION-KEY at DEFAULT, that ARGS (a
quoted list of tokens following \"cl-cmatrix\") parses OPTION-KEY to
PARSES-TO, and -- only when REJECTS is supplied, a further quoted token list
-- that those tokens signal CLI-INVALID-OPTION-VALUE instead. Every
comparison uses EQUAL, which is exact for the strings, numbers, booleans, and
NIL every option here parses to, so one macro covers --speed's float and
--bold's flag alike without per-option predicate plumbing.

OPTION-KEY, ARGS, and REJECTS are read as literal syntax -- a keyword and
quoted lists spliced directly into each generated IT's body -- never
evaluated by this macro itself. DEFAULT and PARSES-TO are ordinary forms,
evaluated each time their own generated IT case runs, not at macroexpansion
time."
  `(progn
     (it ,(format nil "defaults --~(~A~) to ~S" option-key default)
       (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix"))))
         (expect (equal (option-value invocation ,option-key) ,default) :to-be-truthy)))
     (it ,(format nil "parses ~{~A~^ ~} to --~(~A~) = ~S" args option-key parses-to)
       (let ((invocation (parse-argv (make-cmatrix-app) (cons "cl-cmatrix" ',args))))
         (expect (equal (option-value invocation ,option-key) ,parses-to) :to-be-truthy)))
     ,@(when rejects
         `((it ,(format nil "rejects ~{~A~^ ~}" rejects)
             (expect (signals cli-invalid-option-value
                              (parse-argv (make-cmatrix-app) (cons "cl-cmatrix" ',rejects)))
                     :to-be-truthy))))))

(describe "the cl-cmatrix app spec: flag parsing round-trips"
  (define-option-round-trip :speed 1.0d0 ("-s" "2.5") 2.5d0 ("--speed" "0"))
  (define-option-round-trip :color "green" ("-c" "cyan") "cyan" ("-c" "not-a-color"))
  (define-option-round-trip :charset "ascii" ("-g" "katakana") "katakana" ("-g" "not-a-charset"))
  (define-option-round-trip :bold nil ("-b") t)
  (define-option-round-trip :fps 30 ("-u" "60") 60 ("--fps" "0"))
  (define-option-round-trip :seed nil ("--seed" "42") 42)

  (it "accepts --color rainbow, a further valid value beyond DEFINE-OPTION-ROUND-TRIP's own case"
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-c" "rainbow"))))
      (expect (string= (option-value invocation :color) "rainbow") :to-be-truthy))))

(describe "%cmatrix-run-matrix-args"
  (it "resolves every option into RUN-MATRIX's own keyword-argument shape"
    (let* ((invocation (parse-argv (make-cmatrix-app)
                                    '("cl-cmatrix" "-s" "2.5" "-c" "cyan" "-g" "katakana" "-b"
                                      "-u" "60" "--seed" "42")))
           (args (cl-cmatrix/cli::%cmatrix-run-matrix-args invocation)))
      (with-soft-assertions
        (expect (= (getf args :speed) 2.5d0) :to-be-truthy)
        (expect (eq (getf args :color) :cyan) :to-be-truthy)
        (expect (eq (getf args :glyphs) +katakana-glyphs+) :to-be-truthy)
        (expect (eq (getf args :bold) t) :to-be-truthy)
        (expect (= (getf args :fps) 60) :to-be-truthy)
        (expect (typep (getf args :random-state) 'random-state) :to-be-truthy))))

  (it "defaults to green ASCII at speed 1.0, unbolded, 30fps, from an unseeded random state"
    (let* ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix")))
           (args (cl-cmatrix/cli::%cmatrix-run-matrix-args invocation)))
      (with-soft-assertions
        (expect (= (getf args :speed) 1.0d0) :to-be-truthy)
        (expect (eq (getf args :color) :green) :to-be-truthy)
        (expect (eq (getf args :glyphs) +default-glyphs+) :to-be-truthy)
        (expect (not (getf args :bold)) :to-be-truthy)
        (expect (= (getf args :fps) 30) :to-be-truthy)))))

(describe "%option-keyword"
  (it "upcases and interns the parsed string value of OPTION-NAME into the keyword package"
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-c" "cyan" "-g" "katakana"))))
      (with-soft-assertions
        (expect (eq (cl-cmatrix/cli::%option-keyword invocation :color) :cyan) :to-be-truthy)
        (expect (eq (cl-cmatrix/cli::%option-keyword invocation :charset) :katakana)
                :to-be-truthy)))))

(describe "%cmatrix-random-state"
  (it "returns a random state reproducibly seeded from an integer SEED"
    (let ((sequence-1 (loop with rs = (cl-cmatrix/cli::%cmatrix-random-state 9)
                             repeat 20 collect (random 100 rs)))
          (sequence-2 (loop with rs = (cl-cmatrix/cli::%cmatrix-random-state 9)
                             repeat 20 collect (random 100 rs))))
      (expect (equal sequence-1 sequence-2) :to-be-truthy)))

  (it "returns a fresh random state object every call when SEED is NIL"
    (expect (not (eq (cl-cmatrix/cli::%cmatrix-random-state nil)
                      (cl-cmatrix/cli::%cmatrix-random-state nil)))
            :to-be-truthy)))

(describe "the cl-cmatrix app spec: --help and --version"
  (it "exits 0 on --help without invoking the handler"
    (let ((output (with-output-to-string (out)
                    (expect (zerop (run-app (make-cmatrix-app) :argv '("cl-cmatrix" "--help")
                                        :stdout out))
                            :to-be-truthy))))
      (expect (search "cl-cmatrix" output) :to-be-truthy)))

  (it "exits 0 on --version and prints the app's version"
    (let ((output (with-output-to-string (out)
                    (expect (zerop (run-app (make-cmatrix-app) :argv '("cl-cmatrix" "--version")
                                        :stdout out))
                            :to-be-truthy))))
      (expect (search "cl-cmatrix" output) :to-be-truthy))))

(describe "main and image-entry-point (isolated: these really exit the process)"
  (it-isolated "main exits 0 for --version, without invoking the handler"
      (:systems ("cl-cmatrix") :package "CL-USER" :timeout 15)
    (cl-cmatrix/cli:main '("cl-cmatrix" "--version")))

  (it-isolated "image-entry-point resets *default-pathname-defaults* to the cwd, exits 0 for
--version"
      (:systems ("cl-cmatrix") :package "CL-USER" :timeout 15)
    (let ((sb-ext:*posix-argv* (list "cl-cmatrix" "--version")))
      (cl-cmatrix/cli:image-entry-point))))
