(require 'package)

(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/"))
      package-archive-priorities
      '(("gnu"    . 3)
        ("nongnu" . 2)
        ("melpa"  . 1)))

(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(require 'use-package)
(setq use-package-always-ensure t
      use-package-verbose nil)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 32 1024 1024) ; 32MB
                  gc-cons-percentage 0.1)))

(use-package evil
  :init
  ;; These must be set before evil loads.
  (setq evil-want-integration t    ; integrate with other built-in packages
        evil-want-keybinding nil   ; leave keybinding setup to evil-collection, if added later
        evil-want-C-u-scroll t     ; C-u scrolls up, vim-style, instead of universal-argument
        evil-want-C-i-jump nil     ; keep TAB usable normally (e.g. in Org)
        evil-undo-system 'undo-redo) ; use Emacs's native undo-redo (28+)
  :config
  (evil-mode 1)

  ;; Escape should quit most transient states, vim-style.
  (define-key evil-normal-state-map (kbd "<escape>") 'keyboard-quit)
  (define-key evil-visual-state-map (kbd "<escape>") 'keyboard-quit)
  (define-key minibuffer-local-map (kbd "<escape>") 'keyboard-quit))

(use-package which-key
  :init
  (setq which-key-idle-delay 0.2)
  :config
  (which-key-mode 1))

;; vc.el shells out to git on its own (e.g. for the mode-line VC segment, or
;; on every file save/visit) *in addition* to whatever Magit does. That's
;; redundant work Magit already covers, and it's costly everywhere but
;; especially so on Windows where each subprocess spawn is slow.
(setq vc-handled-backends (delq 'Git vc-handled-backends))

;; Emacs's default pipe settings badly throttle subprocess I/O on Windows
;; (git writes many small chunks, and the default read delay serializes
;; them). Raising the buffer size and removing the read delay is the
;; single biggest known fix for "Magit feels slow on Windows".
(when (eq system-type 'windows-nt)
  (setq w32-pipe-read-delay 0
        w32-pipe-buffer-size (* 64 1024)))

(use-package magit
  :bind (("C-x g" . magit-status))
  :config
  ;; Fetching Gravatar images for the log/revision buffers blocks on the
  ;; network; skip it.
  (setq magit-revision-show-gravatars nil)
  ;; Don't compute/show a diff every time the commit buffer opens; view it
  ;; on demand instead. Cheaper, especially on larger repos.
  (setq magit-commit-show-diff nil))

(use-package nerd-icons)

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(require 'albin-timeclock)
