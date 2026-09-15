;;; albin-ide.el --- Universal zero-config setup -*- lexical-binding: t; -*-

;; 1. Inherit shell PATH (ensures Emacs sees node, npm, and global bin directories)
(use-package exec-path-from-shell
  :ensure t
  :config
  (when (memq window-system '(mac ns x pgtk))
    (exec-path-from-shell-initialize)))

;; 2. Install TypeScript mode so .ts/.tsx files derive from prog-mode (Fixes fundamental-mode)
(use-package typescript-mode
  :ensure t
  :mode ("\\.ts\\'" "\\.tsx\\'"))

;; 3. Universal Eglot setup (Auto-starts on all programming files)
(use-package eglot
  :ensure nil ;; Built into Emacs 29+
  :hook (prog-mode . eglot-ensure))

(provide 'albin-lsp)