(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))

(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; Install the use-package integration for Elpaca.
;; Do not call (require 'elpaca-use-package) here; install it via Elpaca
;; itself and only then enable the integration mode.
(elpaca elpaca-use-package
  (elpaca-use-package-mode))

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
  :ensure t
  :demand t
  :init
  (setq which-key-idle-delay 0.2
        which-key-prefix-prefix "◦ ")
  :config
  (which-key-mode 1)
  (which-key-add-key-based-replacements
    "<leader>" "Leader"
    "<leader>n" "Org Roam"
    "<leader>nf" "Find node"
    "<leader>nc" "Capture"
    "<leader>ni" "Insert node"
    "<leader>nl" "Toggle roam buffer"
    "<leader>ng" "Graph"
    "<leader>nd" "Daily note"))

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

;; `compat' is a transitive dependency for Magit, Magit-Section, Org Roam,
;; and related packages; install it early so Elpaca can resolve the chain.
(use-package compat
  :ensure t
  :demand t)

(use-package magit
  :bind (("C-x g" . magit-status))
  :config
  ;; Fetching Gravatar images for the log/revision buffers blocks on the
  ;; network; skip it.
  (setq magit-revision-show-gravatars nil)
  ;; Don't compute/show a diff every time the commit buffer opens; view it
  ;; on demand instead. Cheaper, especially on larger repos.
  (setq magit-commit-show-diff nil))

(use-package nerd-icons
  :ensure t
  :demand t)

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(require 'albin-timeclock)

(use-package org-roam
  :ensure t
  :demand t
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

  ;; Evil leader bindings: define the leader prefix and bind keys under it.
  (evil-set-leader 'normal (kbd "SPC"))
  (evil-set-leader 'motion (kbd "SPC"))
  (evil-define-key 'normal 'global (kbd "<leader>nf") #'org-roam-node-find)
  (evil-define-key 'normal 'global (kbd "<leader>nc") #'org-roam-capture)
  (evil-define-key 'normal 'global (kbd "<leader>ni") #'org-roam-node-insert)
  (evil-define-key 'normal 'global (kbd "<leader>nl") #'org-roam-buffer-toggle)
  (evil-define-key 'normal 'global (kbd "<leader>ng") #'org-roam-graph)
  (evil-define-key 'normal 'global (kbd "<leader>nd") #'org-roam-dailies-capture-today)
  (evil-define-key 'motion 'global (kbd "<leader>nf") #'org-roam-node-find)
  (evil-define-key 'motion 'global (kbd "<leader>nc") #'org-roam-capture)
  (evil-define-key 'motion 'global (kbd "<leader>ni") #'org-roam-node-insert)
  (evil-define-key 'motion 'global (kbd "<leader>nl") #'org-roam-buffer-toggle)
  (evil-define-key 'motion 'global (kbd "<leader>ng") #'org-roam-graph)
  (evil-define-key 'motion 'global (kbd "<leader>nd") #'org-roam-dailies-capture-today))
