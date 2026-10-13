#lang racket/base

(require rackunit
         racket/string
         server-sent-events)

;; Read lines up to and including the frame-terminating blank line.
(define (read-frame rin)
  (let loop ([acc '()])
    (define line (read-line rin))
    (if (eof-object? line)
        (reverse (cons line acc))
        (let ([acc (cons line acc)])
          (if (equal? line "")
              (reverse acc)
              (loop acc))))))

(test-case "fanout delivers exactly one frame per notify"
  (define h (make-hub))
  (define-values (rin rout) (make-pipe))
  (hub-attach! h rout)
  (check-equal? (hub-clients h) (list rout))
  (hub-attach! h rout)                         ; idempotent
  (check-equal? (hub-clients h) (list rout))
  (hub-notify! h "edition" "{\"date\":\"2026-10-13\"}")
  (check-equal? (read-frame rin)
                (list "event: edition" "data: {\"date\":\"2026-10-13\"}" ""))
  ;; no second delivery path: nothing else arrives
  (check-false (sync/timeout 0.2 rin))
  (hub-detach! h rout)
  (check-equal? (hub-clients h) '()))

(test-case "multi-client fanout"
  (define h (make-hub))
  (define-values (rin1 rout1) (make-pipe))
  (define-values (rin2 rout2) (make-pipe))
  (hub-attach! h rout1)
  (hub-attach! h rout2)
  (hub-notify! h "e" "v")
  (check-equal? (read-frame rin1) (list "event: e" "data: v" ""))
  (check-equal? (read-frame rin2) (list "event: e" "data: v" "")))

(test-case "hub-stream: retry hint, replay, heartbeat, detach on closed port"
  (define h (make-hub))
  (hub-notify! h "edition" "v0")               ; no clients yet: replay only
  (define-values (rin rout) (make-pipe))
  (define t (thread (λ () (hub-stream h rout #:retry 4000 #:heartbeat 0.05))))
  (check-equal? (read-line rin) "retry: 4000")
  (check-equal? (read-line rin) "")                      ; hint terminator
  (check-equal? (read-frame rin)
                (list "event: edition" "data: v0" ""))   ; replayed
  (check-equal? (read-frame rin) (list ": ping" ""))     ; heartbeat
  (check-equal? (read-frame rin) (list ": ping" ""))
  (close-output-port rout)                     ; framework abandoned the port
  (sync/timeout 2 t)
  (check-true (thread-dead? t))
  (check-equal? (hub-clients h) '()))

(test-case "write failure detaches the client"
  (define h (make-hub))
  (define broken
    (make-output-port
     'broken always-evt
     (λ (s start end nonblock? breakable?)
       (raise (exn:fail "broken pipe" (current-continuation-marks))))
     void))
  (hub-attach! h broken)
  (hub-notify! h "e" "v")                      ; write raises → silent detach
  (check-equal? (hub-clients h) '()))

(test-case "notify after replay-ready hub reaches stream clients"
  (define h (make-hub))
  (define-values (rin rout) (make-pipe))
  (define t (thread (λ () (hub-stream h rout))))
  (read-line rin)                              ; retry line
  (read-line rin)                              ; hint terminator
  (hub-notify! h "edition" "{\"date\":\"d1\"}")
  (check-equal? (read-frame rin)
                (list "event: edition" "data: {\"date\":\"d1\"}" ""))
  (close-input-port rin)
  (sync/timeout 2 t))

(test-case "watch notifies on changes only, survives thunk errors"
  (define h (make-hub))
  (define-values (rin rout) (make-pipe))
  (hub-attach! h rout)
  (define state (box 0))
  (define (thunk)
    (define v (unbox state))
    (cond [(= v 0) #f]
          [(= v 1) (raise (exn:fail "boom" (current-continuation-marks)))]
          [else (format "v~a" v)]))
  (define t (hub-watch! h 0.05 "upd" thunk))
  (sleep 0.12)
  (set-box! state 1)                           ; error round: logged, ignored
  (sleep 0.12)
  (set-box! state 2)
  (sleep 0.12)
  (check-equal? (read-frame rin) (list "event: upd" "data: v2" ""))
  (check-false (sync/timeout 0.2 rin))         ; no baseline frame, no dup
  (kill-thread t))

(test-case "watch baseline suppresses the initial value"
  (define h (make-hub))
  (define-values (rin rout) (make-pipe))
  (hub-attach! h rout)
  (define t (hub-watch! h 0.05 "upd" (λ () "already-there")))
  (sleep 0.15)
  (check-false (sync/timeout 0.2 rin))         ; baseline, not a change
  (kill-thread t))
