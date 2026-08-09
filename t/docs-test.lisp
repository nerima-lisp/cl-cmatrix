;;;; t/docs-test.lisp
;;;;
;;;; Documentation-to-implementation consistency. docs/src/ names symbols and
;;;; command-line options in prose; nothing but a reader's attention normally
;;;; stops that prose from drifting away from src/. These specs read the
;;;; markdown live on every run -- never a copy checked in here -- and assert
;;;; that every name the docs claim as public really is exported, and every
;;;; option spelling the docs show in a working command really is accepted.
;;;;
;;;; WHAT MAKES THIS HARD. A backticked span in these documents is not a symbol
;;;; name. It is just as likely to be `nix flake check`, `flake.nix`, a runtime
;;;; key like `q`, an upstream C fragment like `rand() % 90 + 33`, an
;;;; environment variable, or -- worst of all -- an option this project
;;;; deliberately does NOT have: docs/src/reference/compatibility.md documents
;;;; `-l` and `-x` as permanent non-goals, `--katakana` as removed, and
;;;; `--charset lambda` as rejected, all in backticks. Any rule that treats
;;;; every backticked token as an API claim reports those as defects.
;;;;
;;;; So the extraction rules below are keyed on the CONTEXT that makes a token
;;;; a claim, not on the token's own shape:
;;;;
;;;;   1. `cl-cmatrix:NAME` / `cl-cmatrix/cli:NAME` -- a single-colon package
;;;;      qualifier IS the claim that NAME is external. The double-colon form
;;;;      is skipped, because api.md documents those two colons as the way to
;;;;      reach an internal symbol.
;;;;   2. A heading whose entire text is one code span, and a same-page anchor
;;;;      link `[`name`](#name)` -- both say "this document documents NAME".
;;;;   3. An option token inside a `cl-cmatrix ...` invocation, and an option
;;;;      token in a table cell that is nothing but a comma-separated list of
;;;;      option spans -- both say "this spelling works". `--opt=value` is one
;;;;      of those spellings: CL-CLI splits a long token on its first #\= and
;;;;      resolves only the left side, so the name is what gets checked.
;;;;
;;;; Everything else is ignored on purpose. That conservatism is what a rule
;;;; keyed on shape alone cannot buy, and it is also what makes the
;;;; non-vacuity specs in the first DESCRIBE mandatory rather than decorative:
;;;; a rule this selective fails silently by matching nothing, and a broken
;;;; docs path or a docs/ tree missing from the build's source closure would
;;;; leave every remaining spec passing over an empty corpus.
;;;;
;;;; NOT CHECKED, deliberately: the reverse direction. An exported symbol that
;;;; no document mentions is not a defect here -- requiring every export to be
;;;; documented would be a different, stricter policy, and requiring every
;;;; internal function to stay out of the docs would forbid architecture.md
;;;; from explaining the implementation at all.

(in-package #:cl-cmatrix/test)

;;; -------------------------------------------------------------------------
;;; Reading the corpus

(defun %docs-directory ()
  "The documentation source tree, resolved through ASDF rather than through
*DEFAULT-PATHNAME-DEFAULTS* so the specs read the same files whether they run
from a checkout, from `nix run .#test`, or from an installed system. Same
mechanism t/mutation-test.lisp uses to read src/ live."
  (asdf:system-relative-pathname "cl-cmatrix" "docs/src/"))

(defun %docs-pathnames ()
  "Every .md file under %DOCS-DIRECTORY, at any depth, in a stable order."
  (sort (directory (merge-pathnames
                    (make-pathname :directory '(:relative :wild-inferiors)
                                   :name :wild :type "md")
                    (%docs-directory)))
        #'string< :key #'namestring))

(defun %docs-read-file (pathname)
  "PATHNAME's entire contents as a string. UTF-8 is named explicitly because
getting-started.md quotes CJK glyphs, and a reader defaulting to Latin-1 would
turn them into mojibake rather than fail."
  (with-open-file (stream pathname :external-format :utf-8)
    (let ((text (make-string (file-length stream))))
      (subseq text 0 (read-sequence text stream)))))

(defvar *docs-corpus* nil
  "Memoized (RELATIVE-NAME TEXT) entries, filled on first use. Only a
non-empty result is cached, so a run that finds no documentation retries
rather than freezing the empty answer that would make every later spec pass
vacuously.")

(defun %docs-corpus ()
  "The documentation corpus as (RELATIVE-NAME TEXT) entries."
  (or *docs-corpus*
      (setf *docs-corpus*
            (mapcar (lambda (pathname)
                      (list (enough-namestring pathname (%docs-directory))
                            (%docs-read-file pathname)))
                    (%docs-pathnames)))))

;;; -------------------------------------------------------------------------
;;; String utilities. Plain CL: cl-cmatrix has no regular-expression
;;; dependency, and cl-cmatrix.asd records that omission as deliberate.

(defun %docs-trim (string)
  (string-trim '(#\Space #\Tab #\Return) string))

(defun %docs-split (character string)
  "STRING split on every occurrence of CHARACTER, empty parts included."
  (let ((parts '())
        (start 0))
    (loop for index = (position character string :start start)
          do (push (subseq string start (or index (length string))) parts)
             (if index (setf start (1+ index)) (return)))
    (nreverse parts)))

(defun %docs-lines (text)
  (%docs-split #\Newline text))

(defun %docs-prefix-at-p (string index prefix)
  "True when PREFIX appears in STRING at INDEX, compared without case."
  (let ((end (+ index (length prefix))))
    (and (<= 0 index)
         (<= end (length string))
         (string-equal string prefix :start1 index :end1 end))))

(defun %docs-code-spans (line)
  "Every `...` span's contents in LINE, in order."
  (let ((spans '())
        (start 0))
    (loop for open = (position #\` line :start start)
          while open
          do (let ((close (position #\` line :start (1+ open))))
               (unless close (return))
               (push (subseq line (1+ open) close) spans)
               (setf start (1+ close))))
    (nreverse spans)))

(defun %docs-sole-span (string)
  "STRING's contents when STRING is exactly one code span and nothing else."
  (let ((length (length string)))
    (when (and (>= length 3)
               (char= (char string 0) #\`)
               (char= (char string (1- length)) #\`)
               (= 2 (count #\` string)))
      (subseq string 1 (1- length)))))

;;; -------------------------------------------------------------------------
;;; Rule 1: package-qualified references

(defun %docs-symbol-character-p (character)
  "True for a character that can appear in a Lisp symbol name as these
documents spell them. Excludes #\\: so a qualifier ends the name, and excludes
#\\. and #\\/ so a filename or a URL following a qualifier cannot be absorbed
into one."
  (or (alphanumericp character)
      (find character "-+*<>=&%")))

(defun %docs-name-at (text index)
  "The run of symbol characters in TEXT starting at INDEX."
  (let ((end index))
    (loop while (and (< end (length text))
                     (%docs-symbol-character-p (char text end)))
          do (incf end))
    (subseq text index end)))

(defun %docs-qualified-references (text)
  "Every (NAME PACKAGE-NAME) TEXT writes as cl-cmatrix:NAME or
cl-cmatrix/cli:NAME.

The double-colon form is skipped rather than checked. api.md documents
`cl-cmatrix::` as precisely the spelling that reaches something unsupported,
so a name written that way is a claim that the symbol is INTERNAL -- asserting
it were external would invert the documented meaning."
  (let ((references '())
        (root "cl-cmatrix")
        (start 0))
    (loop for hit = (search root text :start2 start :test #'char-equal)
          while hit
          do (let* ((after-root (+ hit (length root)))
                    (cli-p (%docs-prefix-at-p text after-root "/cli"))
                    (after-package (if cli-p (+ after-root 4) after-root))
                    (package-name (if cli-p "CL-CMATRIX/CLI" "CL-CMATRIX")))
               (setf start after-root)
               (when (and (%docs-prefix-at-p text after-package ":")
                          (not (%docs-prefix-at-p text (1+ after-package) ":")))
                 (let ((name (%docs-name-at text (1+ after-package))))
                   (when (plusp (length name))
                     (push (list name package-name) references))))))
    (nreverse references)))

;;; -------------------------------------------------------------------------
;;; Rule 2: headings and same-page anchor links

(defun %docs-heading-name (line)
  "LINE's code span when LINE is an ATX heading whose whole text is one span.

`## Why \\`matrix-state\\` and \\`run-state\\` are separate structs` is not one
span and is therefore not a claim that either name is public -- which is the
right answer, since both are internal."
  (let ((trimmed (%docs-trim line)))
    (when (and (plusp (length trimmed)) (char= (char trimmed 0) #\#))
      (%docs-sole-span (%docs-trim (string-left-trim "#" trimmed))))))

(defun %docs-anchor-link-names (line)
  "Every NAME LINE writes as [`NAME`](#anchor).

The #-anchor is required: [`--charset katakana`](../getting-started.md#...) in
compatibility.md points at another page's section rather than at a symbol
documented here, and is not a claim about a symbol at all."
  (let ((names '())
        (start 0))
    (loop for open = (search "[`" line :start2 start)
          while open
          do (let ((close (position #\` line :start (+ open 2))))
               (unless close (return))
               (when (%docs-prefix-at-p line (1+ close) "](#")
                 (push (subseq line (+ open 2) close) names))
               (setf start (1+ close))))
    (nreverse names)))

(defun %docs-api-name-shape-p (name)
  "True when NAME is spelled like a Lisp symbol and like nothing else:
lowercase letters, digits, and - + * only, opening with a lowercase letter or
a #\\+. This is the second gate behind the context rules, and it is what keeps
`nix flake check` (spaces), `flake.nix` (a dot), `~/common-lisp/` (a slash),
`$out` and `--charset` (a leading punctuation character) out of the candidate
set even if one of them ever became a heading."
  (flet ((lowercase-letter-p (character)
           (and (alpha-char-p character) (lower-case-p character))))
    (and (plusp (length name))
         (or (lowercase-letter-p (char name 0)) (char= (char name 0) #\+))
         (every (lambda (character)
                  (or (lowercase-letter-p character)
                      (digit-char-p character)
                      (find character "-+*")))
                name))))

;;; -------------------------------------------------------------------------
;;; Rule 3: command-line option spellings

(defun %docs-option-token-name (token)
  "TOKEN reduced to the part CL-CLI would look an option up by: everything
before the first #\\= in a --long token, or TOKEN unchanged.

This mirrors CL-CLI's own PARSE-LONG-OPTION-TOKEN, which splits a long token
on its first #\\= and canonicalises only the left half, so `--charset=binary'
and `--charset binary' reach the same option -- measured against CL-CLI 1.3.0,
both parse to :CHARSET \"binary\", and `--bogus=1' is rejected as the unknown
option `--bogus'.

The split is deliberately restricted to the long form. CL-CLI performs no such
split on a short cluster: `-g=binary' reaches --charset carrying the literal
value \"=binary\", which its :CHOICES then rejects. Treating `-g=binary' as a
spelling of -g here would therefore endorse an invocation that does not work."
  (if (%docs-prefix-at-p token 0 "--")
      (let ((equals (position #\= token)))
        (if equals (subseq token 0 equals) token))
      token))

(defun %docs-option-token-p (token)
  "True when TOKEN is an option spelling: --long-name, --long-name=value, or
-x for one letter.

The attached-value form has to be admitted rather than merely tolerated. It is
a spelling CL-CLI accepts, so a document showing `--bogus=1' is claiming an
option that does not exist; excluding the form would let exactly that claim
through unchecked, because a token this rule rejects is never looked up at all.

Only the name half is shape-checked. What follows the #\\= is a value -- a
path, a message, a number -- and constraining it would put this rule back in
the business of judging values, which is the parser's job and not this file's."
  (let* ((name (%docs-option-token-name token))
         (length (length name)))
    (cond ((and (> length 2) (string= "--" name :end2 2))
           (every (lambda (character)
                    (or (alphanumericp character) (char= character #\-)))
                  (subseq name 2)))
          ((= length 2)
           (and (char= (char name 0) #\-) (alpha-char-p (char name 1))))
          (t nil))))

(defun %docs-invocation-tokens (command)
  "COMMAND's option tokens when COMMAND is a `cl-cmatrix ...' invocation.

Anything from a #\\# onward is dropped first: the shell blocks in
getting-started.md carry a trailing prose comment on every line, and prose is
exactly where a flag gets mentioned without being claimed to work."
  (let ((trimmed (%docs-trim command)))
    (when (and (%docs-prefix-at-p trimmed 0 "cl-cmatrix")
               (or (= (length trimmed) 10)
                   (char= (char trimmed 10) #\Space)))
      (let* ((comment (position #\# trimmed))
             (body (subseq trimmed 0 (or comment (length trimmed)))))
        (remove-if-not #'%docs-option-token-p (%docs-split #\Space body))))))

(defun %docs-table-cell-tokens (cell)
  "CELL's option tokens when CELL is nothing but a comma-separated list of
single-option code spans, as compatibility.md's spelling tables are.

Requiring the WHOLE cell to be such a list is what separates a claim from a
mention: `\\`-c\\`, \\`--classic\\`, \\`--japanese\\`` is a list of spellings this
program accepts, while `\\`-c\\` classic Japanese glyphs` -- the upstream column
of the same table -- carries prose and is excluded."
  (let ((tokens '()))
    (dolist (part (%docs-split #\, cell) (nreverse tokens))
      (let ((span (%docs-sole-span (%docs-trim part))))
        (unless (and span (%docs-option-token-p span))
          (return nil))
        (push span tokens)))))

;;; -------------------------------------------------------------------------
;;; Candidate sets

(defun %docs-collect (extractor)
  "Apply EXTRACTOR to each corpus entry's text and tag every result with the
file it came from, dropping repeats of the same (FILE . RESULT) pair."
  (remove-duplicates
   (loop for (label text) in (%docs-corpus)
         append (mapcar (lambda (result)
                          (cons label (if (listp result) result (list result))))
                        (funcall extractor text)))
   :test #'equal :from-end t))

(defun %docs-qualified-candidates ()
  "(FILE NAME PACKAGE-NAME) for every package-qualified reference in the docs."
  (%docs-collect #'%docs-qualified-references))

(defun %docs-api-name-candidates ()
  "(FILE NAME) for every name a document gives its own heading or same-page
anchor link, filtered to symbol-shaped names."
  (%docs-collect
   (lambda (text)
     (loop for line in (%docs-lines text)
           append (let ((heading (%docs-heading-name line)))
                    (remove-if-not #'%docs-api-name-shape-p
                                   (append (when heading (list heading))
                                           (%docs-anchor-link-names line))))))))

(defun %docs-option-candidates ()
  "(FILE TOKEN) for every option spelling the docs show in a working
`cl-cmatrix' invocation or list as one of this program's own spellings."
  (%docs-collect
   (lambda (text)
     (let ((tokens '())
           (fencedp nil))
       (dolist (line (%docs-lines text) (nreverse tokens))
         (let ((trimmed (%docs-trim line)))
           (cond ((%docs-prefix-at-p trimmed 0 "```")
                  (setf fencedp (not fencedp)))
                 (fencedp
                  (dolist (token (%docs-invocation-tokens line))
                    (push token tokens)))
                 (t
                  (dolist (span (%docs-code-spans line))
                    (dolist (token (%docs-invocation-tokens span))
                      (push token tokens)))
                  (when (and (plusp (length trimmed))
                             (char= (char trimmed 0) #\|))
                    (dolist (cell (%docs-split #\| trimmed))
                      (dolist (token (%docs-table-cell-tokens cell))
                        (push token tokens))))))))))))

;;; -------------------------------------------------------------------------
;;; Oracles, both read from the implementation rather than restated here

(defun %docs-external-symbol-p (name package-names)
  "True when NAME is an EXTERNAL symbol of one of PACKAGE-NAMES. FIND-SYMBOL's
second value is the whole test: an internal symbol, or one merely accessible
by inheritance, is not a public name."
  (some (lambda (package-name)
          (eq :external (nth-value 1 (find-symbol (string-upcase name) package-name))))
        package-names))

(defun %docs-recognized-option-names ()
  "Every option spelling `cl-cmatrix' accepts, in CL-CLI's canonical form.

MAKE-CMATRIX-OPTIONS is this project's own declarative option set;
BUILT-IN-OPTION-SPECS adds the -h/--help and -V/--version flags CL-CLI
synthesises from MAKE-APP's :AUTO-HELP and :VERSION, which getting-started.md
and api.md both document and which are not in the project's own list."
  (let ((specs (append (cl-cmatrix/cli::make-cmatrix-options)
                       (cl-cli:built-in-option-specs (make-cmatrix-app)))))
    (loop for spec in specs
          append (append (cl-cli:option-names spec)
                         (cl-cli:option-negated-names spec)))))

(defun %docs-canonical-option-name (token)
  "TOKEN's attached `=value' dropped, then its leading dashes stripped and,
unless it is a single character, downcased. CL-CLI's OPTION-NAMES have already
been through its own CANONICAL-OPTION-NAME, which does exactly this and keeps
-x distinct from -X; that function is internal to CL-CLI, so the rule is
restated rather than reached for with a double colon.

Dropping the value first is the same order CL-CLI uses -- it splits on #\\=
and canonicalises the left half -- and it is what makes the lookup below ask
about the option rather than about the option-and-its-value, which would match
nothing and report every attached spelling as missing."
  (let ((name (string-left-trim "-" (%docs-option-token-name token))))
    (if (= (length name) 1) name (string-downcase name))))

(defun %docs-report (entries)
  "ENTRIES rendered as \"file: item\" strings, for a failure message that says
which document and which name rather than only how many."
  (mapcar (lambda (entry) (format nil "~A: ~A" (first entry) (second entry)))
          entries))

;;; -------------------------------------------------------------------------

(describe "docs/src: the corpus these checks read"
  ;; Every spec below this DESCRIBE passes over an empty corpus. These four
  ;; are what make the green meaningful: a docs/ tree missing from the build's
  ;; source closure, a renamed directory, or an extraction rule that stopped
  ;; matching all fail here rather than quietly reporting nothing to check.
  (it "finds markdown files under docs/src"
    (expect (plusp (length (%docs-corpus))) :to-be-truthy))

  (it "reaches nested pages, not only the top level"
    (expect (find "reference/api.md" (%docs-corpus) :key #'first :test #'string=)
            :to-be-truthy))

  (it "reads every file as non-empty text"
    (expect (mapcar #'first
                    (remove-if (lambda (entry) (plusp (length (second entry))))
                               (%docs-corpus)))
            :to-equal '()))

  (it "extracts package-qualified symbol references"
    (expect (plusp (length (%docs-qualified-candidates))) :to-be-truthy))

  (it "extracts documented API names"
    (expect (plusp (length (%docs-api-name-candidates))) :to-be-truthy))

  (it "extracts CLI option spellings"
    (expect (plusp (length (%docs-option-candidates))) :to-be-truthy)))

(describe "docs/src: the attached-value option rule, driven directly"
  ;; No document currently spells an option as `--opt=value' -- `rg --
  ;; "--[a-zA-Z0-9-]+=" docs/src/' matches nothing -- so the corpus cannot
  ;; reach that branch of the rule, and the specs above would stay green with
  ;; it removed entirely. That is precisely the shape of a check nobody
  ;; notices has died. These specs drive the branch with literal text instead,
  ;; so it is exercised on every run whether or not a document adopts the
  ;; spelling, and it goes red the moment it stops working.
  (it "extracts an attached-value spelling from an invocation"
    (expect (%docs-invocation-tokens "cl-cmatrix --charset=binary")
            :to-equal '("--charset=binary")))

  (it "looks the option up by the name to the left of the ="
    (with-soft-assertions
      (expect (%docs-canonical-option-name "--charset=binary") :to-equal "charset")
      (expect (member (%docs-canonical-option-name "--charset=binary")
                      (%docs-recognized-option-names) :test #'string=)
              :to-be-truthy)))

  (it "rejects an attached spelling of an option that does not exist"
    ;; The reason the form is admitted at all. A document writing
    ;; `cl-cmatrix --bogus=1' has to fail the existence check, and both halves
    ;; are asserted because either one quietly returning nothing would let the
    ;; claim through: an unextracted token is never looked up, and a token
    ;; carrying its value into the lookup would match nothing for the wrong
    ;; reason.
    (with-soft-assertions
      (expect (%docs-invocation-tokens "cl-cmatrix --bogus=1")
              :to-equal '("--bogus=1"))
      (expect (%docs-canonical-option-name "--bogus=1") :to-equal "bogus")
      (expect (member (%docs-canonical-option-name "--bogus=1")
                      (%docs-recognized-option-names) :test #'string=)
              :to-be-falsy)))

  (it "still ignores an attached spelling merely mentioned in prose"
    ;; The exact composition %DOCS-OPTION-CANDIDATES applies to an unfenced
    ;; line. Admitting `--opt=value' must not cost the conservatism that keeps
    ;; a discussion of an option out of the claim set.
    (let ((line "Both `--charset=binary` and `--charset binary` select binary."))
      (expect (loop for span in (%docs-code-spans line)
                    append (%docs-invocation-tokens span))
              :to-equal '())))

  (it "takes an attached spelling from a spelling table but not from prose"
    (with-soft-assertions
      (expect (%docs-table-cell-tokens " `--charset=binary` ")
              :to-equal '("--charset=binary"))
      (expect (%docs-table-cell-tokens " `--charset=binary` selects binary ")
              :to-equal '())))

  (it "does not treat -g=binary as a spelling of -g"
    ;; Measured against CL-CLI 1.3.0: a short cluster is not split on #\=, so
    ;; `-g=binary' reaches --charset carrying the literal value "=binary" and
    ;; is rejected by its :CHOICES. Accepting it here would endorse an
    ;; invocation that does not run.
    (expect (%docs-option-token-p "-g=binary") :to-be-falsy)))

(describe "docs/src: every symbol the docs present as public is exported"
  (it "every cl-cmatrix:NAME and cl-cmatrix/cli:NAME reference names an external symbol"
    (expect (%docs-report
             (loop for (label name package-name) in (%docs-qualified-candidates)
                   unless (%docs-external-symbol-p name (list package-name))
                     collect (list label (format nil "~(~A~):~A" package-name name))))
            :to-equal '()))

  (it "every name given its own heading or same-page anchor link is external"
    ;; Either package: api.md and conditions.md document CL-CMATRIX, while
    ;; architecture.md and development.md name the CLI package's entry points.
    ;; A name external in neither is documented as public but is not.
    (expect (%docs-report
             (loop for (label name) in (%docs-api-name-candidates)
                   unless (%docs-external-symbol-p name '("CL-CMATRIX" "CL-CMATRIX/CLI"))
                     collect (list label name)))
            :to-equal '())))

(describe "docs/src: every CLI option the docs show working exists"
  (it "every option spelling in an invocation or a spelling table is accepted"
    (let ((names (%docs-recognized-option-names)))
      (expect (%docs-report
               (loop for (label token) in (%docs-option-candidates)
                     unless (member (%docs-canonical-option-name token) names
                                    :test #'string=)
                       collect (list label token)))
              :to-equal '())))

  (it "the accepted set is the implementation's own, not a list restated here"
    ;; Guards the oracle rather than the docs: if MAKE-CMATRIX-OPTIONS ever
    ;; returns nothing, or CL-CLI's accessors stop returning names, the spec
    ;; above starts accepting nothing and would report every documented option
    ;; as missing -- or, with an empty candidate set, nothing at all.
    (with-soft-assertions
      (expect (plusp (length (%docs-recognized-option-names))) :to-be-truthy)
      (expect (member "charset" (%docs-recognized-option-names) :test #'string=)
              :to-be-truthy)
      (expect (member "help" (%docs-recognized-option-names) :test #'string=)
              :to-be-truthy))))
