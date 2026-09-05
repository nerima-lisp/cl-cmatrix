
(in-package #:cl-cmatrix/test)


(defun %docs-directory ()
  "Return the documentation source tree resolved through ASDF."
  (asdf:system-relative-pathname "cl-cmatrix" "docs/src/"))

(defun %docs-pathnames ()
  "Every .md file under %DOCS-DIRECTORY, at any depth, in a stable order."
  (sort (directory (merge-pathnames
                    (make-pathname :directory '(:relative :wild-inferiors)
                                   :name :wild :type "md")
                    (%docs-directory)))
        #'string< :key #'namestring))

(defun %docs-read-file (pathname)
  "Read PATHNAME as UTF-8 text."
  (with-open-file (stream pathname :external-format :utf-8)
    (let ((text (make-string (file-length stream))))
      (subseq text 0 (read-sequence text stream)))))

(defvar *docs-corpus* nil
  "Memoized (RELATIVE-NAME TEXT) entries.")

(defun %docs-corpus ()
  "The documentation corpus as (RELATIVE-NAME TEXT) entries."
  (or *docs-corpus*
      (setf *docs-corpus*
            (mapcar (lambda (pathname)
                      (list (enough-namestring pathname (%docs-directory))
                            (%docs-read-file pathname)))
                    (%docs-pathnames)))))


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
  "Return public qualified references in TEXT. Double-colon references are
skipped because they name internal symbols."
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


(defun %docs-heading-name (line)
  "Return LINE's code span when it is an ATX heading containing one span."
  (let ((trimmed (%docs-trim line)))
    (when (and (plusp (length trimmed)) (char= (char trimmed 0) #\#))
      (%docs-sole-span (%docs-trim (string-left-trim "#" trimmed))))))

(defun %docs-anchor-link-names (line)
  "Return names in LINE's same-page code-span links."
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
  "True when NAME has the lowercase Lisp symbol shape accepted by docs checks."
  (flet ((lowercase-letter-p (character)
           (and (alpha-char-p character) (lower-case-p character))))
    (and (plusp (length name))
         (or (lowercase-letter-p (char name 0)) (char= (char name 0) #\+))
         (every (lambda (character)
                  (or (lowercase-letter-p character)
                      (digit-char-p character)
                      (find character "-+*")))
                name))))


(defun %docs-option-token-name (token)
  "Return the option name before #\\= for a long option; leave other tokens
unchanged."
  (if (%docs-prefix-at-p token 0 "--")
      (let ((equals (position #\= token)))
        (if equals (subseq token 0 equals) token))
      token))

(defun %docs-option-token-p (token)
  "True when TOKEN has a supported long or short option shape."
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


(describe "docs/src: the corpus these checks read"
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
    (with-soft-assertions
      (expect (%docs-invocation-tokens "cl-cmatrix --bogus=1")
              :to-equal '("--bogus=1"))
      (expect (%docs-canonical-option-name "--bogus=1") :to-equal "bogus")
      (expect (member (%docs-canonical-option-name "--bogus=1")
                      (%docs-recognized-option-names) :test #'string=)
              :to-be-falsy)))

  (it "still ignores an attached spelling merely mentioned in prose"
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
    (expect (%docs-option-token-p "-g=binary") :to-be-falsy)))

(describe "docs/src: every symbol the docs present as public is exported"
  (it "every cl-cmatrix:NAME and cl-cmatrix/cli:NAME reference names an external symbol"
    (expect (%docs-report
             (loop for (label name package-name) in (%docs-qualified-candidates)
                   unless (%docs-external-symbol-p name (list package-name))
                     collect (list label (format nil "~(~A~):~A" package-name name))))
            :to-equal '()))

  (it "every name given its own heading or same-page anchor link is external"
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
    (with-soft-assertions
      (expect (plusp (length (%docs-recognized-option-names))) :to-be-truthy)
      (expect (member "charset" (%docs-recognized-option-names) :test #'string=)
              :to-be-truthy)
      (expect (member "help" (%docs-recognized-option-names) :test #'string=)
              :to-be-truthy))))
