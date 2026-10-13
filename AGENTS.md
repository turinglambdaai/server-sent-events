# AGENTS.md

## What this is

`sse` — Server-Sent Events for Racket: the WHATWG wire format plus a
fan-out hub. Single-collection package (`sse` = collection = package
name). Family protocol-library line (websocket, isotp, crc, pcap,
...). Deliberately NOT a framework: no routing, no HTTP server, no
serialization policy.

## Layout

- `encode.rkt` — WHATWG frame encoding, pure string in/out
- `hub.rkt` — fan-out hub: attach/detach, notify, replay, heartbeats,
  change watching
- `main.rkt` — re-exports everything
- `tests/` — require the `sse` collection, not relative paths
- `scribblings/` — Scribble docs

## Invariants

- Delivery is single-path: `hub-notify!` writes synchronously to every
  attached client and there is no second wake-up that re-sends the
  frame. One notify = one frame per client. (The pitboard ancestor had
  two delivery paths and clients received duplicates.)
- `hub-watch!`'s first thunk call establishes the baseline and must
  not notify.
- Thunk errors and dead-client write errors are absorbed (log/detach),
  never propagated into the polling or streaming loops.
- The payload of `hub-watch!`/`hub-notify!` is a plain string; this is
  what keeps deps at `base` alone. Do not add a json dependency here.

## Conventions

- Code comments in English.
- Timing-sensitive tests use fractional-second heartbeats/polls and a
  final "nothing else arrived" `sync/timeout` check; keep the margins
  generous enough for slow CI.

## Quality gates (before any release)

1. `raco test tests` — all green
2. `raco setup --check-pkg-deps -l server-sent-events` — zero violations
3. `raco setup -l server-sent-events` — docs build clean, zero undefined tags
