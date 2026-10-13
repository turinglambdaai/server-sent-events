#lang info

(define collection "server-sent-events")
(define version "0.1")
(define deps '("base"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"
                     "web-server-lib" "web-server-doc"))
(define scribblings '(("scribblings/server-sent-events.scrbl" ())))
(define pkg-desc "Server-Sent Events: WHATWG wire-format encoding and a fan-out hub")
(define license 'MIT)
(define pkg-authors '(turinglambdaai))
(define test-omit-paths '("scribblings"))
