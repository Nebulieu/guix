;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013 Ludovic Courtès <ludo@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (guix pki)
  #:use-module (guix config)
  #:use-module (guix pk-crypto)
  #:use-module ((guix utils) #:select (with-atomic-file-output))
  #:use-module (ice-9 match)
  #:use-module (rnrs io ports)
  #:export (%public-key-file
            %private-key-file
            %acl-file
            current-acl
            public-keys->acl
            acl->public-keys
            signature-sexp
            authorized-key?))

;;; Commentary:
;;;
;;; Public key infrastructure for the authentication and authorization of
;;; archive imports.  This is essentially a subset of SPKI for our own
;;; purposes (see <http://theworld.com/~cme/spki.txt> and
;;; <http://www.ietf.org/rfc/rfc2693.txt>.)
;;;
;;; Code:

(define (acl-entry-sexp public-key)
  "Return a SPKI-style ACL entry sexp for PUBLIC-KEY, authorizing imports
signed by the corresponding secret key (see the IETF draft at
<http://theworld.com/~cme/spki.txt> for the ACL format.)"
  ;; Note: We always use PUBLIC-KEY to designate the subject.  Someday we may
  ;; want to have name certificates and to use subject names instead of
  ;; complete keys.
  (string->canonical-sexp
   (format #f
           "(entry ~a (tag (guix import)))"
           (canonical-sexp->string public-key))))

(define (acl-sexp entries)
  "Return an ACL sexp from ENTRIES, a list of 'entry' sexps."
  (string->canonical-sexp
   (string-append "(acl "
                  (string-join (map canonical-sexp->string entries))
                  ")")))

(define (public-keys->acl keys)
  "Return an ACL canonical sexp that lists all of KEYS with a '(guix import)'
tag---meaning that all of KEYS are authorized for archive imports.  Each
element in KEYS must be a canonical sexp with type 'public-key'."
  (acl-sexp (map acl-entry-sexp keys)))

(define %acl-file
  (string-append %config-directory "/acl"))

(define %public-key-file
  (string-append %config-directory "/signing-key.pub"))

(define %private-key-file
  (string-append %config-directory "/signing-key.sec"))

(define (ensure-acl)
  "Make sure the ACL file exists, and create an initialized one if needed."
  (unless (file-exists? %acl-file)
    ;; If there's no public key file, don't attempt to create the ACL.
    (when (file-exists? %public-key-file)
      (let ((public-key (call-with-input-file %public-key-file
                          (compose string->canonical-sexp
                                   get-string-all))))
        (with-atomic-file-output %acl-file
          (lambda (port)
            (display (canonical-sexp->string
                      (public-keys->acl (list public-key)))
                     port)))))))

(define (current-acl)
  "Return the current ACL as a canonical sexp."
  (ensure-acl)
  (if (file-exists? %acl-file)
      (call-with-input-file %acl-file
        (compose string->canonical-sexp
                 get-string-all))
      (public-keys->acl '())))                    ; the empty ACL

(define (acl->public-keys acl)
  "Return the public keys (as canonical sexps) listed in ACL with the '(guix
import)' tag."
  (match (canonical-sexp->sexp acl)
    (('acl
      ('entry subject-keys
              ('tag ('guix 'import)))
      ...)
     (map sexp->canonical-sexp subject-keys))
    (_
     (error "invalid access-control list" acl))))

(define* (authorized-key? key
                          #:optional (acl (current-acl)))
  "Return #t if KEY (a canonical sexp) is an authorized public key for archive
imports according to ACL."
  (let ((key (canonical-sexp->sexp key)))
    (match (canonical-sexp->sexp acl)
      (('acl
        ('entry subject-keys
                ('tag ('guix 'import)))
        ...)
       (not (not (member key subject-keys))))
      (_
       (error "invalid access-control list" acl)))))

(define (signature-sexp data secret-key public-key)
  "Return a SPKI-style sexp for the signature of DATA with SECRET-KEY that
includes DATA, the actual signature value (with a 'sig-val' tag), and
PUBLIC-KEY (see <http://theworld.com/~cme/spki.txt> for examples.)"
  (string->canonical-sexp
   (format #f
           "(signature ~a ~a ~a)"
           (canonical-sexp->string data)
           (canonical-sexp->string (sign data secret-key))
           (canonical-sexp->string public-key))))

;;; pki.scm ends here