;;;; src/package.lisp
;;;;
;;;; Two packages, both defined here per PACKAGE_STANDARD.md: CL-CMATRIX is
;;;; the animation engine (pure state construction/advance/resize plus the
;;;; CL-TTY-KIT rendering and the real-time driver loop) and CL-CMATRIX/CLI is
;;;; the thin command-line front end over it, mirroring cl-cowsay's split so
;;;; `(asdf:load-system "cl-cmatrix")` stays usable as a library with no
;;;; CL-CLI-flavoured argv parsing along for the ride.

#-sbcl
(error "cl-cmatrix currently requires SBCL (it relies on cl-tty-kit, which is
itself SBCL-only). See docs/src/reference/compatibility.md for details.")

(defpackage #:cl-cmatrix
  (:use #:cl)
  (:import-from #:cl-concurrent-kit
                #:with-executor
                #:executor-map)
  ;; Sibling packages are never :USEd (CODING_STANDARD.md "`:use` は `#:cl`
  ;; だけ"); every CL-TTY-KIT symbol this system calls is imported by name so
  ;; its origin stays visible at every call site's package qualification.
  (:import-from #:cl-tty-kit
                #:make-style
                #:style-fg
                #:rgb-to-256
                #:blend-colors
                #:screen-put-cell
                #:with-screen-batch
                #:make-renderer
                #:renderer-screen
                #:renderer-width
                #:renderer-height
                #:renderer-render
                #:renderer-clear
                #:renderer-resize
                #:tick-loop-run-realtime
                #:with-terminal-session
                #:terminal-size
                #:make-stream-input-poller
                #:key-event
                #:key-event-type
                #:key-event-code
                #:key-event-kind)
  (:export
   ;; conditions
   #:cl-cmatrix-error
   #:invalid-dimensions
   #:invalid-dimensions-width
   #:invalid-dimensions-height
   #:invalid-speed
   #:invalid-speed-speed
   #:invalid-fps
   #:invalid-fps-fps
   #:invalid-update-delay
   #:invalid-update-delay-delay
   #:unknown-color-scheme
   #:unknown-color-scheme-name
   #:unknown-charset
   #:unknown-charset-name
   ;; glyphs
   #:+default-glyphs+
   #:+katakana-glyphs+
   #:+binary-glyphs+
   #:+lambda-glyphs+
   #:random-glyph
   #:list-charsets
   #:charset-p
   #:charset-glyphs
   ;; color schemes
   #:list-color-schemes
   #:color-scheme-p
   #:color-choice-p
   #:color-scheme-head-rgb
   #:color-scheme-bright-rgb
   #:color-scheme-dark-rgb
   ;; columns
   #:column
   #:column-head
   #:column-length
   #:column-interval
   #:column-counter
   #:column-glyphs
   #:column-glyph-at-row
   #:column-row-lit-p
   #:old-style-column
   #:old-style-column-p
   #:old-style-column-interval
   #:old-style-column-counter
   #:old-style-column-glyphs
   #:old-style-column-glyph-bold-p
   #:old-style-column-spaces
   #:old-style-column-glyph-at-row
   ;; matrix state
   #:matrix-state
   #:make-matrix-state
   #:matrix-state-width
   #:matrix-state-height
   #:matrix-state-columns
   #:matrix-state-random-state
   #:matrix-state-speed
   #:matrix-state-color
   #:matrix-state-glyphs
   #:matrix-state-bold
   #:matrix-state-partial-bold-p
   #:matrix-state-no-bold-p
   #:matrix-state-old-style-p
   #:matrix-state-asyncp
   #:matrix-state-random-bold-p
   #:matrix-state-change-glyphs-p
   #:matrix-state-tick
   #:matrix-advance
   #:matrix-resize
   ;; rendering
   #:matrix-cell-style
   #:render-context
   #:make-render-context
   #:render-context-style-cache
   #:matrix-draw
   ;; real-time driver loop
   #:+default-fps+
   #:+default-update-delay+
   #:+default-workers+
   #:run-state
   #:make-run-state
   #:run-state-matrix
   #:run-state-renderer
   #:run-state-quitp
   #:run-state-input-poller
   #:run-state-workers
                #:run-state-executor
                #:run-state-render-context
   #:run-state-lockp
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
   #:poll-quit-events-cps
   #:run-matrix))

(defpackage #:cl-cmatrix/cli
  (:documentation "The `cl-cmatrix` command-line front end over CL-CMATRIX.")
  (:use #:cl)
  (:import-from #:cl-cmatrix
                #:run-matrix
                #:list-color-schemes
                #:list-charsets
                #:charset-glyphs
                #:+default-fps+
                #:+default-update-delay+
                #:+default-workers+)
  (:import-from #:cl-cli
                #:make-app
                #:make-option
                #:run-app
                #:option-value
                #:option-value-source
                #:current-process-argv)
  (:import-from #:host-kit
                #:quit
                #:getcwd
                #:with-environment-variables)
  (:import-from #:cl-tty-kit
                #:stream-fd)
  (:export
   #:make-cmatrix-app
   #:main
   #:image-entry-point))
