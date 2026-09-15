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

;; Don't block startup forever if ELPA is unreachable or slow. If the
;; refresh hangs, we keep going and let `use-package`/`package-install`
;; retry later on demand instead.
(when (null package-archive-contents)
  (condition-case err
      (with-timeout (15
                     (message "Timed out contacting ELPA; continuing without package refresh."))
        (package-refresh-contents))
    (error
     (message "Package refresh skipped: %s" err))))

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

(use-package org-roam
  :ensure t
  :after org
  :init
  (setq org-roam-v2-ack t
        org-roam-directory (file-truename "~/org-roam")
        org-roam-completion-everywhere t
        org-roam-capture-templates
        '(("d" "default" plain
           "%?\n\n%a"
           :if-new (file+head "%<%Y-%m-%d>-%<%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: \n")
           :unnarrowed t)))
  :bind ("C-c n f" . org-roam-node-find)
  :bind ("C-c n i" . org-roam-node-insert)
  :bind ("C-c n c" . org-roam-capture)
  :bind ("C-c n l" . org-roam-buffer-toggle)
  :bind ("C-c n g" . org-roam-graph)
  :bind ("C-c n d" . org-roam-dailies-capture-today)
  :config
  (unless (file-directory-p org-roam-directory)
    (make-directory org-roam-directory t))
  (org-roam-db-autosync-mode)

  ;; Evil leader bindings for quick access in normal/motion/visual modes.
  (evil-define-key 'normal 'global (kbd "SPC n f") #'org-roam-node-find)
  (evil-define-key 'normal 'global (kbd "SPC n c") #'org-roam-capture)
  (evil-define-key 'normal 'global (kbd "SPC n i") #'org-roam-node-insert)
  (evil-define-key 'normal 'global (kbd "SPC n l") #'org-roam-buffer-toggle)
  (evil-define-key 'normal 'global (kbd "SPC n g") #'org-roam-graph)
  (evil-define-key 'normal 'global (kbd "SPC n d") #'org-roam-dailies-capture-today)
  (evil-define-key 'motion 'global (kbd "SPC n f") #'org-roam-node-find)
  (evil-define-key 'motion 'global (kbd "SPC n c") #'org-roam-capture)
  (evil-define-key 'motion 'global (kbd "SPC n i") #'org-roam-node-insert)
  (evil-define-key 'motion 'global (kbd "SPC n l") #'org-roam-buffer-toggle)
  (evil-define-key 'motion 'global (kbd "SPC n g") #'org-roam-graph)
  (evil-define-key 'motion 'global (kbd "SPC n d") #'org-roam-dailies-capture-today))
