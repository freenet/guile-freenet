#!/usr/bin/env bash
# -*- wisp -*-
# A Freenet Client Protocol library for Guile Scheme.

guile -L $(dirname $(realpath "$0")) -c '(import (language wisp spec))'
PROG="$0"
if [[ "$1" == "-i" ]]; then
    shift
    exec -a "${PROG}" guile -L $(dirname $(realpath "$0")) --language=wisp -x .w -e '(fcp-example)' -- "${@}"
else
    exec -a "${0}" guile -L $(dirname $(realpath "$0")) --language=wisp -x .w -e '(fcp-example)' -c '' "${@}"
fi;
; !#

;; for emacs (defun test-this-file () (interactive) (save-current-buffer) (async-shell-command (concat (buffer-file-name (current-buffer)) " --test")))

define-module : fcp-example
    . #:export : main

define version "0.0.0 just-do-it"

import
    only (fcp) message-create message-task message-type message-data message-fields
             . message-client-get  message-client-get-realtime message-client-get-bulk 
             . message-client-put message-client-put-realtime message-client-put-bulk 
             . message-remove-request
             . send-message processor-put! processor-delete!
             . printing-passthrough-processor printing-discarding-processor 
             . discarding-processor processor-nodehello-printer
             . processor-datafound-getdata 
             . task-id
             . call-with-fcp-connection with-fcp-connection
    only (ice-9 pretty-print) pretty-print truncated-print
    only (ice-9 iconv) string->bytevector
    only (srfi srfi-1) first second third alist-cons assoc lset<= lset-intersection lset-difference take
    only (rnrs bytevectors) make-bytevector bytevector-length string->utf8 utf8->string bytevector?
    only (rnrs io ports) get-bytevector-all get-bytevector-n
         . put-bytevector bytevector->string port-eof?
    only (ice-9 popen) open-output-pipe
    only (ice-9 regex) string-match match:substring
    doctests

define : help args
    format : current-output-port
           . "~a [-i] [--help | --version | --test | YYYY-mm-dd]

Options:
        -i    load the script and run an interactive REPL."
           first args

define : final-action? args
   if {(length args) <= 1} #f
     cond 
       : equal? "--help" : second args
         help args
         . #t
       : equal? "--version" : second args
         format : current-output-port
                . "~a\n" version
         . #t
       else #f
       
    
define : main args
  define put-task : task-id
  define get-task : task-id
  define key : string-append "KSK@" put-task
  define successful #f
  ;; setup interaction:
  ;; when the put succeeds, download the data.
  define : request-successful-upload message
    cond
        : equal? 'PutSuccessful : message-type message
          let : : fields : message-fields message
              when : and=> (assoc 'URI fields) : λ (uri) : equal? key : cdr uri
                  pretty-print message
                  send-message
                      message-client-get-realtime get-task key
              . #f
        else message
  ;; when the download succeeds, display the result and 
  define : record-successful-download message
    cond
        : equal? 'AllData : message-type message
          let : : task : message-task message
              when : equal? task get-task
                  pretty-print message
                  display "Data: "
                  truncated-print : utf8->string (message-data message)
                  newline
                  set! successful #t
              . #f
        else message
  ;; cleanup the task because we use the global queue for easier debugging
  define : remove-successful-tasks-from-queue message
    when : member (message-type message) '(AllData PutSuccessful)
           send-message : message-remove-request : message-task message
    . message
  ;; standard processorrs
  processor-put! printing-discarding-processor
  processor-put! processor-nodehello-printer
  ;; immediately request data from successfull get requests
  processor-put! processor-datafound-getdata
  ;; custom processors
  processor-put! request-successful-upload
  processor-put! record-successful-download
  processor-put! remove-successful-tasks-from-queue
  when : not : final-action? args
    with-fcp-connection
        ;; get the ball rolling
        send-message
            message-client-put-realtime put-task key
                string->utf8 : string-append "Hello " key
        while : not successful
            display "."
            sleep 10