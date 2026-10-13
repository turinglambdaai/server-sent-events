#lang scribble/manual

@(require (for-label server-sent-events
                     racket/base
                     web-server/http)
          scribble/example)

@title{server-sent-events: Server-Sent Events}
@defmodule[server-sent-events]

This package implements @hyperlink["https://html.spec.whatwg.org/multipage/server-sent-events.html#server-sent-events"]{Server-Sent Events}
on Racket ports: the WHATWG wire format on the encoding side, and a
small fan-out hub on the serving side. It is a protocol library, not a
framework — the sibling @tt{websocket} package covers the bidirectional
case. Event routing, serialization (JSON or otherwise), and the HTTP
server all stay with the caller.

@section{Frames}

@defproc[(sse-encode [event sse-event-name?] [data string?] [id (or/c sse-line? #f) #f]) string?]

Encodes one event frame. @racket[data] may contain line breaks; they
are split on CRLF, CR, or LF and re-emitted as one @tt{data:} line per
piece, so multi-line payloads survive the trip. The optional @racket[id]
sets the client's last-event ID.

@examples[#:eval (make-base-eval) #:label ""
  (require server-sent-events)
  (sse-encode "edition" "{\"date\":\"2026-10-13\"}")
  (sse-encode "log" "line one\nline two")]

@defproc[(sse-comment [text sse-line?]) string?]

Encodes a comment frame — the conventional heartbeat, e.g.
@racket[(sse-comment "ping")].

@defproc[(sse-line? [v any/c]) boolean?]

@defproc[(sse-event-name? [v any/c]) boolean?]

@racket[sse-line?] accepts non-empty single-line strings.
@racket[sse-event-name?] additionally excludes colons, which the wire
parser reads as field separators. Both are flat contracts; violations
raise before anything reaches the wire.

@section{The hub}

A @racket[hub] fans frames out to attached output ports, replays the
most recent frame to new subscribers, and keeps connections alive with
comment heartbeats.

@defproc[(make-hub) hub?]

@defproc[(hub? [v any/c]) boolean?]

@defproc[(hub-clients [h hub?]) (listof output-port?)]

Currently attached clients, most recently attached last.

@defproc[(hub-attach! [h hub?] [out output-port?]) void?]

@defproc[(hub-detach! [h hub?] [out output-port?]) void?]

Attaching is idempotent. Detaching closes the port. When a write to a
client fails (the usual signal of a disconnected client), the hub
detaches it silently.

@defproc[(hub-notify! [h hub?] [event sse-event-name?] [data string?] [id (or/c sse-line? #f) #f]) void?]

Broadcasts one frame to every attached client, synchronously, and
remembers it as the frame to replay. Delivery is deliberately
single-path: one notify produces exactly one frame per client.

@defproc[(hub-stream [h hub?] [out output-port?]
                     [#:retry retry (and/c exact-integer? positive?) 5000]
                     [#:heartbeat heartbeat (and/c real? positive?) 15])
         void?]

The long-lived response body. Attaches @racket[out], sends the retry
hint, replays the most recent frame if there is one, then emits a
@racket[(sse-comment "ping")] heartbeat every @racket[heartbeat]
seconds until the client goes away — a dead port makes the next write
raise, which detaches the client and ends the call. Run it in the
servlet's response thread:

@racketblock[
(define (events-h req)
  (response/output
   (λ (out) (hub-stream hub out))
   #:mime-type #"text/event-stream"
   #:headers
   (list (header #"Cache-Control" #"no-cache")
         (header #"X-Accel-Buffering" #"no"))))]

@defproc[(hub-watch! [h hub?] [poll-seconds (and/c real? positive?)]
                     [event sse-event-name?] [thunk (-> (or/c string? #f))])
         thread?]

Starts a daemon-ish polling thread: every @racket[poll-seconds] it
calls @racket[thunk]; a non-@racket[#f] result different (by
@racket[equal?]) from the previous one is broadcast as
@racket[event]. The first call establishes the baseline and does not
notify. Thunk errors are logged under the @racketid[sse] logger and
treated as "nothing new". The payload is a plain string — serializing
domain state (e.g. @racket[jsexpr->string]) is the caller's job, which
is what keeps this package's dependency set at @racket[base] alone.

@section{Semantics and limits}

@itemlist[
@item{Replay is single-slot: the hub remembers only the most recent
frame. Hubs broadcasting several independent event streams replay just
the latest — give each stream its own hub.}

@item{Frames are written whole (Racket port operations do not
interleave mid-call), but ordering between a notify from one thread
and a heartbeat from the stream thread is not coordinated. Clients see
both, in either order; heartbeats are comments, so this is invisible
to the event stream semantics.}

@item{The hub assumes the caller owns connection setup — the response
headers, buffering proxies (@tt{X-Accel-Buffering}), and reconnect
policy are all outside its scope.}]
