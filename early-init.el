;;; early-init.el --- Runs before init.el, package.el, and UI init -*- lexical-binding: t; -*-

;; This file intentionally stays outside the literate config.org: it must
;; execute as early and as fast as possible, before Org is even needed.

;; Raise the GC threshold during startup; config.org restores a sane value
;; once startup is finished.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; We call (package-initialize) ourselves from config.org, once
;; package-archives has been configured.
(setq package-enable-at-startup nil)

;; Avoid a flash of unstyled UI chrome on graphical frames. These are no-ops
;; on a terminal, so this is safe on macOS, Linux and Windows alike.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; Don't let child frames/windows trigger expensive implicit resizes.
(setq frame-inhibit-implied-resize t)
