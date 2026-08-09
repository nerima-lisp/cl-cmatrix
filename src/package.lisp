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
  ;; THE v1.0.0 PUBLIC API. Every symbol below is a compatibility promise:
  ;; removing one, or changing what it accepts or returns, requires a major
  ;; version bump. Everything else this system defines is internal and may
  ;; change in any release, which is why COLUMN, RUN-STATE, the tuning
  ;; constants and the raw glyph vectors are deliberately absent -- they are
  ;; the representations most likely to move, and freezing a representation
  ;; freezes the implementation behind it. A caller that genuinely needs one
  ;; can still reach it through CL-CMATRIX::, and by writing those two colons
  ;; states that it is holding something unsupported.
  ;;
  ;; The line is drawn at the ENGINE: build a state, advance it, reflow it,
  ;; draw it -- enough to embed the animation in a caller's own loop -- but
  ;; not at the state's internals. Glyph sets and color schemes are reached
  ;; by NAME through the registries rather than by their constants, so the
  ;; vectors behind them stay free to change.
  (:export
   ;; Conditions -- the complete set, since a caller cannot handle what it
   ;; cannot name. All but one are reachable from MAKE-MATRIX-STATE or
   ;; RUN-MATRIX with bad arguments; UNKNOWN-CHARSET is the exception, and is
   ;; signalled only by CHARSET-GLYPHS. Neither constructor resolves a charset
   ;; name -- both take :GLYPHS as a vector already -- so nothing they are
   ;; handed can raise it. It is exported all the same, because CHARSET-GLYPHS
   ;; is public and a caller cannot handle what it cannot name.
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
   ;; Registries: what may be passed as :COLOR and :GLYPHS, asked for by name
   ;; instead of by reaching for +CLASSIC-GLYPHS+ and friends directly.
   #:list-color-schemes
   #:color-scheme-p
   #:color-choice-p
   #:list-charsets
   #:charset-p
   #:charset-glyphs
   ;; The defaults RUN-MATRIX itself uses, so a caller can reproduce or
   ;; adjust them without hard-coding the numbers.
   #:+default-fps+
   #:+default-update-delay+
   #:+default-workers+
   ;; The animation engine.
   #:matrix-state
   #:make-matrix-state
   #:matrix-state-width
   #:matrix-state-height
   #:matrix-state-tick
   #:matrix-advance
   #:matrix-resize
   ;; Drawing a state onto a CL-TTY-KIT screen.
   #:render-context
   #:make-render-context
   #:matrix-draw
   #:matrix-cell-style
   ;; The whole animation, terminal session and all.
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
