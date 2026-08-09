;;;; t/package.lisp
(defpackage #:cl-cmatrix/test
  (:use #:cl #:cl-cmatrix)
  ;; The suite tests more than the v1.0.0 public API, which is the point: a
  ;; representation that callers cannot reach still has to be correct, and the
  ;; specs that pin COLUMN's cell vocabulary or RUN-STATE's tick counter are
  ;; exactly the ones that caught the upstream-conformance rewrite's mistakes.
  ;;
  ;; Naming those symbols here rather than qualifying each use with
  ;; CL-CMATRIX:: keeps the spec bodies reading as the behaviour they describe.
  ;; :IMPORT-FROM works on an internal symbol as readily as an exported one --
  ;; it is FIND-SYMBOL plus IMPORT, and neither consults external-ness -- so
  ;; shrinking the export list did not cost the suite a single edit.
  ;;
  ;; This list IS the answer to "what does the suite depend on beyond the
  ;; public API": if a symbol here is ever promoted to :EXPORT it should be
  ;; deleted from this list, and if the suite stops needing one it should be
  ;; deleted too, so the two never quietly overlap.
  (:import-from #:cl-cmatrix
                ;; tuning constants
                #:+min-trail-length+
                #:+max-update-threshold+
                #:+async-count-cycle+
                ;; glyph vectors, behind CHARSET-GLYPHS in the public API
                #:+default-glyphs+
                #:+classic-glyphs+
                #:+katakana-glyphs+
                #:+binary-glyphs+
                #:random-glyph
                ;; color scheme data, behind MATRIX-CELL-STYLE in the public API
                #:color-scheme-head-rgb
                #:color-scheme-bright-rgb
                #:color-scheme-dark-rgb
                ;; COLUMN, the per-stream representation
                #:column
                #:column-p
                #:column-cells
                #:column-heads
                #:column-length
                #:column-spaces
                #:column-update
                #:column-cell-at
                #:column-head-p
                ;; MATRIX-STATE's internals, beyond the width/height/tick trio
                #:matrix-state-column-count
                #:matrix-state-columns
                #:matrix-state-random-state
                #:matrix-state-color
                #:matrix-state-glyphs
                #:matrix-state-bold
                #:matrix-state-partial-bold-p
                #:matrix-state-no-bold-p
                #:matrix-state-old-style-p
                #:matrix-state-lambda-p
                #:matrix-state-asyncp
                #:matrix-state-async-count
                #:matrix-state-random-bold-p
                #:matrix-state-change-glyphs-p
                ;; the render context's memoization slot
                #:render-context-style-cache
                ;; RUN-STATE, the driver loop's mutable state
                #:run-state
                #:make-run-state
                #:run-state-matrix
                #:run-state-renderer
                #:run-state-quitp
                #:run-state-lockp
                #:run-state-input-poller
                #:run-state-workers
                #:run-state-executor
                #:run-state-render-context
                #:run-state-screensaverp
                #:run-state-pausedp
                #:run-state-message
                #:run-state-poll
                #:run-state-poll-cps
                #:run-state-advance
                #:run-state-render
                #:run-state-apply-key-event
                ;; input polling
                #:quit-key-event-p
                #:poll-quit-events
                #:poll-quit-events-cps)
  (:import-from #:cl-concurrent-kit
                #:with-executor)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                ;; Registration and assertions
                #:it #:expect #:signals #:run-all
                ;; Table tests and fixtures
                #:it-each #:before-each
                ;; Soft (all-failures-collected) assertions
                #:with-soft-assertions
                ;; CPS continuation helpers
                #:with-continuation-result
                ;; Mutation testing
                #:run-mutations #:assert-mutation-score
                ;; Subprocess isolation, for code that really exits the process
                #:it-isolated
                ;; Property-based testing: generated cases plus automatic shrinking on
                ;; failure, for invariants that must hold across a whole input space
                ;; rather than only the hand-picked examples the other IT cases cover.
                #:it-property #:gen-integer #:gen-member #:gen-state-machine)
  (:import-from #:cl-cmatrix/cli
                #:make-cmatrix-app
                #:main
                #:image-entry-point)
  (:import-from #:cl-cli
                #:parse-argv
                #:run-app
                #:option-value
                #:cli-invalid-option-value)
  (:import-from #:cl-tty-kit
                #:rgb-to-256
                #:blend-colors
                #:color-luminance
                #:make-screen
                #:screen-cell
                #:cell-char
                #:cell-style
                #:make-renderer
                #:renderer-width
                #:renderer-height
                #:make-key-event
                #:make-stream-input-poller
                #:key-event-code)
  (:export #:run-tests))

(in-package #:cl-cmatrix/test)

(defun run-tests ()
  "Run every registered spec, signalling on any failure so ASDF's TEST-OP
fails."
  (unless (run-all :reporter :spec :timeout-ms 20000)
    (error "cl-cmatrix test suite failed"))
  (format t "~&cl-cmatrix/test: successful completion with 0 failures~%")
  t)
