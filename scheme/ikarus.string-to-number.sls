;;;Ikarus Scheme -- A compiler for R6RS Scheme.
;;;Copyright (C) 2008,2009  Abdulaziz Ghuloum
;;;Modified by Marco Maggi <marco.maggi-ipsu@poste.it>
;;;
;;;This program is free software:  you can redistribute it and/or modify
;;;it under  the terms of  the GNU General  Public License version  3 as
;;;published by the Free Software Foundation.
;;;
;;;This program is  distributed in the hope that it  will be useful, but
;;;WITHOUT  ANY   WARRANTY;  without   even  the  implied   warranty  of
;;;MERCHANTABILITY  or FITNESS FOR  A PARTICULAR  PURPOSE.  See  the GNU
;;;General Public License for more details.
;;;
;;;You should  have received  a copy of  the GNU General  Public License
;;;along with this program.  If not, see <http://www.gnu.org/licenses/>.


(library (ikarus.string-to-number)
  (export string->number define-string->number-parser)
  (import (except (ikarus)
		  string->number)
    (vicare syntactic-extensions)
    (prefix (vicare unsafe-operations)
	    unsafe.))

;;; <number>          ::= <num 2>
;;;                     | <num 8>
;;;                     | <num 10>
;;;                     | <num 16>
;;; <num R>           ::= <prefix R> <complex R>
;;; <complex R>       ::= <real R>
;;;                     | <real R> "@" <real R>
;;;                     | <real R> "+" <ureal R> "i"
;;;                     | <real R> "-" <ureal R> "i"
;;;                     | <real R> "+" <naninf> "i"
;;;                     | <real R> "-" <naninf> "i"
;;;                     | <real R> "+" "i"
;;;                     | <real R> "-" "i"
;;;                     | "+" <ureal R> "i"
;;;                     | "-" <ureal R> "i"
;;;                     | "+" <naninf> "i"
;;;                     | "-" <naninf> "i"
;;;                     | "+" "i"
;;;                     | "-" "i"
;;; <real R>          ::= <sign> <ureal R>
;;;                     | "+" <naninf>
;;;                     | "-" <naninf>
;;; <naninf>          ::= "nan.0"
;;;                     | "inf.0"
;;; <ureal R>           | <uinteger R>
;;;                     | <uinteger R> "/" <uinteger R>
;;;                     | <decimal R> <mantissa width>
;;; <decimal 10>      ::= <uinteger 10> <suffix>
;;;                     | "." <digit 10> + <suffix>
;;;                     | <digit 10> + "." <digit 10> * <suffix>
;;;                     | <digit 10> + "." <suffix>
;;; <uinteger R>      ::= <digit R> +
;;; <prefix R>          | <radix R> <exactness>
;;;                     | <exactness <radix R>
;;; <suffix>          ::= epsilon
;;;                     | <exponent-marker> <sign> <digit 10> +
;;; <exponent-marker> ::= "e"
;;;                     | "E"
;;;                     | "s"
;;;                     | "S"
;;;                     | "f"
;;;                     | "F"
;;;                     | "d"
;;;                     | "D"
;;;                     | "l"
;;;                     | "L"
;;; <mantissa-width>  ::= epsilon
;;;                     | "|" <digit +>
;;; <sign>            ::= epsilon
;;;                     | "+"
;;;                     | "-"
;;; <exactness>       ::= epsilon
;;;                     | "#i"
;;;                     | "#I"
;;;                     | "#e"
;;;                     | "#E"
;;; <radix-2>         ::= "#b"
;;;                     | "#B"
;;; <radix-8>         ::= "#o"
;;;                     | "#O"
;;; <radix-10>        ::= epsilon
;;;                     | "#d"
;;;                     | "#D"
;;; <radix-16>        ::= "#x"
;;;                     | "#X"
;;; <digit-2>         ::= "0"
;;;                     | "1"
;;; <digit-8>         ::= "0"
;;;                     | "1"
;;;                     | "2"
;;;                     | "3"
;;;                     | "4"
;;;                     | "5"
;;;                     | "6"
;;;                     | "7"
;;; <digit-10>        ::= <digit>
;;; <digit-16>        ::= <hex-digit>
;;; <digit>           ::= "0"
;;;                     | "1"
;;;                     | "2"
;;;                     | "3"
;;;                     | "4"
;;;                     | "5"
;;;                     | "6"
;;;                     | "7"
;;;                     | "8"
;;;                     | "9"
;;; <hex-digit>       ::= <hex>
;;;                     | "A"
;;;                     | "B"
;;;                     | "C"
;;;                     | "D"
;;;                     | "E"
;;;                     | "F"
;;;                     | "a"
;;;                     | "b"
;;;                     | "c"
;;;                     | "d"
;;;                     | "e"
;;;                     | "f"


;;;; arguments validation

(define-argument-validation (string who obj)
  (string? obj)
  (assertion-violation who "expected string as argument" obj))

(define-argument-validation (radix who obj)
  (memv obj '(10 16 2 8))
  (assertion-violation who "expected supported radix as argument" obj))


;;;; helpers

(define CHAR-FIXNUM-0		(unsafe.char->fixnum #\0))
(define CHAR-FIXNUM-a		(unsafe.char->fixnum #\a))
(define CHAR-FIXNUM-A		(unsafe.char->fixnum #\A))

(define who 'string->number)

(define-inline (do-sn/ex sn ex ?ac)
  ;;Compose the accumulated number ?AC with the sign SN according to the
  ;;exactness EX.
  ;;
  (let ((ac ?ac))
    (* sn (if (eq? ex 'i) (inexact ac) ac))))

(define-inline (do-dec-sn/ex sn ex ?ac)
  ;;Compose the accumulated number ?AC with the sign SN according to the
  ;;exactness EX.
  ;;
  (let ((ac ?ac))
    (* sn (if (eq? ex 'e) ac (inexact ac)))))

(define (sign c)
  (cond ((unsafe.char= #\+ c)	+1)
	((unsafe.char= #\- c)	-1)
	(else			#f))
  #;(case c ((#\+) +1) ((#\-) -1) (else  #f)))

(define (digit ch r)
  ;;Given  a character CH  representing a  digit in  some base  R (which
  ;;should be  the fixnum 2, 8,  10 or 16) return  a fixnum representing
  ;;the digit in base R.
  ;;
  (let ((n (unsafe.fx- (unsafe.char->fixnum ch) CHAR-FIXNUM-0)))
    (cond ((and (unsafe.fx>= n 0)
		(unsafe.fx<  n r))
	   n)
	  ((eqv? r 16)
	   (let ((n (fx- (unsafe.char->fixnum ch) CHAR-FIXNUM-a)))
	     (if (and (unsafe.fx>= n 0)
		      (unsafe.fx<  n 6))
		 (unsafe.fx+ n 10)
	       (let ((n (unsafe.fx- (unsafe.char->fixnum ch) CHAR-FIXNUM-A)))
		 (if (and (unsafe.fx>= n 0)
			  (unsafe.fx<  n 6))
		     (unsafe.fx+ n 10)
		   #f)))))
	  (else #f))))

(define (mkrec0 n0 n1)
  (cond ((not n0)
	 (make-rectangular 0 n1))
	((and (pair? n0)
	      (eq? (unsafe.car n0) 'polar))
	 (make-polar (unsafe.cdr n0) n1))
	(else
	 (make-rectangular n0 n1))))

(define (mkrec1 n0 n1)
  (cond ((not n0)
	 n1)
	((and (pair? n0)
	      (eq? (unsafe.car n0) 'polar))
	 (make-polar (unsafe.cdr n0) n1))
	(else
	 (make-rectangular n0 n1))))


(module (define-parser)

  (define-syntax gen-empty
    (syntax-rules (eof)
      ((_ C Ca)
       (C EOF-ERROR Ca))
      ((_ C Ca ((eof) then) . rest)
       then)
      ((_ C Ca other . rest)
       (gen-empty C Ca . rest))))

  (define-syntax gen-delimiter
    (syntax-rules (eof)
      ((_ C Ca c)
       (C GEN-DELIM-TEST c
	  (C FAIL Ca)
	  (C FAIL Ca c)))
      ((_ C Ca c ((eof) then) . rest)
       (C GEN-DELIM-TEST c
	  then
	  (C FAIL Ca c)))
      ((_ C Ca c other . rest)
       (gen-delimiter C Ca c . rest))))

  (define-syntax gen-char
    (syntax-rules (eof =>)
      ((_ C Ca c dc)
       dc)
      ((_ C Ca c dc ((eof) then) . rest)
       (gen-char C Ca c dc . rest))
      ((_ C Ca c dc ((test . args) => result then) . rest)
       (cond ((test c . args)
	      => (lambda (result) then))
	     (else
	      (gen-char C Ca c dc . rest))))
      ((_ C Ca c dc (ls then) . rest)
       (if (memv c 'ls)
	   then
	 (gen-char C Ca c dc . rest)))))

  (define-syntax gen-clause
    (syntax-rules ()
      ((_ (Ca ...) C next fail name (arg* ...) (clause* ...))
       (define (name Ca ... arg* ...)
	 (C GEN-TEST c next fail (Ca ...)
	    (gen-empty C (Ca ...) clause* ...)
	    (gen-char C (Ca ...) c
		      (gen-delimiter C (Ca ...) c clause* ...)
		      clause* ...))))))

  (define-syntax define-parser^
    ;;This is the true parser generator.
    ;;
    (lambda (x)
      (define (lookup ls1 ls2)
	(lambda (var)
	  (let f ((ls1 ls1) (ls2 ls2))
	    (cond
	     ((null? ls1)
	      (error 'define-parser "cannot find" var))
	     ((bound-identifier=? var (unsafe.car ls1))
	      (unsafe.car ls2))
	     (else (f (unsafe.cdr ls1) (unsafe.cdr ls2)))))))
      (syntax-case x ()
	((_ (entries ...) config next fail
	    orig*
	    (name* (arg** ...) clause** ...) ...)
	 (with-syntax (((mapped-entries ...)
			(map (lookup (syntax->datum #'orig*) #'(name* ...))
			  #'(entries ...))))
	   #'(begin
	       (config GEN-ARGS
		       gen-clause config next fail name*
		       (arg** ...)
		       (clause** ...))
	       ...
	       (define entries mapped-entries)
	       ...))))))

  (define-syntax define-parser
    ;;Interface  to  DEFINE-PARSER^  which  only  introduces  ORIG*  and
    ;;reorganises the order of the arguments.
    ;;
    (lambda (x)
      (syntax-case x ()
	((_ definer next fail (name* (arg** ...) clause** ...) ...)
	 (with-syntax ((orig* (datum->syntax #'foo #'(name* ...))))
	   #'(define-syntax definer
	       (syntax-rules ()
		 ((_ config (entries (... ...)))
		  (define-parser^ (entries (... ...)) config next fail
		    orig*
		    (name* (arg** ...) clause** ...) ...))))
	   ))
	)))

  #| end of module |#)


(define-parser define-string->number-parser next fail

  (u:ratio+ (r n0 ex sn num ac)
	    ((eof)
	     (if (or n0 (= ac 0))
		 (fail)
	       (do-sn/ex sn ex (/ num ac))))
	    ((digit r) => d
	     (next u:ratio+ r n0 ex sn num (+ (* ac r) d)))
	    ((sign) => sn2
	     (if (or n0 (= ac 0))
		 (fail)
	       (let ((real (do-sn/ex sn ex (/ num ac))))
		 (next u:sign r real ex sn2))))
	    ((#\@)
	     (if (or n0 (= ac 0))
		 (fail)
	       (let ((mag (do-sn/ex sn ex (/ num ac))))
		 (next u:polar r mag ex))))
	    ((#\i)
	     (if (= ac 0)
		 (fail)
	       (next u:done (mkrec0 n0 (do-sn/ex sn ex (/ num ac)))))))

  (u:ratio (r n0 ex sn num)
	   ((digit r) => d
	    (next u:ratio+ r n0 ex sn num d)))

  (u:done (n)
	  ((eof) n))

  (u:polar (r mag ex)
	   ((digit r) => d
	    (next u:digit+ r (cons 'polar mag) ex +1 d))
	   ((#\.)
	    (if (= r 10)
		(next u:dot r (cons 'polar mag) ex +1)
	      (fail)))
	   ((sign) => sn
	    (next u:sign r (cons 'polar mag) ex sn)))

  (u:exponent+digit (r n0 ex sn ac exp1 exp2 exp-sign)
		    ((eof)
		     (if (number? n0)
			 (fail)
		       (mkrec1 n0 (do-dec-sn/ex sn ex
						(* ac (expt 10 (+ exp1 (* exp2 exp-sign))))))))
		    ((digit r) => d
		     (next u:exponent+digit r n0 ex sn ac exp1 (+ (* exp2 r) d) exp-sign))
		    ((sign) => sn2
		     (if n0
			 (fail)
		       (let ((real (do-dec-sn/ex sn ex (* ac (expt 10 (+ exp1 (* exp2 exp-sign)))))))
			 (next u:sign r real ex sn2))))
		    ((#\@)
		     (if n0
			 (fail)
		       (let ((mag (do-dec-sn/ex sn ex (* ac (expt 10 (+ exp1 (* exp2 exp-sign)))))))
			 (next u:polar r mag ex))))
		    ((#\i)
		     (let ((n1 (do-dec-sn/ex sn ex
					     (* ac (expt 10 (+ exp1 (* exp2 exp-sign)))))))
		       (next u:done (mkrec0 n0 n1))))
		    ((#\|)
		     (let ((n1 (do-dec-sn/ex sn ex
					     (* ac (expt 10 (+ exp1 (* exp2 exp-sign)))))))
		       (next u:mant r n0 n1 ex))))

  (u:exponent+sign (r n0 ex sn ac exp1 exp-sign)
		   ((digit r) => d
		    (next u:exponent+digit r n0 ex sn ac exp1 d exp-sign)))

  (u:exponent (r n0 ex sn ac exp1)
	      ((digit r) => d
	       (next u:exponent+digit r n0 ex sn ac exp1 d +1))
	      ((sign) => sn2 (next u:exponent+sign r n0 ex sn ac exp1 sn2)))

  (u:digit+dot (r n0 ex sn ac exp)
	       ((eof)
		(if (and n0 (not (pair? n0)))
		    (fail)
		  (mkrec1 n0 (do-dec-sn/ex sn ex (* ac (expt 10 exp)))))
;;;       (mkrec1 n0 (do-dec-sn/ex sn ex (* ac (expt 10 exp))))
		)
	       ((digit r) => d
		(next u:digit+dot r n0 ex sn (+ (* ac r) d) (- exp 1)))
	       ((#\i)
		(let ((n1 (do-dec-sn/ex sn ex (* ac (expt 10 exp)))))
		  (next u:done (mkrec0 n0 n1))))
	       ((sign) => sn2
		(if n0
		    (fail)
		  (let ((real (do-dec-sn/ex sn ex (* ac (expt 10 exp)))))
		    (next u:sign r real ex sn2))))
	       ((#\@)
		(if n0
		    (fail)
		  (let ((mag (do-dec-sn/ex sn ex (* ac (expt 10 exp)))))
		    (next u:polar r mag ex))))
	       ((#\e #\E #\s #\S #\f #\F #\d #\D #\l #\L)
		(if (fx=? r 10)
		    (next u:exponent r n0 ex sn ac exp)
		  (fail)))
	       ((#\|)
		(let ((n1 (do-dec-sn/ex sn ex (* ac (expt 10 exp)))))
		  (next u:mant r n0 n1 ex)))
	       )


  (u:digit+ (r n0 ex sn ac)
	    ((eof)
	     (if (and n0 (not (pair? n0)))
		 (fail)
	       (mkrec1 n0 (do-sn/ex sn ex ac)))
;;;       (mkrec1 n0 (do-sn/ex sn ex ac))
	     )
	    ((digit r) => d
	     (next u:digit+ r n0 ex sn (+ (* ac r) d)))
	    ((#\.)
	     (if (fx=? r 10)
		 (next u:digit+dot r n0 ex sn ac 0)
	       (fail)))
	    ((#\/) (next u:ratio r n0 ex sn ac))
	    ((sign) => sn2
	     (if n0
		 (fail)
	       (let ((real (do-sn/ex sn ex ac)))
		 (next u:sign r real ex sn2))))
	    ((#\i)
	     (next u:done (mkrec0 n0 (do-sn/ex sn ex ac))))
	    ((#\@)
	     (if n0
		 (fail)
	       (let ((mag (do-sn/ex sn ex ac)))
		 (next u:polar r mag ex))))
	    ((#\e #\E #\s #\S #\f #\F #\d #\D #\l #\L)
	     (if (fx=? r 10)
		 (next u:exponent r n0 ex sn ac 0)
	       (fail)))
	    ((#\|)
	     (next u:mant r n0 (do-sn/ex sn 'i ac) ex)))

  (u:mant (r n0 n1 ex)
	  ((digit r) => d_
	   (next u:mant+ r n0 n1 ex)))

  (u:mant+ (r n0 n1 ex)
	   ((eof) (mkrec1 n0 n1))
	   ((digit r) => d_
	    (next u:mant+ r n0 n1 ex))
	   ((sign) => sn2
	    (if n0 (fail) (next u:sign r n1 ex sn2)))
	   ((#\@) (if n0 (fail) (next u:polar r n1 ex)))
	   ((#\i) (if (pair? n0) (fail) (next u:done (mkrec0 n0 n1)))))

  (u:sign-i (r n0 ex sn)
	    ((eof) (mkrec0 n0 (do-sn/ex sn ex 1)))
	    ((#\n) (next u:sign-in r n0 (* sn +inf.0) ex)))
  (u:sign-in (r n0 n1 ex)
	     ((#\f) (next u:sign-inf r n0 n1 ex)))
  (u:sign-inf (r n0 n1 ex)
	      ((#\.) (next u:sign-inf. r n0 n1 ex)))
  (u:sign-inf. (r n0 n1 ex)
	       ((#\0) (next u:sign-inf.0 r n0 n1 ex)))
  (u:sign-inf.0 (r n0 n1 ex)
		((eof) (mkrec1 n0 n1))
		((sign) => sn2
		 (if n0 (fail) (next u:sign r n1 ex sn2)))
		((#\@) (if n0 (fail) (next u:polar r n1 ex)))
		((#\i) (next u:done (mkrec0 n0 n1))))

  (u:dot (r n0 ex sn)
	 ((digit r) => d
	  (next u:digit+dot r n0 ex sn d -1)))

  (u:sign (r n0 ex sn)
	  ((digit r) => d
	   (next u:digit+ r n0 ex sn d))
	  ((#\i) (next u:sign-i r n0 ex sn))
	  ((#\n) (next u:sign-n r n0 ex))
	  ((#\.)
	   (if (= r 10)
	       (next u:dot r n0 ex sn)
	     (fail))))

  (u:sign-n (r n0 ex) ((#\a) (next u:sign-na r n0 ex)))
  (u:sign-na (r n0 ex) ((#\n) (next u:sign-nan r n0 ex)))
  (u:sign-nan (r n0 ex) ((#\.) (next u:sign-nan. r n0 ex)))
  (u:sign-nan. (r n0 ex) ((#\0) (next u:sign-nan.0 r n0 ex)))
  (u:sign-nan.0 (r n0 ex)
		((eof) (mkrec1 n0 +nan.0))
		((sign) => sn2 (if n0 (fail) (next u:sign r +nan.0 ex sn2)))
		((#\@) (if n0 (fail) (next u:polar r +nan.0 ex)))
		((#\i) (next u:done (mkrec0 n0 +nan.0))))

  (parse-string-h (dr r ex)
		  ((#\x #\X)
		   (if r (fail) (next parse-string 16 16 ex)))
		  ((#\o #\O)
		   (if r (fail) (next parse-string 8 8 ex)))
		  ((#\b #\B)
		   (if r (fail) (next parse-string 2 2 ex)))
		  ((#\d #\D)
		   (if r (fail) (next parse-string 10 10 ex)))
		  ((#\e #\E)
		   (if ex (fail) (next parse-string dr r 'e)))
		  ((#\i #\I)
		   (if ex (fail) (next parse-string dr r 'i))))

  (parse-string (dr r ex)
		((#\#) (next parse-string-h dr r ex))
		((sign) => sn2 (next u:sign dr #f ex sn2))
		((#\.)
		 (if (fx=? dr 10)
		     (next u:dot dr #f ex +1)
		   (fail)))
		((digit dr) => d
		 (next u:digit+ dr #f ex +1 d)))

  #| end of DEFINE-PARSER |# )


;;;; definition of STRING->NUMBER

(define-syntax string-config
  (syntax-rules (EOF-ERROR GEN-TEST GEN-ARGS FAIL GEN-DELIM-TEST)
    ((_ GEN-ARGS k . rest)
     (k (s n i) . rest))

    ((_ FAIL (s n i) c)
     #f)

    ((_ FAIL (s n i))
     #f)

    ((_ EOF-ERROR (s n i))
     #f)

    ((_ GEN-DELIM-TEST c sk fk)
     #f)

    ((_ GEN-TEST var next fail (s n i) sk fk)
     (let ()
       (define-syntax fail
	 (syntax-rules ()
	   ((_) #f)))
       (if (unsafe.fx= i n)
	   sk
	 (let ((var (unsafe.string-ref s i)))
	   (define-syntax next
	     (syntax-rules ()
	       ((_ who args (... ...))
		(who s n (fx+ i 1) args (... ...)))))
	   fk))))))

(define-string->number-parser string-config (parse-string))

(define string->number
  (case-lambda
   ((s)
    (with-arguments-validation (who)
	((string s))
      (parse-string s (unsafe.string-length s) 0 10 #f #f)))
   ((s r)
    (with-arguments-validation (who)
	((string s)
	 (radix	 r))
      (parse-string s (unsafe.string-length s) 0 r #f #f)))))


;;;; done

)

;;; end of file