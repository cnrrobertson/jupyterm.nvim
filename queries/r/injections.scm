; -----------------------------------------------------------------------------
; Syntax highlighting for jupyterm blocks
; -----------------------------------------------------------------------------
(
  (string
    (string_content) @injection.content)
  (#match? @injection.content "(In \\[[0-9]+\\]|Out \\[[0-9]+\\]):.*")
  (#set! injection.language "r")
)
