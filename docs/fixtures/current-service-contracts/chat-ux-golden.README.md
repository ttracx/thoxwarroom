# ThoxOS chat UX golden reference

[`chat-ux-golden.html`](chat-ux-golden.html) is the design reference supplied
for the shared ThoxOS chat experience. Open it directly in
a browser to inspect the six target interactions: Markdown/code/math, a line
chart, a Mermaid flow, artifact preview/source/fullscreen, editable live code,
and a Digital Human turn paused at an approval boundary.

This file is a visual and interaction fixture, not a production runtime. It
loads public CDN copies of its demo libraries and therefore is not suitable for
private prompts, offline claims, native packaging, or regulated data. Product
hosts use the vendored, network-disabled `@thox/chat-render` bundle owned by
`ttracx/THOX_MeshStack`; its `connect-src 'none'` boundary, opaque artifact
preview, and receipted Sandpack runtime remain authoritative.

The repository copy removes `defer` from the two KaTeX scripts so direct-file
execution cannot race the inline renderer. No visible design or wire fixture
changed.

Runnable reference SHA-256:

```text
86bdce5a7206ac2ce0b9191db4bf412508a3d5bb3c43aeb180fc267e33a674cd
```

Original supplied attachment SHA-256:

```text
8288e9a87674b5a73d34cbed3538bbf911984c3dcf36fda138c5c88300fc8f12
```
