# sse

[![CI](https://github.com/turinglambdaai/sse/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/sse/actions/workflows/ci.yml)

Server-Sent Events for Racket: the WHATWG wire format plus a small
fan-out hub. A protocol library, not a framework — event routing,
serialization, and the HTTP server stay with the caller.

## Install

```
raco pkg install sse
```

## Use

Serve an event stream from any `response/output`-shaped server:

```racket
(require sse
         web-server/http)

(define hub (make-hub))

;; broadcast to everyone (payload is a plain string — bring your own JSON)
(hub-notify! hub "edition" "{\"date\":\"2026-10-13\"}")

;; long-lived response body: retry hint, replay, 15s heartbeats
(define (events-h req)
  (response/output
   (λ (out) (hub-stream hub out))
   #:mime-type #"text/event-stream"
   #:headers
   (list (header #"Cache-Control" #"no-cache")
         (header #"X-Accel-Buffering" #"no"))))

;; poll a source of truth; changes are broadcast as "edition" events
(hub-watch! hub 5 "edition"
            (λ () (and (data-changed?) (jsexpr->string (hasheq 'date (today))))))

;; encode frames by hand when you don't need the hub
(sse-encode "msg" "line one\nline two")
;; => "event: msg\ndata: line one\ndata: line two\n\n"
```

What you get:

- WHATWG-compliant frame encoding: multi-line data split across
  `data:` lines, optional event IDs, contract-checked event names
- Fan-out hub with single-slot replay for reconnecting clients
- Comment heartbeats and liveness detection — dead clients are
  detached silently
- A change-watching helper with baseline suppression and error
  resilience
- Zero dependencies beyond `base`

Limitations: replay is single-slot (one hub per event stream);
connection setup and reconnect policy are the caller's job.

## Development

```
raco pkg install --auto --link .
raco test tests
raco setup --check-pkg-deps -l sse
```

## License

[MIT](LICENSE)
