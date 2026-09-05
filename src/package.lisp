
#-sbcl
(error "cl-cmatrix currently requires SBCL (it relies on cl-tty-kit, which is
itself SBCL-only). See docs/src/reference/compatibility.md for details.")

(defpackage #:cl-cmatrix
  (:use #:cl)
  (:import-from #:cl-concurrent-kit
                #:with-executor
                #:executor-map)
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
   #:cl-cmatrix-error
   #:invalid-dimensions
   #:invalid-dimensions-width
   #:invalid-dimensions-height
   #:invalid-glyphs
   #:invalid-glyphs-glyphs
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
   #:list-color-schemes
   #:color-scheme-p
   #:color-choice-p
   #:list-charsets
   #:charset-p
   #:charset-glyphs
   #:+default-fps+
   #:+default-update-delay+
   #:+default-workers+
   #:matrix-state
   #:make-matrix-state
   #:matrix-state-width
   #:matrix-state-height
   #:matrix-state-tick
   #:matrix-advance
   #:matrix-resize
   #:render-context
   #:make-render-context
   #:matrix-draw
   #:matrix-cell-style
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
