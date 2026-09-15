;; -*- lexical-binding: t; -*-

;; The mode-line segment showing the active profile, project and elapsed
;; time today, refreshed once a minute.

(require 'timeclock)
(require 'time-date)
(require 'albin-timeclock-profiles)
(require 'albin-timeclock-sessions)

(defvar albin-timeclock-mode-string "")

;; Append directly to the default `mode-line-format' (shared by every
;; buffer that hasn't set its own) rather than going through
;; `global-mode-string': the latter only renders if it's still wired into
;; `mode-line-misc-info' in the active mode-line-format, which is true out
;; of the box but is an indirect dependency this shouldn't have to rely on.
(unless (memq 'albin-timeclock-mode-string (default-value 'mode-line-format))
  (setq-default mode-line-format
                (append (default-value 'mode-line-format)
                        '(albin-timeclock-mode-string))))

(defun albin/timeclock-update-modeline ()
  (let* ((raw (albin/get-timelog-sessions)) (today (format-time-string "%Y-%m-%d")) (hours 0.0) (current-proj nil))
    (dolist (s raw) (when (string= (nth 0 s) today) (setq hours (+ hours (nth 3 s)))))
    (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
      (setq current-proj (nth 2 timeclock-last-event)
            hours (+ hours (/ (float-time (time-subtract (current-time) (nth 1 timeclock-last-event))) 3600.0))))
    (setq albin-timeclock-mode-string
          (concat (propertize (format " %s " albin-timeclock-current-profile) 'face 'font-lock-keyword-face)
                  (if current-proj (propertize (format " [%s]" current-proj) 'face 'success) " [Paused]")
                  (format " %s " (albin/format-hours-to-hm hours))))
    (force-mode-line-update t)))

(defvar albin-timeclock--modeline-timer nil
  "Timer that periodically refreshes the timeclock mode-line segment.")

(when (timerp albin-timeclock--modeline-timer)
  (cancel-timer albin-timeclock--modeline-timer))
(setq albin-timeclock--modeline-timer
      (run-at-time t 60 #'albin/timeclock-update-modeline))

(albin/timeclock-update-modeline)

(provide 'albin-timeclock-modeline)
