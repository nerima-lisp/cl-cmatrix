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

(define-option-round-trip :old-style nil ("-o") t)

(describe "%cmatrix-run-matrix-args"
  (it "resolves every option into RUN-MATRIX's own keyword-argument shape"
    (let* ((invocation (parse-argv (make-cmatrix-app)
                                    '("cl-cmatrix" "--speed" "2.5" "-C" "cyan" "-g" "katakana" "-b"
                                      "-o" "-L" "-f" "-t" "/dev/tty" "--fps" "60"
                                      "--workers" "8" "--seed" "42")))
           (args (cl-cmatrix/cli::%cmatrix-run-matrix-args invocation)))
      (with-soft-assertions
        (expect (= (getf args :speed) 2.5d0) :to-be-truthy)
        (expect (eq (getf args :color) :cyan) :to-be-truthy)
        (expect (eq (getf args :glyphs) +katakana-glyphs+) :to-be-truthy)
        (expect (not (getf args :bold)) :to-be-truthy)
        (expect (getf args :partial-bold-p) :to-be-truthy)
        (expect (not (getf args :no-bold-p)) :to-be-truthy)
        (expect (getf args :old-style-p) :to-be-truthy)
        (expect (not (getf args :asyncp)) :to-be-truthy)
        (expect (getf args :lockp) :to-be-truthy)
        (expect (getf args :force-linux-term) :to-be-truthy)
        (expect (string= (getf args :tty) "/dev/tty") :to-be-truthy)
        (expect (= (getf args :fps) 60) :to-be-truthy)
        (expect (null (getf args :update-delay)) :to-be-truthy)
        (expect (= (getf args :workers) 8) :to-be-truthy)
        (expect (typep (getf args :random-state) 'random-state) :to-be-truthy))))

  (it "maps -a and -o to independent runtime modes"
    (let* ((async-invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-a")))
           (async-args (cl-cmatrix/cli::%cmatrix-run-matrix-args async-invocation))
           (old-style-invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-o")))
           (old-style-args (cl-cmatrix/cli::%cmatrix-run-matrix-args old-style-invocation))
           (combined-invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-a" "-o")))
           (combined-args (cl-cmatrix/cli::%cmatrix-run-matrix-args combined-invocation)))
      (with-soft-assertions
        (expect (getf async-args :asyncp) :to-be-truthy)
        (expect (not (getf async-args :old-style-p)) :to-be-truthy)
        (expect (getf old-style-args :old-style-p) :to-be-truthy)
        (expect (not (getf old-style-args :asyncp)) :to-be-truthy)
        (expect (getf combined-args :asyncp) :to-be-truthy)
        (expect (getf combined-args :old-style-p) :to-be-truthy))))

  (it "defaults to green ASCII at speed 1.0, unbolded, upstream delay 4, from an unseeded random state"
    (let* ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix")))
           (args (cl-cmatrix/cli::%cmatrix-run-matrix-args invocation)))
      (with-soft-assertions
        (expect (= (getf args :speed) 1.0d0) :to-be-truthy)
        (expect (eq (getf args :color) :green) :to-be-truthy)
        (expect (eq (getf args :glyphs) +default-glyphs+) :to-be-truthy)
        (expect (not (getf args :bold)) :to-be-truthy)
        (expect (not (getf args :partial-bold-p)) :to-be-truthy)
        (expect (not (getf args :no-bold-p)) :to-be-truthy)
        (expect (not (getf args :old-style-p)) :to-be-truthy)
        (expect (not (getf args :asyncp)) :to-be-truthy)
        (expect (not (getf args :lockp)) :to-be-truthy)
        (expect (not (getf args :force-linux-term)) :to-be-truthy)
        (expect (not (getf args :tty)) :to-be-truthy)
        (expect (null (getf args :fps)) :to-be-truthy)
        (expect (= (getf args :update-delay) +default-update-delay+) :to-be-truthy)
        (expect (= (getf args :workers) +default-workers+) :to-be-truthy)))))

  (it "passes an explicit upstream update delay when --fps is absent"
    (let* ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-u" "6")))
           (args (cl-cmatrix/cli::%cmatrix-run-matrix-args invocation)))
      (with-soft-assertions
        (expect (null (getf args :fps)) :to-be-truthy)
        (expect (= (getf args :update-delay) 6) :to-be-truthy))))

  (it "passes an explicit upstream update delay when --fps is absent"
    (let* ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-u" "6")))
           (args (cl-cmatrix/cli::%cmatrix-run-matrix-args invocation)))
      (with-soft-assertions
        (expect (null (getf args :fps)) :to-be-truthy)
        (expect (= (getf args :update-delay) 6) :to-be-truthy))))

(describe "%option-keyword"
  (it "upcases and interns the parsed string value of OPTION-NAME into the keyword package"
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-C" "cyan" "-g" "katakana"))))
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

(describe "the cl-cmatrix app spec: help and version aliases"
  (it "exits 0 on --help and -h without invoking the handler"
    (dolist (option '("--help" "-h"))
      (let ((output (with-output-to-string (out)
                      (expect (zerop (run-app (make-cmatrix-app)
                                              :argv (list "cl-cmatrix" option)
                                              :stdout out))
                              :to-be-truthy))))
        (expect (search "cl-cmatrix" output) :to-be-truthy))))

  (it "exits 0 on --version and -V and prints the app's version"
    (dolist (option '("--version" "-V"))
      (let ((output (with-output-to-string (out)
                      (expect (zerop (run-app (make-cmatrix-app)
                                              :argv (list "cl-cmatrix" option)
                                              :stdout out))
                              :to-be-truthy))))
        (expect (search "cl-cmatrix" output) :to-be-truthy)))))

(describe "main and image-entry-point (isolated: these really exit the process)"
  (it-isolated "main exits 0 for --version, without invoking the handler"
      (:systems ("cl-cmatrix") :package "CL-USER" :timeout 15)
    (cl-cmatrix/cli:main '("cl-cmatrix" "--version")))

  (it-isolated "image-entry-point resets *default-pathname-defaults* to the cwd, exits 0 for
--version"
      (:systems ("cl-cmatrix") :package "CL-USER" :timeout 15)
    (let ((sb-ext:*posix-argv* (list "cl-cmatrix" "--version")))
      (cl-cmatrix/cli:image-entry-point))))
