;; -*- lexical-binding: t; -*-

;; Entry point for the personal timeclock library. The implementation is
;; split across several files by concern (profiles, session parsing,
;; diary/backup, interactive commands, the transient menu, the mode-line),
;; each providing its own feature; this file just loads them in the order
;; their dependencies require and provides the single feature that the
;; rest of the config asks for via (require 'albin-timeclock).
;;
;;   albin-timeclock-profiles  - active profile + per-profile file paths
;;   albin-timeclock-sessions  - holidays, rounding, timelog parsing, flex
;;   albin-timeclock-diary     - org diary logging + git backup
;;   albin-timeclock-commands  - clock in/out/break/…, reports, CSV export
;;   albin-timeclock-menu      - the C-c t transient menu
;;   albin-timeclock-modeline  - the mode-line segment + refresh timer

(require 'albin-timeclock-profiles)
(require 'albin-timeclock-sessions)
(require 'albin-timeclock-diary)
(require 'albin-timeclock-commands)
(require 'albin-timeclock-menu)
(require 'albin-timeclock-modeline)

(provide 'albin-timeclock)
