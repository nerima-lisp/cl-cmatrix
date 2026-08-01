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
itself SBCL-only). See the \"Compatibility\" section of the README for
details.")

(defpackage #:cl-cmatrix
  (:use #:cl)
  ;; Sibling packages are never :USEd (CODING_STANDARD.md "`:use` は `#:cl`
  ;; だけ"); every CL-TTY-KIT symbol this system calls is imported by name so
  ;; its origin stays visible at every call site's package qualification.
  (:import-from #:cl-tty-kit
                #:make-style
                #:style-fg
                #:rgb-to-256
                #:blend-colors
                #:screen-put-cell
                #:make-renderer
                #:renderer-screen
                #:renderer-width
                #:renderer-height
                #:renderer-render
                #:renderer-clear
                #:renderer-resize
                #:tick-loop-run-realtime
                #:with-terminal-session
                #:terminal-size)
  (:export
   ;; conditions
   #:cl-cmatrix-error
   #:invalid-dimensions
   #:invalid-dimensions-width
   #:invalid-dimensions-height
   #:invalid-speed
   #:invalid-speed-speed
   #:unknown-color-scheme
   #:unknown-color-scheme-name
   ;; glyphs
   #:+default-glyphs+
   #:random-glyph
   ;; color schemes
   #:list-color-schemes
   #:color-scheme-p
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
   #:matrix-state-tick
   #:matrix-advance
   #:matrix-resize
   ;; rendering
   #:matrix-cell-style
   #:matrix-draw
   ;; real-time driver loop
   #:run-state
   #:make-run-state
   #:run-state-matrix
   #:run-state-renderer
   #:run-state-quitp
   #:run-state-input-stream
   #:run-state-advance
   #:run-state-render
   #:quit-key-character-p
   #:poll-quit-key
   #:run-matrix))

(defpackage #:cl-cmatrix/cli
  (:documentation "The `cl-cmatrix` command-line front end over CL-CMATRIX.")
  (:use #:cl)
  (:import-from #:cl-cmatrix
                #:run-matrix
                #:list-color-schemes)
  (:import-from #:cl-cli
                #:make-app
                #:make-option
                #:run-app
                #:option-value
                #:current-process-argv)
  (:export
   #:make-cmatrix-app
   #:main
   #:image-entry-point))
