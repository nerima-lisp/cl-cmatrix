(defpackage #:cl-cmatrix/test
  (:use #:cl #:cl-cmatrix)
  (:import-from #:cl-cmatrix
                #:+min-trail-length+
                #:+max-update-threshold+
                #:+async-count-cycle+
                #:+default-glyphs+
                #:+classic-glyphs+
                #:+katakana-glyphs+
                #:+binary-glyphs+
                #:random-glyph
                #:color-scheme-head-rgb
                #:color-scheme-bright-rgb
                #:color-scheme-dark-rgb
                #:column
                #:column-p
                #:column-cells
                #:column-heads
                #:column-length
                #:column-spaces
                #:column-update
                #:column-cell-at
                #:column-head-p
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
                #:render-context-style-cache
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
                #:quit-key-event-p
                #:poll-quit-events
                #:poll-quit-events-cps)
  (:import-from #:cl-concurrent-kit
                #:with-executor)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it #:expect #:signals #:run-all
                #:it-each #:before-each
                #:with-soft-assertions
                #:with-continuation-result
                #:run-mutations #:assert-mutation-score
                #:it-isolated
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
