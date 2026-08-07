(in-package #:cl-cmatrix)

(defstruct (render-context (:constructor make-render-context))
  "Renderer-local memoization, separate from animation state.

The style cache depends only on drawing configuration and trail length. It is
therefore owned by the render context instead of being copied through every
MATRIX-STATE transition."
  (style-cache (make-hash-table :test #'equal) :type hash-table))
