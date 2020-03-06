;;; bufler-workspace-tabs.el --- Bufler workspace tabs  -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Adam Porter

;; Author: Adam Porter <adam@alphapapa.net>
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This provides a global minor mode that uses the new `tab-bar-mode'
;; and `tab-line-mode' in Emacs 27+ to show Bufler workspaces and
;; buffers, respectively.

;;; Code:

;;;; Requirements

(require 'bufler-workspace)

;;;; Compatibility

;; Since most of this file is defined conditionally, depending on
;; whether `tab-bar' is present, we have to declare several variables
;; and functions to avoid byte-compiler warnings.

(defvar tab-bar-tabs-function)
(defvar tab-bar-close-button)
(defvar tab-bar-close-button-show)
(defvar tab-line-tabs-function)
;; Because the mode isn't necessarily defined.
(defvar bufler-workspace-tabs-mode)
(defvar bufler-workspace-tabs-mode-saved-settings)
(defvar bufler-workspace-tabs-tab-separator)

(declare-function tab-bar-mode "ext:tab-bar" t t)
(declare-function tab-bar--current-tab-index "ext:tab-bar" t t)
(declare-function tab-bar--tab "ext:tab-bar" t t)
(declare-function tab-bar-tabs "ext:tab-bar" t t)
(declare-function global-tab-line-mode "ext:tab-line" t t)
(declare-function tab-line-tabs-window-buffers "ext:tab-line" t t)

(declare-function bufler-workspace-tabs--tab-bar-select-tab "ext:bufler-workspace" t t)
(declare-function bufler-workspace-buffers "ext:bufler-workspace" t t)
(declare-function bufler-workspace-tabs "ext:bufler-workspace" t t)
(declare-function bufler-workspace-tabs-mode "ext:bufler-workspace" t t)

;;;; Functionality

;;;###autoload
(when (require 'tab-bar nil t)

  ;; Only on Emacs 27+.

  ;; FIXME: Maybe these should be autoloaded, but how to do that conditionally?

;;;; Variables

  (defvar bufler-workspace-tabs-mode-saved-settings
    '((tab-bar-close-button . nil) (tab-bar-close-button-show . nil))
    "Settings saved from before `bufler-workspace-tabs-mode' was activated.
Used to restore them when the mode is disabled.")

;;;; Customization

  (defcustom bufler-workspace-tabs-tab-separator " |"
    "String displayed between tabs.
Since there is no built-in separator between tabs, it can be
unclear where one tab ends and the next begins, depending on face
settings.  Normally the tab-close button would indicate where a
tab ends, but our tabs are dynamic, rule-generated workspaces and
aren't closable manually, so we repurpose the
`tab-bar-close-button' as a separator.

This string can be anything, including an image using display
properties.  See the default value of `tab-bar-close-button'."
    :type 'string
    :group 'bufler-workspace)

;;;; Commands

  (define-minor-mode bufler-workspace-tabs-mode
    "Use Bufler workspaces for `tab-bar-mode' and `tab-line-mode'."
    :global t
    (if bufler-workspace-tabs-mode
	(progn
	  ;; Save settings.
	  (cl-loop for (symbol . _value) in bufler-workspace-tabs-mode-saved-settings
		   do (setf (map-elt bufler-workspace-tabs-mode-saved-settings symbol)
			    (symbol-value symbol)))
	  (advice-add 'tab-bar-select-tab :override #'bufler-workspace-tabs--tab-bar-select-tab)
          (setf tab-bar-tabs-function #'bufler-workspace-tabs
                tab-line-tabs-function #'bufler-workspace-buffers)
          (tab-bar-mode 1)
          (global-tab-line-mode 1)
	  ;; NOTE: `tab-bar-mode' adds text properties to `tab-bar-close-button'
	  ;; when it is activated, so we must set it after the mode is activated.
	  (setf tab-bar-close-button bufler-workspace-tabs-tab-separator
		tab-bar-close-button-show t))
      (advice-remove 'tab-bar-select-tab #'bufler-workspace-tabs--tab-bar-select-tab)
      (setf tab-bar-tabs-function #'tab-bar-tabs
            tab-line-tabs-function #'tab-line-tabs-window-buffers)
      ;; Restore settings.
      (cl-loop for (symbol . value) in bufler-workspace-tabs-mode-saved-settings
               do (set symbol value)
               do (setf (map-elt bufler-workspace-tabs-mode-saved-settings symbol) nil))
      (tab-bar-mode -1)
      (global-tab-line-mode -1))
    (force-mode-line-update 'all))

  (defalias 'bufler-tabs-mode #'bufler-workspace-tabs-mode)

  (defun bufler-workspace-tabs--tab-bar-select-tab (&optional arg)
    "Set the frame's workspace to the selected tab's workspace.
ARG is the position of the tab in the tab bar."
    ;; Modeled on/copied from `tab-bar-select-tab'.
    (interactive "P")
    (unless (integerp arg)
      (let ((key (event-basic-type last-command-event)))
        (setq arg (if (and (characterp key) (>= key ?1) (<= key ?9))
                      (- key ?0)
                    1))))
    (let* ((tabs (funcall tab-bar-tabs-function))
           (from-index (tab-bar--current-tab-index tabs))
           (to-index (1- (max 1 (min arg (length tabs))))))
      (unless (eq from-index to-index)
        (let* ((_from-tab (tab-bar--tab))
               (to-tab (nth to-index tabs))
               (workspace-path (alist-get 'path to-tab)))
          (bufler-workspace-frame-set workspace-path)
          (force-mode-line-update 'all)))))

;;;; Functions

  (cl-defun bufler-workspace-tabs (&optional (frame (selected-frame)))
    "Return a list of workspace tabs from FRAME's perspective.
Works as `tab-bar-tabs-function'."
    ;; This is ridiculously complicated.  It seems to all stem from,
    ;; again, that group paths can start with nil, but we need to ignore
    ;; initial nils when displaying paths, but we need to keep the
    ;; initial nil in the actual path.  And then we need to store paths
    ;; as lists, not ever single elements, but putting a list in an
    ;; alist by consing the key onto the beginning causes its value to
    ;; be just the car of the value list, not a list itself (at least,
    ;; when retrieved with `alist-get'), which is very confusing, so we
    ;; use a plist at one point to avoid that.  Anyway, this feels like
    ;; a terrible mess, so in the future we should probably use structs
    ;; for groups, which would probably make this much easier.  I think
    ;; I've spent more time messing with this function than I have on
    ;; the actual grouping logic, which may say more about me than the
    ;; code.
    (with-selected-frame frame
      (cl-labels ((tab-type
		   (path) (if (equal path (frame-parameter nil 'bufler-workspace-path))
			      'current-tab
			    'tab))
		  (path-first ;; CAR, or CADR if CAR is nil.
		   (path) (cl-typecase path
			    (string (list path))
			    (list (if (car path)
				      (list (car path))
				    (list (cadr path))))))
		  (workspace-to-tab
		   (workspace &optional type) (-let* (((&plist :name :path) workspace))
						(list (or type (tab-type path))
						      (cons 'name (car name))
						      (cons 'path path))))
		  (path-to-workspace
		   ;; This gets too complicated.  We need to preserve the real path, but
		   ;; if the first element is nil, we need to ignore that and display
		   ;; the string after the nil.  We sort-of cheat here by using
		   ;; `path-first' in this function.
		   (path) (list :name (path-first path)
				:path path)))
	(let* ((bufler-vc-state nil)
	       (buffer-paths (bufler-group-tree-paths (bufler-buffers)))
	       (group-paths (mapcar #'butlast buffer-paths))
	       (top-level-group-paths (mapcar #'path-first group-paths))
	       (uniq-top-level-group-paths (seq-uniq top-level-group-paths))
	       (workspaces (mapcar #'path-to-workspace uniq-top-level-group-paths))
	       (tabs (mapcar #'workspace-to-tab workspaces)))
	  ;; Add the current workspace if it's not listed (i.e. when the
	  ;; current workspace is not a top-level workspace).
	  (unless (cl-loop with current-path = (frame-parameter nil 'bufler-workspace-path)
			   for tab in tabs
			   for tab-path = (alist-get 'path tab)
			   thereis (equal tab-path current-path))
	    (push (list 'current-tab
			(cons 'name (bufler-format-path (frame-parameter nil 'bufler-workspace-path)))
			(cons 'path (frame-parameter nil 'bufler-workspace-path)))
		  tabs))
	  tabs)))))

;;;; Footer

(provide 'bufler-workspace-tabs)

;;; bufler-workspace-tabs.el ends here
