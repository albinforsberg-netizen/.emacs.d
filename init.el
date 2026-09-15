;;; init.el --- Bootstrap -*- lexical-binding: t; -*-

;; The entire configuration lives in config.org, as a literate program.
;; This file's only job is to tangle it (on first run / after edits) and
;; load the result.

(require 'org)

(org-babel-load-file (expand-file-name "config.org" user-emacs-directory))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
