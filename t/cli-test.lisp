;;;; t/cli-test.lisp
;;;;
;;;; Flag parsing, plus the handler's own wiring. RUN-MATRIX takes over a real
;;;; terminal, so no case here ever reaches it: RUN-APP is called only with
;;;; --help or --version, and the %CMATRIX-HANDLER cases pass their own
;;;; recorder as :RUN-MATRIX-FN, the defaulted-keyword seam that exists so the
;;;; handler can be executed without the animation starting -- the same shape
;;;; t/run-state-test.lisp uses for :TERMINAL-SIZE-FN.
;;;; The IT-ISOLATED cases at the bottom exercise MAIN and
;;;; IMAGE-ENTRY-POINT for real, in a subprocess, for the same reason they
;;;; are never called directly above: both end in HOST-KIT:QUIT, a genuine
;;;; process exit that would kill this test runner if called in-process.
;;;; SB-COVER's coverage data is per-process, so this subprocess's execution
;;;; is invisible to CL-WEAVE:COVERAGE-STATISTICS in the parent regardless --
;;;; these are here for their value as real execution tests, not for
;;;; coverage percentage (see scripts/coverage-entry.lisp's header comment).

(in-package #:cl-cmatrix/test)

(defun run-matrix-args (tokens)
  "The RUN-MATRIX keyword plist the argv (\"cl-cmatrix\" . TOKENS) resolves
to, through the real MAKE-CMATRIX-APP spec and the real cl-cli parser. No
option metadata is stubbed anywhere in this file, so a flag that is renamed,
retyped or deleted in cli-options.lisp fails these cases rather than being
mocked past them."
  (cl-cmatrix/cli::%cmatrix-run-matrix-args
   (parse-argv (make-cmatrix-app) (cons "cl-cmatrix" tokens))))

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
;; -c is upstream's classic-CJK flag and -m is upstream's lambda render mode.
;; Both are plain flags now; neither is a --charset value.
(define-option-round-trip :japanese nil ("-c") t)
(define-option-round-trip :lambda nil ("-m") t)
;; --charset offers exactly ascii/classic/katakana/binary. "lambda" was a
;; choice here once and is not one now, which is what the REJECTS arm pins.
(define-option-round-trip :charset "ascii" ("-g" "binary") "binary" ("-g" "lambda"))

(describe "%cmatrix-run-matrix-args"
  (it "resolves every option into RUN-MATRIX's own keyword-argument shape"
    (let ((args (run-matrix-args '("--speed" "2.5" "-C" "cyan" "-g" "katakana" "-b"
                                   "-o" "-L" "-f" "-t" "/dev/tty" "--fps" "60"
                                   "--workers" "8" "--seed" "42"))))
      (with-soft-assertions
        (expect (= (getf args :speed) 2.5d0) :to-be-truthy)
        (expect (eq (getf args :color) :cyan) :to-be-truthy)
        (expect (eq (getf args :glyphs) +katakana-glyphs+) :to-be-truthy)
        (expect (not (getf args :lambda-p)) :to-be-truthy)
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
    (let ((async-args (run-matrix-args '("-a")))
          (old-style-args (run-matrix-args '("-o")))
          (combined-args (run-matrix-args '("-a" "-o"))))
      (with-soft-assertions
        (expect (getf async-args :asyncp) :to-be-truthy)
        (expect (not (getf async-args :old-style-p)) :to-be-truthy)
        (expect (getf old-style-args :old-style-p) :to-be-truthy)
        (expect (not (getf old-style-args :asyncp)) :to-be-truthy)
        (expect (getf combined-args :asyncp) :to-be-truthy)
        (expect (getf combined-args :old-style-p) :to-be-truthy))))

  (it "defaults to green ASCII at speed 1.0, unbolded, upstream delay 4, unseeded"
    (let ((args (run-matrix-args '())))
      (with-soft-assertions
        (expect (= (getf args :speed) 1.0d0) :to-be-truthy)
        (expect (eq (getf args :color) :green) :to-be-truthy)
        (expect (eq (getf args :glyphs) +default-glyphs+) :to-be-truthy)
        (expect (not (getf args :lambda-p)) :to-be-truthy)
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
        (expect (= (getf args :workers) +default-workers+) :to-be-truthy))))

  (it "passes an explicit upstream update delay when --fps is absent"
    (let ((args (run-matrix-args '("-u" "6"))))
      (with-soft-assertions
        (expect (null (getf args :fps)) :to-be-truthy)
        (expect (= (getf args :update-delay) 6) :to-be-truthy))))

  ;; cl-cli's OPTION-VALUE-SOURCE returns NIL, not :DEFAULT, for an absent
  ;; option that carries no literal default -- which --fps does not. The
  ;; resolution therefore compares against :COMMAND-LINE explicitly, and this
  ;; case is what stops that comparison from silently becoming (NOT NULL).
  (it "lets an explicit --fps suppress -u, and leaves -u in force otherwise"
    (let ((fps-args (run-matrix-args '("--fps" "60" "-u" "6")))
          (delay-args (run-matrix-args '("-u" "6"))))
      (with-soft-assertions
        (expect (= (getf fps-args :fps) 60) :to-be-truthy)
        (expect (null (getf fps-args :update-delay)) :to-be-truthy)
        (expect (null (getf delay-args :fps)) :to-be-truthy)
        (expect (= (getf delay-args :update-delay) 6) :to-be-truthy))))

  ;; -u is upstream's delay and a LARGER value is SLOWER; --speed is ours and
  ;; divides that delay, so a LARGER value is FASTER. The two knobs point
  ;; opposite ways, and nothing but this case pins the direction of either.
  ;; Every expected tick count below is a literal, never recomputed from the
  ;; CLI's own output, so an inverted resolution cannot agree with itself.
  (it "points -u and --speed in opposite directions through the tick resolution"
    (flet ((ticks (tokens)
             (let ((args (run-matrix-args tokens)))
               (cl-cmatrix::%update-ticks (getf args :fps)
                                          (getf args :update-delay)
                                          (getf args :speed)))))
      (with-soft-assertions
        (expect (= (ticks '("-u" "2")) 2) :to-be-truthy)
        (expect (= (ticks '("-u" "8")) 8) :to-be-truthy)
        (expect (= (ticks '("--speed" "1")) 4) :to-be-truthy)
        (expect (= (ticks '("--speed" "4")) 1) :to-be-truthy)
        (expect (< (ticks '("-u" "2")) (ticks '("-u" "8"))) :to-be-truthy)
        (expect (> (ticks '("--speed" "1")) (ticks '("--speed" "4"))) :to-be-truthy)))))

(describe "-c/--classic/--japanese: upstream's classic CJK glyph set"
  (it-each (("-c") ("--classic") ("--japanese"))
           "~A selects +CLASSIC-GLYPHS+, the set upstream's own -c draws"
           (token)
           (let ((args (run-matrix-args (list token))))
             (with-soft-assertions
               (expect (eq (getf args :glyphs) +classic-glyphs+) :to-be-truthy)
               (expect (not (eq (getf args :glyphs) +katakana-glyphs+)) :to-be-truthy)
               (expect (not (getf args :lambda-p)) :to-be-truthy))))

  ;; Half-width katakana used to ride on -c under a --katakana alias. It does
  ;; not any more: it is reachable only through --charset, and --katakana is
  ;; now an unknown option rather than a second spelling of -c.
  (it "reaches half-width katakana only through --charset, never through -c"
    (with-soft-assertions
      (expect (eq (getf (run-matrix-args '("-g" "katakana")) :glyphs) +katakana-glyphs+)
              :to-be-truthy)
      (expect (eq (getf (run-matrix-args '("--charset" "katakana")) :glyphs)
                  +katakana-glyphs+)
              :to-be-truthy)
      (expect (signals cl-cli:cli-unknown-option
                       (parse-argv (make-cmatrix-app) '("cl-cmatrix" "--katakana")))
              :to-be-truthy)))

  (it "overrides --charset without disturbing the value --charset itself parsed"
    (let ((invocation (parse-argv (make-cmatrix-app) '("cl-cmatrix" "-c" "-g" "binary"))))
      (with-soft-assertions
        (expect (string= (option-value invocation :charset) "binary") :to-be-truthy)
        (expect (eq (getf (cl-cmatrix/cli::%cmatrix-run-matrix-args invocation) :glyphs)
                    +classic-glyphs+)
                :to-be-truthy)))))

(describe "-m/--lambda: a render mode over whichever glyph set is in force"
  (it-each (("-m") ("--lambda"))
           "~A sets :LAMBDA-P without touching the glyph set"
           (token)
           (let ((args (run-matrix-args (list token))))
             (with-soft-assertions
               (expect (getf args :lambda-p) :to-be-truthy)
               (expect (eq (getf args :glyphs) +default-glyphs+) :to-be-truthy))))

  ;; IT-EACH quotes its case data, so EXPECTED arrives as the constant's name
  ;; and SYMBOL-VALUE reads it. Naming the +...-GLYPHS+ constant keeps the
  ;; oracle anchored there rather than routing it back through the same
  ;; CHARSET-GLYPHS registry the resolution under test already consulted.
  (it-each ((("-g" "binary") +binary-glyphs+)
            (("-g" "katakana") +katakana-glyphs+)
            (("-c") +classic-glyphs+))
           "composes with ~A rather than replacing its glyphs"
           (tokens expected)
           (let ((args (run-matrix-args (append '("-m") tokens))))
             (with-soft-assertions
               (expect (getf args :lambda-p) :to-be-truthy)
               (expect (eq (getf args :glyphs) (symbol-value expected)) :to-be-truthy)))))

(describe "--charset: the four registered glyph sets, and only those"
  (it-each (("ascii" +default-glyphs+)
            ("classic" +classic-glyphs+)
            ("katakana" +katakana-glyphs+)
            ("binary" +binary-glyphs+))
           "resolves --charset ~A to its registered glyph vector"
           (name expected)
           (let ((glyphs (symbol-value expected)))
             (with-soft-assertions
               (expect (eq (getf (run-matrix-args (list "-g" name)) :glyphs) glyphs)
                       :to-be-truthy)
               (expect (eq (getf (run-matrix-args (list "--charset" name)) :glyphs) glyphs)
                       :to-be-truthy))))

  ;; "lambda" was a --charset choice before -m became a render mode. Keeping
  ;; it rejected is the only thing that stops the old spelling from quietly
  ;; coming back as a fifth glyph set.
  (it-each (("lambda") ("japanese") ("cjk") (""))
           "rejects ~S, which names no registered charset"
           (name)
           (expect (signals cli-invalid-option-value
                            (parse-argv (make-cmatrix-app)
                                        (list "cl-cmatrix" "-g" name)))
                   :to-be-truthy)))

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

(defun record-handler-call (tokens)
  "Run the real %CMATRIX-HANDLER over the argv (\"cl-cmatrix\" . TOKENS),
passing a recorder as :RUN-MATRIX-FN instead of letting RUN-MATRIX take the
terminal, and return three values: the keyword plist RUN-MATRIX was actually
applied to, the value of TERM as seen from inside that call, and the
handler's own return value.

Nothing else is stubbed. The invocation comes from the real MAKE-CMATRIX-APP
spec through the real cl-cli parser, and the plist is whatever
%CMATRIX-RUN-MATRIX-ARGS built and %CMATRIX-RUN-WITH-TERMINAL forwarded, so
these cases pin the wiring between the two rather than re-testing either.
The initial :NEVER-CALLED distinguishes \"RUN-MATRIX received an empty
plist\" from \"RUN-MATRIX was never reached\", which NIL would not.

The handler is called directly rather than through RUN-APP, exactly as the
IT-ISOLATED cases below call MAIN directly: cl-cli hands a handler nothing
but the invocation, so the injection point has to be this call, and being an
argument rather than a special variable is what keeps it independent of which
thread ends up doing the work."
  (let ((seen-args :never-called)
        (seen-term :never-called))
    (let ((code (cl-cmatrix/cli::%cmatrix-handler
                 (parse-argv (make-cmatrix-app) (cons "cl-cmatrix" tokens))
                 :run-matrix-fn (lambda (&rest args)
                                  (setf seen-args args
                                        seen-term (sb-ext:posix-getenv "TERM"))
                                  nil))))
      (values seen-args seen-term code))))

(describe "%cmatrix-handler: what actually reaches RUN-MATRIX"
  ;; %CMATRIX-RUN-MATRIX-ARGS' own cases above prove the plist is built
  ;; correctly and t/runtime-test.lisp proves RUN-MATRIX validates what it is
  ;; given; neither shows the one plist arriving at the other function.
  (it "applies RUN-MATRIX to the plist %CMATRIX-RUN-MATRIX-ARGS resolved"
    (multiple-value-bind (args term code)
        (record-handler-call '("--speed" "2.5" "-C" "cyan" "-g" "katakana" "-u" "6"
                               "-o" "-L" "--workers" "8" "--seed" "42"))
      (declare (ignore term))
      (with-soft-assertions
        (expect (not (eq args :never-called)) :to-be-truthy)
        (expect (= (getf args :speed) 2.5d0) :to-be-truthy)
        (expect (eq (getf args :color) :cyan) :to-be-truthy)
        (expect (eq (getf args :glyphs) +katakana-glyphs+) :to-be-truthy)
        (expect (= (getf args :update-delay) 6) :to-be-truthy)
        (expect (null (getf args :fps)) :to-be-truthy)
        (expect (getf args :old-style-p) :to-be-truthy)
        (expect (getf args :lockp) :to-be-truthy)
        (expect (= (getf args :workers) 8) :to-be-truthy)
        (expect (typep (getf args :random-state) 'random-state) :to-be-truthy)
        (expect (eql code 0) :to-be-truthy))))

  ;; RUN-MATRIX has no :FORCE-LINUX-TERM parameter, so a plist that still
  ;; carries the key is a live crash in the delivered binary and not merely
  ;; untidy. The default argument to GETF is what makes the check exact: a
  ;; plain (GETF ARGS :FORCE-LINUX-TERM) cannot tell an absent key from a
  ;; present NIL one.
  (it "strips :FORCE-LINUX-TERM and runs the call under TERM=linux for -f"
    (multiple-value-bind (args term code) (record-handler-call '("-f"))
      (with-soft-assertions
        (expect (eq (getf args :force-linux-term :absent) :absent) :to-be-truthy)
        (expect (equal term "linux") :to-be-truthy)
        (expect (eql code 0) :to-be-truthy))))

  ;; The other arm of the same branch: without -f the handler must not enter
  ;; WITH-ENVIRONMENT-VARIABLES at all. Comparing against the ambient TERM
  ;; rather than against "not linux" keeps this honest on a host whose TERM
  ;; really is linux.
  (it "leaves TERM alone when -f is absent, and still strips the key"
    (multiple-value-bind (args term code) (record-handler-call '())
      (with-soft-assertions
        (expect (eq (getf args :force-linux-term :absent) :absent) :to-be-truthy)
        (expect (equal term (sb-ext:posix-getenv "TERM")) :to-be-truthy)
        (expect (eql code 0) :to-be-truthy))))

  ;; :TTY is likewise not a RUN-MATRIX parameter. It is removed on the way
  ;; into %CMATRIX-RUN-WITH-TERMINAL, which means it has to be gone on the
  ;; no-tty arm too -- the arm every ordinary invocation takes.
  (it "strips :TTY even on the branch where no --tty was given"
    (multiple-value-bind (args term code) (record-handler-call '())
      (declare (ignore term))
      (with-soft-assertions
        (expect (eq (getf args :tty :absent) :absent) :to-be-truthy)
        (expect (eq (getf args :stream :absent) :absent) :to-be-truthy)
        (expect (eql code 0) :to-be-truthy)))))

(describe "--tty: only a terminal is a terminal"
  ;; Handing --tty a regular file used to open it and hand RUN-MATRIX its
  ;; descriptor, which wrote the animation into the file from byte zero. The
  ;; rejection has to land before the descriptor is taken, so this checks that
  ;; RUN-MATRIX was never reached.
  ;;
  ;; The surviving-file rows are not decoration. WITH-OPEN-FILE closes with
  ;; :ABORT T on a non-local exit, and an aborted close of a :DIRECTION :IO
  ;; stream deletes the file -- so a rejection signalled from inside that
  ;; macro erases the very file the user misnamed. Both rows failed against
  ;; exactly that arrangement before %CMATRIX-RUN-WITH-TERMINAL switched to
  ;; OPEN plus an explicit CLOSE, which is why they are here and why the
  ;; teardown deletes conditionally rather than assuming.
  (it "refuses a --tty naming a regular file, before RUN-MATRIX is reached"
    (let ((path (format nil "/tmp/cl-cmatrix-cli-test-~D-~D.tty"
                        (sb-unix:unix-getpid) (random 1000000)))
          (called nil))
      (with-open-file (out path :direction :output :if-exists :supersede)
        (write-line "not a terminal" out))
      (unwind-protect
           (flet ((record (&rest args)
                    (declare (ignore args))
                    (setf called t)
                    nil))
             (with-soft-assertions
               (expect (signals error
                                (cl-cmatrix/cli::%cmatrix-handler
                                 (parse-argv (make-cmatrix-app)
                                             (list "cl-cmatrix" "-t" path))
                                 :run-matrix-fn #'record))
                       :to-be-truthy)
               (expect (not called) :to-be-truthy)
               (expect (and (probe-file path) t) :to-be-truthy)
               (expect (equal (when (probe-file path)
                                (with-open-file (in path) (read-line in)))
                              "not a terminal")
                       :to-be-truthy)))
        (when (probe-file path)
          (delete-file path))))))

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
