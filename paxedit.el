;;; paxedit.el --- Structured, Context Driven LISP Editing and Refactoring

;; Copyright 2014 Mustafa Shameem

;; Author: Mustafa Shameem
;; Maintainer: Mustafa Shameem
;; URL: https://github.com/promethial/paxedit
;; Created: November 2, 2014
;; Version: 1.0.0
;; Keywords: lisp, refactoring, context
;; Package-Requires: ((cl-lib "0.5") (paredit "23"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;; Structured, Context Driven LISP Editing and Refactoring
;;;
;;; For documentation refer to https://github.com/promethial/paxedit

;;; Code:
(require 'cl-lib)
(require 'paredit)

;;; User Customizable Options

(defgroup paxedit nil
  "Structured, Context Driven LISP Editing and Refactoring"
  :group 'languages)

(defcustom paxedit-alignment-cleanup t
  "Option enables or disables SEXP alignment."
  :group 'paxedit
  :type 'boolean)

(defcustom paxedit-whitespace-cleanup t
  "Option enables or disables whitespace formatting."
  :group 'paxedit
  :type 'boolean)

(defcustom paxedit-sexp-delimiters '(?,
                                     ?@
                                     ?~
                                     ?'
                                     ?`)
  "Delimiters considered part of a SEXP in the context of macros."
  :group 'paxedit
  :type '(repeat character))

(defcustom paxedit-implicit-functions-elisp '((setq . (1 2))
                                              (setf . (1 2))
                                              (setq-default . (1 2))
                                              (defcustom . (4 2))
                                              (paxedit-new . (1 2))
                                              (paxedit-cnew . (1 2))
                                              (paxedit-cond . (1 2))
                                              (paxedit-put . (2 2)))
  "Implicit functions in ELISP."
  :group 'paxedit
  :type '(alist :key-type symbol :value-type (list integer integer)))

(defcustom paxedit-implicit-functions-clojure '((cond . (1 2)))
  "Implicit functions in Clojure."
  :group 'paxedit
  :type '(alist :key-type symbol :value-type (list integer integer)))

(defcustom paxedit-implicit-structures-clojure '((?\{ . (0 2)))
  "Implicit structures in Clojure."
  :group 'paxedit
  :type '(alist :key-type character :value-type (list integer integer)))

(defcustom paxedit-invert-symbol-clojure '((true false nil))
  "Clojure symbols that can be inverted."
  :group 'paxedit
  :type '(alist :key-type symbol :value-type symbol))

(defcustom paxedit-invert-symbol-elisp '((t nil)
                                         (when unless)
                                         (< > >= <=)
                                         (equal eq =)
                                         (or and))
  "ELISP symbols that can be inverted."
  :group 'paxedit
  :type '(alist :key-type symbol :value-type symbol))

;;; User Messages

(defcustom paxedit-message-nothing-found "Nothing found to swap with."
  "Message to user when nothing found to swap with during refactor."
  :group 'paxedit
  :type 'string)

(defcustom paxedit-message-kill "Nothing found to kill in this context."
  "Message to user when nothing found to kill."
  :group 'paxedit
  :type 'string)

(defcustom paxedit-message-delete "Nothing found to delete in this context."
  "Message to user when nothing found to delete."
  :group 'paxedit
  :type 'string)

(defcustom paxedit-message-copy "Nothing found to copy in this context."
  "Message to user when nothing found to copy."
  :group 'paxedit
  :type 'string)

(defvar paxedit-sexp-implicit-functions nil
  "Internal implict functions.")

(defvar paxedit-sexp-implicit-structures nil
  "Internal implicit structure.")

;;; Default Hooks

(add-hook 'emacs-lisp-mode-hook
          (function (lambda () (setf paxedit-sexp-implicit-functions paxedit-implicit-functions-elisp))))

(add-hook 'clojure-mode-hook
          (function (lambda () (setf paxedit-sexp-implicit-functions paxedit-implicit-functions-clojure
                                paxedit-sexp-implicit-structures paxedit-implicit-structures-clojure))))

;;; Paxedit Defaults

(defvar paxedit-number-regex "[+-]?[0-9_,]+\.?[0-9]*"
  "Regex to extract numbers.")

(defvar paxedit-sexp-boundary-delimiters '(?\(
                                           ?\)
                                           ?\[
                                           ?\]
                                           ?\"
                                           ?\{
                                           ?\})
  "Delimiters that designate the boundary of a SEXP.")

(defvar paxedit-general-whitespace '(?\s
                                     ?\t)
  "White space.")

(defvar paxedit-general-newline '(?\n
                                  ?\r)
  "New line.")

(defvar paxedit-language-whitespace (append paxedit-general-whitespace
                                            paxedit-general-newline
                                            '(?,))
  "Characters considering whitespace by the language.")

(defvar paxedit-symbol-separator (append paxedit-language-whitespace paxedit-sexp-boundary-delimiters)
  "Characters indicating symbol boundary.")

(defvar paxedit-sexp-implicit-structures nil
  "SEXPS with implicit structure.")

(defvar paxedit-sexp-implicit-functions nil
  "Functions & macros with implicit SEXP structure.")

(defvar paxedit-sexp-delimiters-regex (concat paxedit-sexp-delimiters)
  "Delimiters combined into a regex")

(defvar paxedit-symbol-separator-regex (concat paxedit-symbol-separator)
  "Separators that indicate symbol boundary")

(defvar paxedit-cursor-preserve-random "**$$**$$"
  "Unique string to allow preservation of cursor position")

;;; MS Library

;;; Macros

(eval-and-compile
  (defun paxedit-function-build-body (&optional comment body expression-to-wrap-around-body)
    "Builds the comment and body section of a defun with the option of wrapping a expression around the body (e.g. (expression-to-wrap-around-body body)).
comment - expression
body - expected to be a list
expression-to-wrap-around-body - expected to be a list"
    (cond
     ((and (stringp comment) body) (list comment (append expression-to-wrap-around-body body)))
     ((and comment (not body)) (list (append expression-to-wrap-around-body (list comment))))
     ((and (not (stringp comment)) body) (list (append expression-to-wrap-around-body (list comment) body)))))
  (defun paxedit-thread-function (x form)
    "Allows threading of functions enclosed in parenthesis or just specified as symbols.
e.g. FORM (message) is the same as FORM message"
    (if (listp form)
        (append form (list x))
      (list form x))))

(defmacro paxedit->> (x form &rest forms)
  "Clojure like thread last macro."
  (setq forms (append (list x) (list form) forms))
  (let ((result (pop forms)))
    (dolist (lform forms result)
      (setq result (paxedit-thread-function result lform)))))

(defmacro defun-paxedit-excursion (function-name arguments &optional document-string &rest body)
  "Wraps the body with the S-EXP save-excursion."
  (let ((body (paxedit-function-build-body document-string
                                           body
                                           '(save-excursion))))
    `(defun ,function-name ,arguments
       ,@body)))

(defmacro paxedit-nif (test-form greater zero less)
  `(cl-case (signum ,test-form)
     (1 ,greater)
     (0 ,zero)
     (-1 ,less)))

(defmacro paxedit-aif (test-form then-form &optional else-form)
  "Anaphoric if expression."
  (declare (indent 2))
  `(let ((it ,test-form))
     (if it ,then-form ,else-form)))

(defmacro paxedit-awhen (test-form &rest then-forms)
  "Anaphoric when expression."
  (declare (indent 1))
  `(paxedit-aif ,test-form
       (progn ,@then-forms)))

;;; General Functions

(defun paxedit-end-of-buffer? ()
  "Indicates if at the end of the actual or restricted buffer."
  (= (point) (point-max)))

(defun paxedit-start-of-buffer? ()
  "Indicates if at the start of the actual or restricted buffer."
  (= (point) (point-min)))

(defun paxedit-line-beginning? ()
  "Indicates if at beginning of line."
  (= (point) (line-beginning-position)))

(defun paxedit-line-end? ()
  "Indicates if at end of line."
  (= (point) (line-end-position)))

(defun paxedit-nth-satisfies (list condition)
  "Apply the function CONDITION to each element of the LIST until it evaluates to true or the LIST is exhausted. If the CONDITION evaluates to true return the index position of the element that satisfies CONDITION."
  (let ((i 0)
        (return nil))
    (while list
      (if (funcall condition (cl-first list))
          (setf list nil
                return i)
        (setf list (cl-rest list))
        (cl-incf i)))
    return))

(defun paxedit-partition (n list)
  "Returns a new list with the items in LIST grouped into N-sized sublists. If there are not enough items to make the last group N-sized, those items are discarded."
  (cl-loop
   while list
   collect (cl-subseq list 0 n)
   do (setf list (nthcdr n list))))

(defun paxedit-convert-to-string (var)
  "Convert VAR to string."
  (cond
   ((stringp var) var)
   ((numberp var) (number-to-string var))
   ((characterp var) (char-to-string var))
   ((symbolp var) (symbol-name var))))

(defun paxedit-str (&rest vars)
  "If only one value set for VARS, then convert to string and return. If multiple VARS set convert each of the VARS to string and concatenate."
  (mapconcat 'paxedit-convert-to-string vars ""))

(defun paxedit-substring-from-region (string region)
  "Get substring specified by region."
  (substring string (cl-first region) (cl-rest region)))

(defun paxedit-regex-string-region (regex string &optional start)
  "Returns the region of the substring in STRING that statisfies REGEX."
  (paxedit-awhen (string-match regex string start)
    (cons it (match-end 0))))

(defun paxedit-regex-string (regex string &optional start)
  "Returns the first substring in STRING that statisfies REGEX."
  (paxedit-awhen (paxedit-regex-string-region regex string start)
    (paxedit-substring-from-region string it)))

(defun paxedit-regex-match? (regex &rest strings)
  "Verifies all STRINGS match the REGEX."
  (cl-every (lambda (x) (string-match regex x)) strings))

(defun paxedit-create (&optional test size)
  "Create a hash table of default size 65 which uses the equal operator for testing, when TEST and SIZE parameters are not set."
  (make-hash-table :test (or test 'equal)
                   :size (or size 65)))

(defun paxedit-put (hash-map &rest key-values)
  "Put implicit key value pairs in HASH-MAP.
  e.g. (paxedit-put my-hashmap
               :one 1
               :two 2)"
  (mapc (lambda (x) (puthash (cl-first x) (cl-second x) hash-map))
        (paxedit-partition 2 key-values))
  hash-map)

(defun paxedit-get (table key &optional default)
  "Get the value from the hash table using the KEY."
  (gethash key table default))

(defun paxedit-new (&rest key-values)
  "Create hash table with default size (65) and which uses equal operator for comparison. KEY-VALUES are implicit key value pairs which get added to the newly created hash table."
  (apply 'paxedit-put (cons (paxedit-create) key-values)))

(defun paxedit-cnew (&rest key-values)
  "Space efficient version of paxedit-new. Create hash table with same size as number of key value pairs provided and which uses equal operator for comparison. KEY-VALUES are implicit key value pairs which get added to the newly created hash table."
  (apply 'paxedit-put (cons (paxedit-create 'equal (length (paxedit-partition 2 key-values))) key-values)))

(defun paxedit-contains? (hash-map &rest keys)
  "Returns true if all the keys supplied exist in HASH-MAP, else nil."
  (let ((gsym (make-symbol "DNE")))
    ;; Use uninterned symbol to prevent unexpected results when user specifies DNE symbol as value in map
    (cl-every (lambda (k) (not (equal (paxedit-get hash-map k gsym) gsym))) keys)))

(defun paxedit-contains-some? (hash-map &rest keys)
  "Returns true if at least one of the keys supplied exist in HASH-MAP, else nil."
  (let ((gsym (make-symbol "DNE")))
    ;; Use uninterned symbol to prevent unexpected results when user specifies DNE symbol as value in map
    (cl-some (lambda (k) (not (equal (paxedit-get hash-map k gsym) gsym))) keys)))

;;; Macros & Helper Functions

(defmacro defun-paxedit-region (function-name arguments &optional document-string &rest body)
  "Builds a function that requires a REGION argument and allows the user to specify other arguments. The body of the function is wrapped with RSTART and REND of the REGION supplied."
  (let ((body (paxedit-function-build-body document-string
                                           body
                                           '(let ((rstart (cl-first region))
                                                  (rend (cl-rest region)))))))
    `(defun ,function-name ,(cons 'region arguments)
       ,@body)))

;;; Region functions
;;; Region refers to an alist containing (REGION-START-POINT . REGION-END-POINT)

(defun-paxedit-region paxedit-region-valid? ()
  "Return REGION if it has valid dimensions, else if not valid return nil."
  (and (<= 1 rstart)
       (<= rstart rend)
       region))

(defun-paxedit-region paxedit-region-length ()
  "Return REGION's length."
  (- rend rstart))

(defun-paxedit-region paxedit-region-contains-point (point)
  "Verify POINT is bounded by REGION. POINT ∈ [START, END]."
  (and (>= point rstart)
       (<= point rend)))

(defun-paxedit-region paxedit-region-contains-point-exclude-boundary (point)
  "Verify POINT is bounded by REGION. POINT ∈ (START, END)."
  (and (> point rstart)
       (< point rend)))

(defun-paxedit-region paxedit-region-contains-current-point ()
  "Verify cursor's (or current point's) location is bounded by REGION. Cursor ∈ [START, END]."
  (paxedit-region-contains-point region (point)))

(defun paxedit-region-contains (region1 region2)
  "Verify REGION2 is bounded by REGION1."
  (and (paxedit-region-contains-point region1 (cl-first region2))
       (paxedit-region-contains-point region1 (cl-rest region2))))

(defun paxedit-region-content? (region)
  "Verify REGION has valid dimensions and a size large enough to accommodate content (size larger than 0)."
  (and (paxedit-region-valid? region)
       (> (paxedit-region-length region) 0)
       region))

(defun-paxedit-region paxedit-region-string ()
  "Return REGION's content as string."
  (when region
    (buffer-substring rstart rend)))

(defun-paxedit-region paxedit-region-kill ()
  "Kill REGION. If successful return t else nil."
  (ignore-errors (kill-region rstart rend) t))

(defun-paxedit-region paxedit-region-copy  ()
  "Copy REGION. If successful return t else nil."
  (ignore-errors (copy-region-as-kill rstart rend) t))

(defun-paxedit-region paxedit-region-delete ()
  "Delete REGION. If successful return t else nil."
  (ignore-errors (delete-region rstart rend) t))

(defun-paxedit-region paxedit-region-modify (func)
  "Replace the content of REGION with the result of applying FUNC to the string content of REGION. This function makes no guarantee of preserving the cursor when the REGION being modified contains the cursor.
e.g.
---------- Buffer: foo ----------
we hold these truths
---------- Buffer: foo ----------
 (paxedit-region-modify '(9 . 21)    ; This region will be capitalized
                        (lambda (region-string) (capitalize region-string)))
 ⇒ nil
---------- Buffer: foo ----------
we hold These Truths
---------- Buffer: foo ----------"
  (paxedit-awhen (paxedit-region-string region)
    (paxedit-region-delete region)
    (save-excursion (goto-char rstart)
                    (insert (funcall func it)))))

(defun paxedit-preserve-place ()
  "Insert a unique string to preserve the current cursor position."
  (insert paxedit-cursor-preserve-random))

(defun paxedit-search-replace-random ()
  "Remove the random inserted string."
  (ignore-errors (when (search-forward paxedit-cursor-preserve-random nil t)
                   (replace-match "")
                   t)))

(defun paxedit-restore-place (&optional start-search)
  "Replace unique cursor preservation string with cursor."
  (unless (progn (goto-char (- (point) (or start-search 1000)))
                 (paxedit-search-replace-random))
    (goto-char (point-min))
    (paxedit-search-replace-random)))

(defun-paxedit-region paxedit-region-inc (inc)
  "Update the dimensions of the REGION to reflect the random string."
  (cons rstart (+ rend inc)))

(defmacro paxedit-cursor (region &rest body)
  "Preserve the cursor location while making edits to the REGION."
  `(let ((region (and ,region (paxedit-region-inc ,region (length paxedit-cursor-preserve-random)))))
     (paxedit-preserve-place)
     ,@body
     (paxedit-restore-place)))

(defun paxedit-swap-regions (region1 region2 &optional leave-markers)
  "Transpose REGION1 and REGION2."
  (transpose-regions (cl-first region1)
                     (cl-rest region1)
                     (cl-first region2)
                     (cl-rest region2)
                     leave-markers))

(defun paxedit-current-line-region ()
  "Return region of current line."
  (cons (line-beginning-position)
        (line-end-position)))

(defun paxedit-whitespace-to-side? (direction &optional delimiters)
  "If there is exclusively white-space and or DELIMITERS (which is a string) to the left point until the start of the line, or if there is exclusively white-space to the right of the point until the end of the line return true."
  (paxedit-regex-match? (if delimiters
                            (concat "^" (regexp-opt-charset (append paxedit-general-whitespace
                                                                    paxedit-sexp-boundary-delimiters))
                                    "+$")
                          (concat "^[" paxedit-general-whitespace "]+$"))
                        (funcall 'paxedit-region-string
                                 (if (equal direction :right)
                                     (cons (point) (line-end-position))
                                   (cons (line-beginning-position) (point))))))

(defun paxedit-region-dimension ()
  "Function used for debugging purposes to confirm if region generated is what is expected"
  (interactive)
  (message (format "(%d . %d)"
                   (region-beginning)
                   (region-end))))

;;; Paxedit Interface
;;; General Notes
;;; -!- represents the insertion point in Emacs

;;; SEXP Manipulation Facade - By default uses Paredit, but Smartparens or other tools can be substituted

(defun paxedit-sexp-move-to-core-start (&optional n)
  "Move point to the SEXP start and return cursor position, and if no SEXP is found return nil.
e.g. (message -!- \"hello\") --> -!-(message \"hello\")"
  (ignore-errors (paredit-backward-up n)
                 (point)))

(defun paxedit-sexp-forward (&optional n)
  "Move point from 'core start' to the end of the SEXP and return cursor position, and if unable to do so return nil."
  (ignore-errors (paredit-forward n)
                 (point)))

(defun paxedit-sexp-backward (&optional n)
  "Move from end of the SEXP to the start of the SEXP."
  (ignore-errors (paredit-backward n)
                 (point)))

;;; SEXP Manipulators

(defun paxedit-sexp-move-to-start ()
  "Move the point from 'core start' to true start of SEXP to include modifiers which in ELISP for
example include ' ` , @
e.g. '-!-(message \"hello\") --> -!-'(message \"hello\")"
  (skip-chars-backward paxedit-sexp-delimiters-regex))

(defun paxedit-sexp-core-move-istart ()
  "Move to the first symbol inside the SEXP."
  (cl-incf (point))
  (skip-chars-forward (concat paxedit-language-whitespace)))

(defun-paxedit-excursion paxedit-sexp-core-get-end-point ()
  "Under the condition point is at core start of the SEXP, get the end position of the SEXP."
  (paxedit-sexp-forward)
  (point))

(defun-paxedit-excursion paxedit-sexp-core-get-start-point ()
  "Under the condition point is at core start of the SEXP, get the true start of the SEXP which includes ', @, etc."
  (paxedit-sexp-move-to-start)
  (point))

(defun-paxedit-excursion paxedit-sexp-core-get-functional-symbol ()
  "Return the symbol in the functional position under the condition cursor point is at SEXP core start."
  (paxedit-sexp-core-move-istart) ; Account for case where there is extra whitespace in front of functional symbol
  (paxedit-awhen (paxedit-get-current-symbol)     ; If there is a symbol in the functional position intern and return
    (intern it)))

(defun-paxedit-excursion paxedit-sexp-parent-function-symbol ()
  "Return function symbol of the parent SEXP."
  (when (paxedit-sexp-move-to-core-start 2)
    (paxedit-sexp-core-get-functional-symbol)))

(defun-paxedit-excursion paxedit-sexp-function-symbol ()
  "Return function symbol of current SEXP."
  (when (paxedit-sexp-move-to-core-start 1)
    (paxedit-sexp-core-get-functional-symbol)))

(defun-paxedit-excursion paxedit-sexp-core-region ()
  "Return core SEXP region."
  (paxedit-awhen (paxedit-sexp-move-to-core-start)
    (cons it (paxedit-sexp-core-get-end-point))))

(defun-paxedit-excursion paxedit-sexp-region (&optional n)
  "Return region of current SEXP."
  (paxedit-awhen (paxedit-sexp-move-to-core-start n)
    (cons (paxedit-sexp-core-get-start-point)
          (paxedit-sexp-core-get-end-point))))

(defun paxedit-sexp-core-get-type ()
  "Return SEXP start symbol. e.g. (, \", {, [."
  (char-after (point)))

(defun-paxedit-excursion paxedit-sexp-get-type ()
  "Return char that represents the type of the current SEXP (, \", [, etc."
  (when (paxedit-sexp-move-to-core-start)
    (paxedit-sexp-core-get-type)))

(defun paxedit-reindent-defun ()
  "Paxedit reindent expression."
  (when paxedit-alignment-cleanup
    (paredit-reindent-defun)))

;;; Context Generation

(defun paxedit-context-generate (&optional direction n)
  "Return hashmap with initial context data including DIRECTION, start point, SEXP start point, SEXP end point, and other properties specified by paxedit-sexp-current-properties"
  (paxedit->> (paxedit-new :point (point)
                           :iterations n
                           :direction direction
                           :message "No action found for this context.")
              (paxedit-sexp-current-properties)
              (paxedit-implicit-sexp-properties)))

(defun-paxedit-excursion paxedit-sexp-current-properties (property-map &optional n)
  "Return hashmap with properties of current SEXP.
The following properties of the SEXP are stored (if no SEXP is found, no values are stored in the property-map and it is returned as is without modification):
:region region - including special modifiers `,', and @ for ELISP for example
:region-core - region not including modifiers
:function-symbol - symbol in the functional position
:sexp-type - type of the current SEXP (, \", [, etc.
:sexp-istart - point where the first symbol is located in the SEXP"
  (when (paxedit-sexp-move-to-core-start n)
    (let ((end (paxedit-sexp-core-get-end-point)))
      (paxedit-put property-map
                   :region (cons (paxedit-sexp-core-get-start-point) end)
                   :region-core (cons (point) end)
                   :function-symbol (paxedit-sexp-core-get-functional-symbol)
                   :sexp-type (paxedit-sexp-core-get-type)
                   :sexp-istart (progn (paxedit-sexp-core-move-istart)
                                       (point)))))
  property-map)

(defun paxedit-implicit-sexp-properties (context)
  "Add implicit SEXP properties."
  (when (paxedit-cxt-sexp? context)
    (let ((istructure (assq (paxedit-get context :sexp-type) paxedit-sexp-implicit-structures))
          (ifunction (assq (paxedit-get context :function-symbol) paxedit-sexp-implicit-functions)))
      (cond
       (istructure (paxedit-put context
                                :implicit-structure t
                                :implicit-offset (cl-first (cl-rest istructure))
                                :implicit-size (cl-second (cl-rest istructure))
                                :implicit-dimension (assq (paxedit-get context :sexp-type)
                                                          paxedit-sexp-implicit-structures)
                                :sexp-enum (paxedit-cxt-sexp-enumerate context)))
       (ifunction (paxedit-put context
                               :implicit-function t
                               :implicit-offset (cl-first (cl-rest ifunction))
                               :implicit-size (cl-second (cl-rest ifunction))
                               :implicit-dimension (assq (paxedit-get context :function-symbol)
                                                         paxedit-sexp-implicit-functions)
                               :sexp-enum (paxedit-cxt-sexp-enumerate context)))))
    (when (paxedit-contains? context :implicit-dimension)
      (paxedit-cxt-implicit-gen context)))
  context)

(defun paxedit-cxt-implicit-gen (context)
  "Generate the implicit sexp's shape."
  (let ((subseq-part-code (paxedit-partition (paxedit-get context :implicit-size)
                                             (cl-subseq (paxedit-get context :sexp-enum)
                                                        (paxedit-get context :implicit-offset)))))
    (paxedit-put context
                 :implicit-shape (mapcar (lambda (x) (cons (caar x) (cl-rest (cl-first (cl-rest x)))))
                                         subseq-part-code)
                 :implicit-delete (mapcar (lambda (x) (cons (cl-rest (cl-first x)) (cl-first (cl-second x))))
                                          subseq-part-code))))

(defun-paxedit-excursion paxedit-cxt-sexp-enumerate (context)
  "Return an alist which contains regions (START . END) of every form contained within the parent SEXP."
  (paxedit-awhen (paxedit-cxt-cboundary context)
    (paxedit-cxt-move-istart context)
    (cl-loop do (paxedit-sexp-forward)
             until (= (cl-rest it) (point))
             collect (cons (save-excursion (paxedit-sexp-backward)) (point)))))

;;; Symbol Functions

(defun paxedit-invert-regex (regex)
  "Return the inverse regex character class of the string of characters provided."
  (concat "^" regex))

(defun-paxedit-excursion paxedit-symbol-current-boundary ()
  "Return current symbol's region.
e.g. some-function-name, 123, 12_234."
  (let* ((non-separators (paxedit-invert-regex paxedit-symbol-separator-regex))
         (first-point (progn (skip-chars-backward non-separators)
                             (point))))
    (skip-chars-forward non-separators)
    (paxedit-region-content? (cons first-point (point)))))

(defun paxedit-get-current-symbol ()
  "Return the symbol the cursor is on or next to. If no symbol is found return nil."
  (paxedit-awhen (paxedit-symbol-current-boundary)
    (buffer-substring (cl-first it) (cl-rest it))))

(defun paxedit-move-to-symbol (forwardp)
  "Move backward or forward a symbol."
  (if forwardp
      (progn (paxedit-goto-end-of-symbol)
             (skip-chars-forward paxedit-symbol-separator-regex))
    (paxedit-goto-start-of-symbol)
    (skip-chars-backward paxedit-symbol-separator-regex)))

(defun paxedit-symbol-find (forwardp)
  "Find the next or previous symbol (if it exists)."
  (if (paxedit-symbol-current-boundary)
      nil
    (let ((original-position (point)))
      (funcall (if forwardp
                   'skip-chars-forward
                 'skip-chars-backward)
               paxedit-symbol-separator-regex))))

(defun paxedit-symbol-cursor-within? ()
  "Return true if the cursors is within the symbol, and not at the left or right boundary of the symbol."
  (paxedit-awhen (paxedit-symbol-current-boundary)
    (when (paxedit-region-contains-point-exclude-boundary it (point))
      it)))

;;; Comment Functions

(defun paxedit-comment-valid? ()
  "Verify cursor is at start of a valid comment."
  (and (not (paxedit-line-end?))
       (equal ?\; (char-after))
       (or (paxedit-line-beginning?)
           (and (not (equal ?\\ (char-before)))
                (not (equal ?? (char-before)))))
       (not (equal ?\" (paxedit-sexp-get-type)))))

(defun-paxedit-excursion paxedit-comment-check-context ()
  "Return an alist containing the (start . end) of a comment if it exists, else return nil."
  (let (exit
        (eol (line-end-position)))
    (beginning-of-line)
    (unless (or exit (>= (point) eol))
      (skip-chars-forward "^;" eol)
      (if (paxedit-comment-valid?)
          (setf exit t)
        (cl-incf (point))))
    (when exit
      (cons (point) eol))))

(defun paxedit-comment-move (forwardp)
  "Move to the next comment if FORWARDP is true else move to previous comment. If no comment is found return nil."
  (if forwardp
      (comment-search-forward nil t)
    (comment-search-backward nil t)))

;;; Context Functions

(defun paxedit-cxt-implicit-region (context n)
  "Return the dimension of the nth implicit SEXP."
  (elt (paxedit-get context :implicit-shape) n))

(defun paxedit-cxt-cboundary (context)
  "Return core SEXP boundary region."
  (paxedit-get context :region-core))

(defun paxedit-hash-context-forwardp (context)
  "Verify if going forward."
  (equal :forward (gethash :direction context)))

(defun paxedit-cxt-sexp? (context)
  "Verify if currently on a SEXP."
  (paxedit-contains? context :sexp-type))

(defun paxedit-cxt-implicit-sexp? (context)
  "Verify if there is an implicit SEXP."
  (paxedit-contains-some? context :implicit-function :implicit-structure))

(defun-paxedit-excursion paxedit-cxt-topmost-sexp? (context)
  "Verify if context defined SEXP is topmost expression."
  (when (paxedit-cxt-sexp? context)
    (goto-char (cl-first (paxedit-get context :region)))
    (not (paxedit-sexp-move-to-core-start))))

(defun paxedit-cxt-move-istart (context)
  "Move to the internal start point of the SEXP."
  (goto-char (paxedit-get context :sexp-istart)))

(defun paxedit-cxt-nth-current-implicit-sexp (context)
  "Get the position of the implicit sexp depending on where the cursor is."
  (paxedit-nth-satisfies (paxedit-get context :implicit-shape)
                         (lambda (x) (paxedit-region-contains-point x (point)))))

(defun paxedit-cxt-implicit-get-current-sexp (context)
  "Get the region of the current implicit SEXP."
  (paxedit-awhen (paxedit-nth-satisfies (paxedit-get context :implicit-shape)
                                        (lambda (x) (paxedit-region-contains-point x (point))))
    (elt (paxedit-get context :implicit-shape)
         it)))

;;; Cleanup Functions
;;; SEXP Deletion Cleanup

(defun paxedit-whitespace-clean (&optional clean-to-right?)
  "Clean whitespace to the right or left."
  (let ((empty-region-end (point)))
    (funcall (if clean-to-right?
                 'skip-chars-forward
               'skip-chars-backward)
             (concat paxedit-general-whitespace paxedit-general-newline))
    (paxedit-region-delete (cons (point) empty-region-end))))

(defun paxedit-sexp-removal-cleanup ()
  "Delete empty space left by SEXP deletion."
  ;; Delete empty space to the left of the deleted SEXP
  (paxedit-whitespace-clean)
  ;; Cleaning up whitespace may result in making the parent form unbalanced or result in the commenting of other forms on the same line as the deleted form. The next form handles these two undesirable scenarios.
  (when (and (not (paxedit-line-end?))
             (paxedit-comment-check-context) ; check if inside a comment
             (save-excursion (paxedit-sexp-move-to-core-start)))
    (newline)
    (indent-according-to-mode)))

;;; SEXP Structure & Alignment Cleanup

(defun paxedit-whitespace-delete-left ()
  "Delete all the whitespace on the left side until a non-space character is encountered."
  (interactive)
  (paxedit-whitespace-clean))

(defun paxedit-whitespace-delete-right ()
  "Delete all the whitespace on the right side until a non-space character is encountered."
  (interactive)
  (paxedit-whitespace-clean t))

(defun paxedit-delete-whitespace ()
  "Kill all whitespace to the left and right of the cursor."
  (interactive)
  (paxedit-whitespace-clean t)
  (paxedit-whitespace-clean))

(defun paxedit-untabify-buffer ()
  "Remove all tabs in the buffer."
  (interactive)
  (untabify (point-min) (point-max)))

(defun paxedit-indent-buffer ()
  "Re-indent buffer."
  (interactive)
  (indent-region (point-min) (point-max)))

(defun paxedit-cleanup ()
  "Indent buffer as defined by mode, remove tabs, and delete trialing whitespace."
  (interactive)
  (paxedit-indent-buffer)
  (paxedit-untabify-buffer)
  (delete-trailing-whitespace))

;;; Interactive Functions

;;; Symbol Navigation & Manipulation

(defun paxedit-goto-start-of-symbol ()
  "Go to the start of the current symbol."
  (interactive)
  (goto-char (cl-first (paxedit-symbol-current-boundary))))

(defun paxedit-goto-end-of-symbol ()
  "Go to the end of the current symbol."
  (interactive)
  (goto-char (cl-rest (paxedit-symbol-current-boundary))))

(defun paxedit-symbol-copy ()
  "Copy the symbol the cursor is on or next to."
  (interactive)
  (paxedit-aif (paxedit-symbol-current-boundary)
      (paxedit-region-copy it)
    (message "No symbol found to copy")))

(defun paxedit-symbol-kill ()
  "Kill the symbol the text cursor is next to or in and cleans up the left-over whitespace from kill."
  (interactive)
  (paxedit-aif (paxedit-symbol-current-boundary)
      (progn (paxedit-region-kill it)
             (paxedit-whitespace-clean-context))
    (message "No symbol found to kill")))

(defun paxedit-symbol-change-case ()
  "Change the symbol to all uppercase if any of the symbol characters are lowercase, else lowercase the whole symbol."
  (interactive)
  (paxedit-aif (paxedit-symbol-current-boundary)
      (funcall (if (let ((case-fold-search nil))
                     (string-match-p "[a-z]" (paxedit-region-string it)))
                   'upcase-region
                 'downcase-region)
               (cl-first it)
               (cl-rest it))
    (message "No symbol found to uppercase")))

(defun paxedit-symbol-occur ()
  "Search for symbol the cursor is on or next to in the current buffer with occur."
  (interactive)
  (paxedit-aif (paxedit-symbol-current-boundary)
      (progn (occur (paxedit-region-string it))
             (other-window 1))
    (message "No symbol found to search with")))

(defun paxedit-next-symbol (&optional n)
  "Go to the next symbol."
  (interactive "p")
  (paxedit-symbol-find t)
  (dotimes (_ n)
    (paxedit-move-to-symbol t)))

(defun paxedit-previous-symbol (&optional n)
  "Go to the previous symbol."
  (interactive "p")
  (paxedit-symbol-find nil)
  (dotimes (_ n)
    (paxedit-move-to-symbol nil)))

;;; Comment

(defun paxedit-comment-kill ()
  "Kill the comment if the cursor is on."
  (interactive)
  (paxedit-awhen (paxedit-comment-check-context)
    (when (paxedit-region-contains-point it (point))
      (paxedit-region-kill it)
      (paxedit-whitespace-clean)
      t)))

(defun paxedit-comment-align-all ()
  "Align all the comments from the point of the cursor onwards."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (paxedit-comment-move t)
      (paredit-comment-dwim))))

;;; SEXP

(defun paxedit-sexp-backward-up (n)
  "Go to the start of the containing parent expression."
  (interactive "p")
  (unless (paxedit-sexp-move-to-core-start n)
    (paxedit-sexp-backward n)))

(defun paxedit-sexp-backward-end (&optional n)
  "Go to the end of the containing parent expression."
  (interactive "p")
  (paxedit-sexp-move-to-core-start n)
  (paxedit-sexp-forward))

(defun paxedit-quoted-open-round ()
  "Insert quoted open round."
  (interactive)
  (paredit-open-round)
  (save-excursion
    (cl-decf (point))
    (insert ?')))

(defun paxedit-close-sexp-newline ()
  "Close current round and newline. Faster version of the default paredit close round and newline procedure."
  (interactive)
  (paxedit-sexp-backward-end)
  (paredit-newline))

(defun paxedit-close-sexp-newline-round ()
  "Close the current expression, create a newline, and create a new parenthesis pair."
  (interactive)
  (paxedit-sexp-backward-end)
  (paredit-newline)
  (paredit-open-round))

(defun paxedit-sexp-kill (&optional n)
  "Kill current s-expression and any extraneous white space left over from deletion. If deletion is success returns true else nil."
  (interactive "p")
  (paxedit-awhen (paxedit-sexp-region n)
    (paxedit-region-kill it)
    (paxedit-sexp-removal-cleanup)
    t))

(defun paxedit-whitespace-clean-context ()
  "Clean whitespace with account for special cases. After deletion if there is another expression on the same line indent the expression. If there is no code or end delimiters consolidate with the line above."
  (if (or (paxedit-whitespace-to-side? :right)
          (paxedit-line-end?)
          (paxedit-whitespace-to-side? :right t))
      (paxedit-sexp-removal-cleanup)
    (paredit-reindent-defun)
    t))

(defun paxedit-implicit-sexp-kill (&optional n)
  "Kill the implicit SEXP if present."
  (interactive "p")
  (paxedit-awhen (paxedit-context-generate)
    (when (paxedit-cxt-implicit-sexp? it)
      (let ((nth-isexp (paxedit-nth-satisfies (paxedit-get it :implicit-shape)
                                              (lambda (x) (paxedit-region-contains-point x (point))))))
        (when nth-isexp
          (paxedit-region-kill (elt (paxedit-get it :implicit-shape) nth-isexp))
          (paxedit-whitespace-clean-context)
          t)))))

(defun paxedit-sexp-delete (&optional n)
  "Delete current s-expression and any extraneous white space left over from deletion. If deletion is success returns true else nil."
  (interactive "p")
  (paxedit-awhen (paxedit-sexp-region n)
    (paxedit-region-delete it)
    (paxedit-sexp-removal-cleanup)
    t))

(defun paxedit-sexp-raise ()
  "Raises the expression the cursor is in while perserving the cursor location."
  (interactive)
  (if (paxedit-symbol-cursor-within?)
      (progn (paxedit-cursor (paxedit-symbol-current-boundary)
                             (goto-char (cl-first (paxedit-symbol-current-boundary)))
                             (paredit-raise-sexp))
             (paxedit-reindent-defun))
    (paxedit-aif (paxedit-sexp-core-region)
        (progn (paxedit-cursor it
                               (goto-char (cl-first region))
                               (paredit-raise-sexp))
               (paxedit-reindent-defun))
      (message "No SEXP found to raise."))))

(defun paxedit-wrap-function (function-name region)
  "Wrap FUNCTION-NAME around some REGION."
  (paxedit-cursor region
                  (paxedit-region-modify region (lambda (region-string) (format "(%s %s)" function-name region-string))))
  (paxedit-reindent-defun))

(defun paxedit-wrap-comment ()
  "Wrap a comment macro around the current expression. If the current expression is already wrapped by a comment, then the wrapping comment is removed."
  (interactive)
  (paxedit-awhen (paxedit-sexp-core-region)
    (if (equal 'comment (paxedit-sexp-parent-function-symbol))
        (paxedit-sexp-raise)
      (paxedit-wrap-function "comment" it))))

;;; Macros

(defmacro paxedit-macroexpand-p (form)
  "Inserts into the buffer and expanded version of FORM."
  `(progn (cl-prettyprint (macroexpand ',form))
          ;; Remove the extra newline introduced by cl-prettyprint
          (delete-char 1)))

(defun paxedit-macro-expand-replace ()
  "Replace the current expression (if there is a macro in the functional position) with its macro expansion."
  (interactive)
  (paxedit-awhen (paxedit-context-generate)
    (if (functionp (paxedit-get it :function-symbol))
        (message "Function found instead of macro. Macro expansion cannot be done.")
      (let* ((sregion (paxedit-get it :region))
             (sexp (paxedit-region-string sregion))
             (cleanup? (not (paxedit-cxt-topmost-sexp? it)))
             original-pos)
        (paxedit-region-delete sregion)
        (setf original-pos (point))
        (when cleanup?
          (paxedit-sexp-removal-cleanup))
        (eval (read (concat "(paxedit-macroexpand-p " sexp ")")))
        (if cleanup?
            (indent-according-to-mode)
          (save-excursion (goto-char original-pos)
                          (delete-char 1)))))))

;;; SEXP Refactoring Context

(defun-paxedit-excursion paxedit-comment-next-region (forwardp)
  "Return the region of the next or previous comment depending on FORWARDP."
  (if forwardp
      (end-of-line)
    (beginning-of-line))
  (when (paxedit-comment-move forwardp)
    (paxedit-comment-check-context)))

(defun-paxedit-excursion paxedit-sexp-next-region (forwardp)
  "Get the region of the next or previous SEXP depending on FORWARDP."
  (if forwardp
      (let ((end-point (progn (paxedit-sexp-forward)
                              (point))))
        (cons (progn (paxedit-sexp-backward)
                     (point))
              end-point))
    (cons (progn (paxedit-sexp-backward)
                 (point))
          (progn (paxedit-sexp-forward)
                 (point)))))

(defun paxedit-swap-if-next (current-region next-region-func forwardp error-message)
  "Swap the CURRENT-REGION with the next or previous region based on what the NEXT-REGION-FUNC generates."
  (paxedit-aif (funcall next-region-func forwardp)
      (paxedit-swap-regions current-region it)
    (error error-message)))

(defun paxedit-context-comment (context)
  "Swap with next or previous comment."
  (paxedit-aif (and context
                    (not (paxedit-cxt-sexp? context))
                    (paxedit-comment-check-context))
      (paxedit-swap-if-next it
                            'paxedit-comment-next-region
                            (equal (paxedit-get context :direction) :forward)
                            "No comment found to switch with.")
    context))

(defun paxedit-context-implicit-sexp (context)
  "Swap with next or previous implicit SEXP."
  (if (and context
           (paxedit-cxt-implicit-sexp? context)
           (not (paxedit-symbol-cursor-within?))
           (paxedit-cxt-nth-current-implicit-sexp context))
      (condition-case nil
          (paxedit-swap-regions (paxedit-cxt-implicit-region context
                                                             (paxedit-cxt-nth-current-implicit-sexp context))
                                (paxedit-cxt-implicit-region context
                                                             (funcall (if (equal (paxedit-get context :direction) :forward)
                                                                          '+
                                                                        '-)
                                                                      (paxedit-cxt-nth-current-implicit-sexp context)
                                                                      1)))
        (error (message paxedit-message-nothing-found) nil))
    context))

(defun paxedit-context-explicit-sexp (context)
  "Swap with previous or next explicit SEXP."
  (when context
    (let ((in-symbol (paxedit-symbol-cursor-within?))
          (forwardp (equal (paxedit-get context :direction) :forward)))
      (if (or (paxedit-cxt-sexp? context) in-symbol)
          (if in-symbol
              (condition-case nil
                  (paxedit-swap-regions in-symbol
                                        (save-excursion
                                          (if forwardp
                                              (paxedit-sexp-forward)
                                            (paxedit-sexp-backward))
                                          (paxedit-sexp-next-region forwardp)))
                (error (message paxedit-message-nothing-found)
                       nil))
            (condition-case nil
                (paxedit-swap-regions (paxedit-get context :region)
                                      (save-excursion
                                        (if forwardp
                                            (goto-char (cl-rest (paxedit-get context :region-core)))
                                          (goto-char (cl-first (paxedit-get context :region))))
                                        (paxedit-sexp-next-region forwardp)))
              (error (message paxedit-message-nothing-found)
                     nil)))
        context))))

(defun paxedit-context-default (context)
  "If context is detected as non-nil, then display a message stating no context was found."
  (when context
    (message (gethash :message context))))

(defun paxedit-implicit-sexp-up (&optional start)
  "Move to the start of the implicit SEXP if START is true, else go to the end of the implicit SEXP."
  (paxedit-awhen (paxedit-context-generate)
    (paxedit-awhen (and (paxedit-cxt-implicit-sexp? it)
                        (paxedit-cxt-implicit-get-current-sexp it))
      (when (paxedit-region-contains-point-exclude-boundary it (point))
        (goto-char (if start
                       (cl-first it)
                     (cl-rest it)))))))

(defun paxedit-comment-backward (direction)
  "Move to the start or end of the comment."
  (paxedit-awhen (paxedit-comment-check-context)
    (goto-char (funcall (if (eq direction :start)
                            'cl-first
                          'cl-rest) it))))

(defun paxedit-implicit-backward-up (&optional n)
  "Move to the start of the implicit SEXP."
  (paxedit-implicit-sexp-up t))

(defun paxedit-implicit-backward-down (&optional n)
  "Move to the end of the implicit SEXP."
  (paxedit-implicit-sexp-up nil))

(defun paxedit-sexp-close-statement ()
  "Faster version of the default paredit close round and newline procedure."
  (interactive)
  (paxedit-awhen (paxedit-context-generate)
    (goto-char (cl-rest (paxedit-get it :region)))
    (paredit-newline)
    (pcase (paxedit-get it :sexp-type)
      (?\( (paredit-open-round))
      (?\{ (paredit-open-curly))
      (?\[ (paredit-open-bracket))
      (?\" (paredit-doublequote)))))

(defun paxedit-function-goto-definition ()
  "Split the current window and display the definition of the function."
  (interactive)
  (paxedit-awhen (paxedit-sexp-function-symbol)
    (select-window (split-window-right))
    (find-function it)))

(defun paxedit-sexp-close-newline ()
  "Faster version of the default paredit close round and newline procedure."
  (interactive)
  (paxedit-awhen (paxedit-sexp-region)
    (goto-char (cl-rest it))
    (paredit-newline)))

;;; Context Orchestration

(defun paxedit-context-refactor-sexp (direction n)
  "Generic method to refactor implicit SEXPs, explicit SEXPs, and comments in forward and backward DIRECTION."
  (paxedit->> (paxedit-context-generate direction n)
              (paxedit-context-comment)
              (paxedit-context-implicit-sexp)
              (paxedit-context-explicit-sexp)
              (paxedit-context-default)))

;;; Context Sensitive Start

(defun paxedit-backward-up (&optional n)
  "Move to the start of the explicit expression, implicit expression or comment."
  (interactive "p")
  (dotimes (_ n)
    (or (paxedit-comment-backward :start)
        (paxedit-implicit-backward-up)
        (paxedit-sexp-backward-up 1))))

(defun paxedit-backward-end (&optional n)
  "Move to the end of the explicit expression, implicit expression or comment."
  (interactive "p")
  (dotimes (_ n)
    (or (paxedit-comment-backward :end)
        (paxedit-implicit-backward-down)
        (paxedit-sexp-backward-end))))

(defun paxedit-backward-up-2 (&optional n)
  "Go up expressions by multiples of two."
  (interactive "p")
  (paxedit-backward-up (* 2 n)))

;;; Context Dependent New Statement

(defun paxedit-context-new-statement (&optional n)
  "Create a new SEXP depending on the context."
  (interactive "p")
  (or (paxedit-sexp-close-statement)))

;;; Context Dependent Goto Definition

(defun paxedit-context-goto-definition ()
  "Go to the function definition."
  (interactive)
  (or (paxedit-function-goto-definition)))

;;; Context Dependent Kill, Copy, and Delete

(defun paxedit-kill (&optional n)
  "Kill current explicit expression, implicit expression, or comment. Also cleans up left-over whitespace from kill and corrects indentation."
  (interactive "p")
  (or (paxedit-comment-kill)
      (paxedit-implicit-sexp-kill n)
      (paxedit-sexp-kill n)
      (message paxedit-message-kill)))

(defun paxedit-copy (&optional n)
  "Copy current explicit expression, implicit expression, or comment."
  (interactive "p")
  (cl-letf (((symbol-function 'paxedit-region-kill) #'paxedit-region-copy)
            (paxedit-message-kill paxedit-message-copy))
    (paxedit-kill n)))

(defun paxedit-delete (&optional n)
  "Delete current explicit expression, implicit expression, or comment. Also cleans up the left-over whitespace from deletion and corrects indentation."
  (interactive "p")
  (cl-letf (((symbol-function 'paxedit-region-kill) #'paxedit-region-delete)
            (paxedit-message-kill paxedit-message-delete))
    (paxedit-kill n)))

;;; Context Dependent Transpose

(defun paxedit-transpose-forward (&optional n)
  "Swap the current explicit expression, implicit expression, symbol, or comment forward depending on what the cursor is on and what is available to swap with. This command is very versatile and will do the \"right\" thing in each context."
  (interactive "p")
  (paxedit-context-refactor-sexp :forward n))

(defun paxedit-transpose-backward (&optional n)
  "Swaps the current explicit, implicit expression, symbol, or comment backward depending on what the cursor is on and what is available to swap with. Swaps in the opposite direction of paxedit-transpose-forward."
  (interactive "p")
  (paxedit-context-refactor-sexp :backward n))

(provide 'paxedit)
;;; paxedit.el ends here
