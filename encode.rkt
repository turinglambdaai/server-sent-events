#lang racket/base

;; WHATWG Server-Sent Events wire format: frame encoding and comments.
;; Pure string in, string out; the caller owns ports and transport.

(require racket/contract
         racket/string)

(provide (contract-out
          [sse-line? (-> any/c boolean?)]
          [sse-event-name? (-> any/c boolean?)]
          [sse-encode (->* (sse-event-name? string?) ((or/c sse-line? #f)) string?)]
          [sse-comment (-> sse-line? string?)]))

;; A single wire line: no CR, no LF.
(define (sse-line? s)
  (and (string? s) (non-empty-string? s)
       (not (string-contains? s "\n"))
       (not (string-contains? s "\r"))))

;; An event name is additionally colon-free (the field parser would
;; otherwise read it as a field/value separator).
(define (sse-event-name? s)
  (and (sse-line? s) (not (string-contains? s ":"))))

;; Data may span lines: the spec splits values on CRLF, CR, or LF and
;; emits one "data:" line per piece, which is what keeps multi-line
;; payloads reconstructible on the client.
(define (data-lines s)
  (regexp-split #rx"\r\n|[\r\n]" s))

(define (sse-encode event data [id #f])
  (string-append
   "event: " event "\n"
   (if id (string-append "id: " id "\n") "")
   (string-append*
    (for/list ([line (in-list (data-lines data))])
      (string-append "data: " line "\n")))
   "\n"))

(define (sse-comment text)
  (string-append ": " text "\n\n"))
