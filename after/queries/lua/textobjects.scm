; extends

; Treat named table fields like assignments. This makes assignment textobjects
; work for both `value = expression` and `{ key = value }` forms.
(field
  name: (_) @assignment.lhs
  value: (_) @assignment.inner @assignment.rhs) @assignment.outer
