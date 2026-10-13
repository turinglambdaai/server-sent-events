#lang racket/base

(require rackunit
         sse)

(test-case "single-line frame (wire-compat shape)"
  (check-equal? (sse-encode "edition" "{\"a\":1}")
                "event: edition\ndata: {\"a\":1}\n\n")
  (check-true (regexp-match? #rx"\n\n$" (sse-encode "ping" "x"))))

(test-case "multi-line data is split into data: lines"
  (check-equal? (sse-encode "msg" "line1\nline2")
                "event: msg\ndata: line1\ndata: line2\n\n")
  (check-equal? (sse-encode "msg" "a\r\nb\rc")
                "event: msg\ndata: a\ndata: b\ndata: c\n\n")
  (check-equal? (sse-encode "msg" "")
                "event: msg\ndata: \n\n"))

(test-case "optional id line"
  (check-equal? (sse-encode "e" "d" "42")
                "event: e\nid: 42\ndata: d\n\n"))

(test-case "comments"
  (check-equal? (sse-comment "ping") ": ping\n\n"))

(test-case "predicates"
  (check-true (sse-event-name? "edition"))
  (check-false (sse-event-name? "e:v"))      ; colon reads as separator
  (check-false (sse-event-name? "a\nb"))
  (check-false (sse-event-name? ""))
  (check-true (sse-line? "x:y"))             ; colon is fine outside event names
  (check-false (sse-line? "a\rb")))

(test-case "bad event names fail at the contract, not on the wire"
  (check-exn exn:fail:contract? (λ () (sse-encode "bad:name" "d")))
  (check-exn exn:fail:contract? (λ () (sse-encode "a\nb" "d"))))
