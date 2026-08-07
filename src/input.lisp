(in-package #:cl-cmatrix)

(defun %quit-character-p (code)
  (and (characterp code)
       (or (char= code #\q)
           (char= code #\Q)
           (= (char-code code) 3))))

(defun quit-key-event-p (event)
  "Return true when EVENT is a pressed q, Q, Ctrl-C, or Escape key event."
  (and (typep event 'key-event)
       (eq (key-event-kind event) :press)
       (case (key-event-type event)
         (:character (%quit-character-p (key-event-code event)))
         (:special (eq (key-event-code event) :escape))
         (otherwise nil))))

(defun poll-quit-events-cps (events on-quit on-continue)
  "Dispatch EVENTS to ON-QUIT when a quit event is present, otherwise continue.

The callback form keeps event polling composable with CL-WEAVE's continuation
helpers without wrapping the underlying CL-TTY-KIT event objects."
  (let ((event (find-if #'quit-key-event-p events)))
    (if event
        (funcall on-quit event)
        (funcall on-continue))))

(defun poll-quit-events (events)
  "Return true when EVENTS contains a pressed quit key event."
  (poll-quit-events-cps events (constantly t) (constantly nil)))
