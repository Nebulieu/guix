;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013, 2014 Ludovic Courtès <ludo@gnu.org>
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

(define-module (guix build-system perl)
  #:use-module (guix store)
  #:use-module (guix utils)
  #:use-module (guix derivations)
  #:use-module (guix build-system)
  #:use-module (guix build-system gnu)
  #:use-module (guix packages)
  #:use-module (ice-9 match)
  #:export (perl-build
            perl-build-system))

;; Commentary:
;;
;; Standard build procedure for Perl packages using the "makefile
;; maker"---i.e., "perl Makefile.PL".  This is implemented as an extension of
;; `gnu-build-system'.
;;
;; Code:

(define (default-perl)
  "Return the default Perl package."

  ;; Do not use `@' to avoid introducing circular dependencies.
  (let ((module (resolve-interface '(gnu packages perl))))
    (module-ref module 'perl)))

(define* (lower name
                #:key source inputs native-inputs outputs
                system target
                (perl (default-perl))
                #:allow-other-keys
                #:rest arguments)
  "Return a bag for NAME."
  (define private-keywords
    '(#:source #:target #:perl #:inputs #:native-inputs))

  (and (not target)                               ;XXX: no cross-compilation
       (bag
         (name name)
         (system system)
         (host-inputs `(,@(if source
                              `(("source" ,source))
                              '())
                        ,@inputs

                        ;; Keep the standard inputs of 'gnu-build-system'.
                        ,@(standard-packages)))
         (build-inputs `(("perl" ,perl)
                         ,@native-inputs))
         (outputs outputs)
         (build perl-build)
         (arguments (strip-keyword-arguments private-keywords arguments)))))

(define* (perl-build store name inputs
                     #:key
                     (search-paths '())
                     (tests? #t)
                     (parallel-build? #t)
                     (parallel-tests? #t)
                     (make-maker-flags ''())
                     (phases '(@ (guix build perl-build-system)
                                 %standard-phases))
                     (outputs '("out"))
                     (system (%current-system))
                     (guile #f)
                     (imported-modules '((guix build perl-build-system)
                                         (guix build gnu-build-system)
                                         (guix build utils)))
                     (modules '((guix build perl-build-system)
                                (guix build utils))))
  "Build SOURCE using PERL, and with INPUTS.  This assumes that SOURCE
provides a `Makefile.PL' file as its build system."
  (define builder
    `(begin
       (use-modules ,@modules)
       (perl-build #:name ,name
                   #:source ,(match (assoc-ref inputs "source")
                               (((? derivation? source))
                                (derivation->output-path source))
                               ((source)
                                source)
                               (source
                                source))
                   #:search-paths ',(map search-path-specification->sexp
                                         search-paths)
                   #:make-maker-flags ,make-maker-flags
                   #:phases ,phases
                   #:system ,system
                   #:test-target "test"
                   #:tests? ,tests?
                   #:parallel-build? ,parallel-build?
                   #:parallel-tests? ,parallel-tests?
                   #:outputs %outputs
                   #:inputs %build-inputs)))

  (define guile-for-build
    (match guile
      ((? package?)
       (package-derivation store guile system #:graft? #f))
      (#f                                         ; the default
       (let* ((distro (resolve-interface '(gnu packages commencement)))
              (guile  (module-ref distro 'guile-final)))
         (package-derivation store guile system #:graft? #f)))))

  (build-expression->derivation store name builder
                                #:system system
                                #:inputs inputs
                                #:modules imported-modules
                                #:outputs outputs
                                #:guile-for-build guile-for-build))

(define perl-build-system
  (build-system
    (name 'perl)
    (description "The standard Perl build system")
    (lower lower)))

;;; perl.scm ends here
