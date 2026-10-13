#lang racket/base

;; A tiny fan-out hub: broadcast frames to attached output ports, replay
;; the most recent frame to new subscribers, keep connections alive with
;; comment heartbeats, and watch a thunk for changes.  Delivery is
;; synchronous inside hub-notify!; hub-stream only adds the retry hint,
;; the replay, heartbeats, and liveness detection.  There is deliberately
;; no second delivery path: every notify produces exactly one frame per
;; attached client.

(require racket/contract
         racket/list
         "encode.rkt")

(provide (contract-out
          [hub? (-> any/c boolean?)]
          [make-hub (-> hub?)]
          [hub-clients (-> hub? (listof output-port?))]
          [hub-attach! (-> hub? output-port? void?)]
          [hub-detach! (-> hub? output-port? void?)]
          [hub-notify! (->* (hub? sse-event-name? string?) ((or/c sse-line? #f)) void?)]
          [hub-watch! (-> hub? (and/c real? positive?) sse-event-name?
                          (-> (or/c string? #f)) thread?)]
          [hub-stream (->* (hub? output-port?)
                           (#:retry (and/c exact-integer? positive?)
                            #:heartbeat (and/c real? positive?))
                           void?)]))

;; Internal state: a clients list guarded by its own semaphore (unbox/
;; set-box! alone leaves a read-modify-write window between attach and
;; notify), plus the most recent frame for replay.
(struct hub (clients-sem clients-box last-frame-box))

(define (make-hub)
  (hub (make-semaphore 1) (box '()) (box #f)))

(define (hub-clients h)
  (unbox (hub-clients-box h)))

(define (hub-attach! h port)
  (call-with-semaphore
   (hub-clients-sem h)
   (λ ()
     (unless (memq port (unbox (hub-clients-box h)))
       (set-box! (hub-clients-box h)
                 (append (unbox (hub-clients-box h)) (list port)))))))

(define (hub-detach! h port)
  (define removed?
    (call-with-semaphore
     (hub-clients-sem h)
     (λ ()
       (define cs (unbox (hub-clients-box h)))
       (when (memq port cs)
         (set-box! (hub-clients-box h) (remq port cs))
         #t))))
  (when removed?
    (with-handlers ([exn:fail? void])
      (close-output-port port))))

(define (safe-write h port s)
  (with-handlers ([exn:fail? (λ (_) (hub-detach! h port))])
    (display s port)
    (flush-output port)))

(define (hub-notify! h event data [id #f])
  (define frame (sse-encode event data id))
  (set-box! (hub-last-frame-box h) frame)
  (for ([p (in-list (hub-clients h))])
    (safe-write h p frame)))

(define logger (make-logger 'sse))

;; Poll thunk every poll-seconds; the first call establishes the
;; baseline and does not notify.  A non-#f result different from the
;; previous one is broadcast as (event result).  Thunk errors are
;; logged and treated as "nothing new" so one bad poll cannot kill the
;; watcher.
(define (hub-watch! h poll-seconds event value-thunk)
  (define (safe-thunk)
    (with-handlers ([exn:fail?
                     (λ (e)
                       (log-message logger 'error "sse: watch thunk failed" e)
                       #f)])
      (value-thunk)))
  (thread
   (λ ()
     (let loop ([last (safe-thunk)])
       (sleep poll-seconds)
       (define v (safe-thunk))
       (when (and v (not (equal? v last)))
         (hub-notify! h event v))
       (loop (or v last))))))

(define (format-retry ms)
  (string-append "retry: " (number->string ms) "\n\n"))

;; Long-lived response body: attach, send the retry hint, replay the
;; most recent frame, then emit a comment heartbeat every heartbeat
;; seconds until the client goes away.  A dead client makes the next
;; write raise, which detaches and ends this thread.
(define (hub-stream h out #:retry [retry-ms 5000] #:heartbeat [heartbeat 15])
  (hub-attach! h out)
  (with-handlers ([exn:fail? (λ (_) (hub-detach! h out))])
    (display (format-retry retry-ms) out)
    (flush-output out)
    (define last (unbox (hub-last-frame-box h)))
    (when last
      (display last out)
      (flush-output out))
    (let loop ()
      (cond
        [(sync/timeout heartbeat (port-closed-evt out))
         (hub-detach! h out)]
        [else
         (display (sse-comment "ping") out)
         (flush-output out)
         (loop)]))))
