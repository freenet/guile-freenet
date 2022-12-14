#!/bin/sh
# -*- scheme -*-
exec guile -e main -s "$0" "$@"
!#

;; Parser to turn a set of downloaded WoT files into a standard graph format.

(use-modules (web request)
             (web client)
             (web response)
             (web uri)
             (web http)
             (ice-9 threads)
             (ice-9 vlist)
             (ice-9 rdelim)
             (rnrs io ports)
             (ice-9 match)
             (srfi srfi-42)
             (srfi srfi-1)
             (rnrs bytevectors)
             (sxml simple)
             (sxml match)
             (ice-9 ftw))


(define (non-breaking-sxml-reader xml-port)
  (catch #t
         (lambda () (xml->sxml xml-port))
         (lambda (key . args) (format #t "~A: ~A" key args)(newline) '())))


(define (wot-uri-key uri)
  (let ((index (string-index uri #\/)))
    (if index 
        (string-take uri index)
        uri))) ;; no / in uri, so it is already a key.


(define (wot-file-key filename)
  (let* ((pubkey-identifier ",AQACAAE")
         (index (string-contains filename pubkey-identifier)))
    (if index
        (string-take filename (+ index (string-length pubkey-identifier)))
        filename)))


(define (parse-trust-values filename)
  (let* ((port (open-input-file filename))
         (sxml (non-breaking-sxml-reader port))
         (closed (close-port port))
         (trust '()))
    (let extract-trust ((sxml sxml))
      (match sxml
        (('Trust ('@ ('Value value) ('Identity uri) rest ...))
         (set! trust
           (cons (cons (wot-uri-key uri)
                       (string->number value))
                 trust)))
        ((a b ...)
         (map extract-trust sxml))
        (else '())))
    (cons (wot-file-key filename) trust)))


(define* (trust-lists->csv trusts #:key (target-filename #f))
  "Format the list of trust lists as csv file.

See https://gephi.org/users/supported-graph-formats/csv-format/

steps:
- trusting ids: map car trusts
- additional ids: every ID not in trusting ids.

Source;Target;Weight
A;B;0
B;A;1

"
  (let ((port (if target-filename
                  (open-output-file target-filename)
                  (current-output-port)))
        (ids (map car trusts)))
    (display "Source;Target;Weight" port)
    (newline port)
    (let write-edges ((trusts trusts))
      (cond ((null? trusts) #t)
            (else
             (let* ((id (car (car trusts)))
                    (trusted (cdr (car trusts))))
               (let write-trust ((trusted trusted))
                 (cond ((null? trusted) #t)
                       (else 
                        (let* ((edge (car trusted))
                               (trustee (car edge))
                               (weight (cdr edge)))
                          (when weight ; avoid stumbling over incorrectly formatted trust values
                              (format port "~A;~A;~f\n" id trustee weight))
                          (write-trust (cdr trusted)))))))
             (write-edges (cdr trusts)))))
    ; (write (car trusts))
    ; (newline)
    (when target-filename (close-port port))))


(define (main args)
  (let ((dir (if (null? (cdr args))
                 "."
                 (car (cdr args)))))
    (let* ((select? (lambda (x) (or (equal? x ".") (string-prefix? "USK@" x))))
           (files (cdr (scandir dir select?))))
      (trust-lists->csv 
       (par-map parse-trust-values files)
       #:target-filename "trust.csv"))))
