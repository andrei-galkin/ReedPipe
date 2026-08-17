# ReedPipe agent guidance

## Swift style

All Swift changes in this repository must follow
[`Documentation/Style/Swift.md`](Documentation/Style/Swift.md).

The guide applies to new and modified code. Do not perform unrelated,
repository-wide restyling while completing a focused change. When touching
legacy code, preserve surrounding behavior and comments, and bring the edited
area into compliance when that does not create unrelated churn.

Project requirements and task-specific instructions take precedence if they
conflict with the general style guide. In particular:

- The browser frontend must remain implemented in Swift and WebAssembly.
- Keep the shared `Core` target compatible with the native proxy and Embedded
  Swift WebAssembly where possible.
- Foundation must not be linked through `Core` or `Frontend`.
- Keep browser-only JavaScript interop conformances in `Frontend`, not `Core`.

## Upstream provenance

The Swift guide is vendored from
[`tayloraswift/dollup`](https://github.com/tayloraswift/dollup/blob/master/Agent/Swift.md)
at commit `288c5cd5f6c872e49bcabaa98f497fbd64fee949`.

It is distributed under Apache License 2.0. Its license and notice are retained
in [`Documentation/Style/DOLLUP-LICENSE`](Documentation/Style/DOLLUP-LICENSE)
and [`Documentation/Style/DOLLUP-NOTICE`](Documentation/Style/DOLLUP-NOTICE).
