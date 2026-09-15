;; -*- lexical-binding: t; -*-

;; The interactive commands: clocking in/out/break/resume/change, profile
;; and project management, the holidays popup, daily/weekly reports and
;; CSV export.

(require 'org)
(require 'calendar)
(require 'timeclock)
(require 'time-date)
(require 'parse-time)
(require 'nerd-icons)
(require 'albin-timeclock-profiles)
(require 'albin-timeclock-sessions)
(require 'albin-timeclock-diary)

;; Defined in albin-timeclock-modeline.el; every command below calls this
;; after changing clock state, but the mode-line module requires this file
;; (indirectly, via the menu) rather than the other way around, so a plain
;; `require' here would create a load cycle.
(declare-function albin/timeclock-update-modeline "albin-timeclock-modeline")

(defun albin/swedish-red-days (year)
  "Returns a sorted list of (date-string . holiday-name) for a given YEAR."
  (let* ((easter-abs (albin/calculate-easter year))
         ;; Midsummer Eve: the Friday between June 19-25
         (midsommar-abs
          (let* ((june-19 (calendar-absolute-from-gregorian (list 6 19 year)))
                 (dow (calendar-day-of-week (list 6 19 year))))
            (+ june-19 (% (+ 12 (- dow)) 7))))
         ;; All Saints' Day: the Saturday between Oct 31 - Nov 6
         (alla-helgons-abs
          (let* ((oct-31 (calendar-absolute-from-gregorian (list 10 31 year)))
                 (dow (calendar-day-of-week (list 10 31 year))))
            (+ oct-31 (% (+ 7 (- 6 dow)) 7))))
         ;; Build the list of pairs: (absolute-day . "Name")
         (holiday-alist
          (list
           (cons (calendar-absolute-from-gregorian (list 1 1 year))   "New Year's Day")
           (cons (calendar-absolute-from-gregorian (list 1 6 year))   "Epiphany")
           (cons (- easter-abs 2)                                    "Good Friday")
           (cons easter-abs                                          "Easter Sunday")
           (cons (+ easter-abs 1)                                    "Easter Monday")
           (cons (calendar-absolute-from-gregorian (list 5 1 year))   "May 1st (Labour Day)")
           (cons (+ easter-abs 39)                                   "Ascension Day")
           (cons (+ easter-abs 49)                                   "Pentecost")
           (cons (calendar-absolute-from-gregorian (list 6 6 year))   "National Day")
           (cons midsommar-abs                                       "Midsummer Eve")
           (cons (+ midsommar-abs 1)                                 "Midsummer Day")
           (cons alla-helgons-abs                                    "All Saints' Day")
           (cons (calendar-absolute-from-gregorian (list 12 24 year)) "Christmas Eve")
           (cons (calendar-absolute-from-gregorian (list 12 25 year)) "Christmas Day")
           (cons (calendar-absolute-from-gregorian (list 12 26 year)) "Boxing Day")
           (cons (calendar-absolute-from-gregorian (list 12 31 year)) "New Year's Eve"))))

    ;; Sort by absolute date (car)
    (setq holiday-alist (sort holiday-alist (lambda (a b) (< (car a) (car b)))))

    ;; Convert to (YYYY-MM-DD . "Name")
    (mapcar (lambda (pair)
              (let ((greg (calendar-gregorian-from-absolute (car pair))))
                (cons (format "%04d-%02d-%02d" (nth 2 greg) (nth 0 greg) (nth 1 greg))
                      (cdr pair))))
            holiday-alist)))

(defun albin/timeclock-switch-profile ()
  (interactive)
  (timeclock-reread-log)
  (let ((new-profile (completing-read (format "Switch profile (current: %s): " albin-timeclock-current-profile)
                                      albin-timeclock-profiles nil t nil nil albin-timeclock-current-profile)))
    (unless (string= new-profile albin-timeclock-current-profile)
      (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
        (albin/timeclock-out (format "Auto-clockout (Switched to %s profile)" new-profile)))
      (setq albin-timeclock-current-profile new-profile)
      (albin/save-active-profile)
      (albin/timeclock-update-paths)
      (timeclock-reread-log)
      (setq albin-timeclock-paused-project nil)
      (albin/timeclock-update-modeline)
      (message "🔄 Profile switched to: %s" new-profile))))

(defun albin/timeclock-out (&optional auto-reason)
  (interactive)
  (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
    (let* ((start-time (nth 1 timeclock-last-event))
           (project (nth 2 timeclock-last-event))
           (diff-sec (float-time (time-subtract (current-time) start-time)))
           (duration-hours (/ diff-sec 3600.0))
           (reason (or auto-reason
                       (read-string "Done for now! What did you do under this session? "
                                    nil
                                    'albin-timeclock-task-history
                                    albin-timeclock-pending-reason))))

      (setq reason (if (albin/is-empty reason) "" reason))
      (timeclock-log "o" (if (albin/is-empty reason) nil (substring-no-properties reason)))
      (albin/append-to-diary project reason duration-hours)
      (setq albin-timeclock-pending-reason nil)
      (albin/timeclock-update-modeline)
      ;; Back up after every clock-out, not just on Emacs exit — a crash or
      ;; power loss mid-day would otherwise lose the whole day's work.
      (albin/timeclock-git-backup)
      (when (called-interactively-p 'any)
        (message "⏱️ Clocked out.%s" (if (albin/is-empty reason) "" (format " Task: %s" reason)))))))

(defun albin/timeclock-break ()
  (interactive)
  (if (not (and timeclock-last-event (string= (car timeclock-last-event) "i")))
      (message "You are not clocked in right now!")
    (setq albin-timeclock-paused-project (nth 2 timeclock-last-event))
    (when albin-timeclock-paused-project
      (write-region albin-timeclock-paused-project nil albin-timeclock-paused-file nil 'silent))
    (timeclock-log "o" "---BREAK---")
    (albin/timeclock-update-modeline)
    (message "☕ Clock paused! Project '%s' saved." albin-timeclock-paused-project)))

(defun albin/timeclock-resume ()
  (interactive)
  (when (and (not albin-timeclock-paused-project)
             albin-timeclock-paused-file
             (file-exists-p albin-timeclock-paused-file))
    (with-temp-buffer
      (insert-file-contents albin-timeclock-paused-file)
      (setq albin-timeclock-paused-project (string-trim (buffer-string)))))

  (if (or (albin/is-empty albin-timeclock-paused-project)
          (not (equal (nth 2 timeclock-last-event) "---BREAK---")))
      (message "No valid break found to resume from.")
    (timeclock-log "i" albin-timeclock-paused-project)
    (when (file-exists-p albin-timeclock-paused-file) (delete-file albin-timeclock-paused-file))
    (albin/timeclock-update-modeline)
    (message "▶️ Clock is ticking again on: %s" albin-timeclock-paused-project)
    (setq albin-timeclock-paused-project nil)))

(defun albin/timeclock-in ()
  (interactive)
  (let* ((mapping (albin/load-timeclock-projects))
         (active-projs (delq nil (mapcar (lambda (x) (when (plist-get (cdr x) :active) (car x))) mapping)))
         (suggested-proj (when (derived-mode-p 'org-mode)
                           (or (org-entry-get nil "CATEGORY")
                               (file-name-nondirectory (buffer-file-name)))))
         (selected-proj (completing-read
                         (format "Clock in on project%s: "
                                 (if suggested-proj (format " (suggested: %s)" suggested-proj) ""))
                         active-projs nil nil nil nil suggested-proj)))
    (let* ((props (cdr (assoc selected-proj mapping)))
           (export-name nil))
      (if props
          (setq export-name (plist-get props :export-code))
        (let ((new-code (read-string (format "Enter export code for NEW project '%s' (Enter for name): " selected-proj))))
          (setq export-name (if (albin/is-empty new-code) selected-proj new-code))
          (unless (albin/is-empty selected-proj)
            (setq mapping (assq-delete-all selected-proj mapping))
            (push (cons selected-proj (list :export-code export-name :rounding 0.5 :round-up nil :active t)) mapping)
            (albin/save-timeclock-projects mapping))))
      (setq export-name (substring-no-properties export-name))
      (let* ((suggestions (albin/timeclock-task-suggestions selected-proj))
             (suggested-task
              (when suggestions
                (completing-read (format "Task suggestion for '%s' (RET to skip): " selected-proj)
                                 suggestions nil nil nil
                                 'albin-timeclock-task-history
                                 (car suggestions)))))
        (setq albin-timeclock-pending-reason
              (unless (albin/is-empty suggested-task)
                (substring-no-properties suggested-task))))
      (when (and timeclock-last-event (string= (car timeclock-last-event) "i"))
        (albin/timeclock-out (if (albin/is-empty selected-proj) "" (format "Automatically switched to %s" selected-proj))))
      (setq albin-timeclock-paused-project nil)
      (when (and albin-timeclock-paused-file (file-exists-p albin-timeclock-paused-file)) (delete-file albin-timeclock-paused-file))
      (timeclock-log "i" (if (albin/is-empty export-name) nil export-name))
      (albin/timeclock-update-modeline)
      (message "⏱️ Clocked in%s" (if (albin/is-empty selected-proj) "" (format " on: %s" selected-proj))))))

(defun albin/timeclock-change ()
  (interactive)
  (if (not (and timeclock-last-event (string= (car timeclock-last-event) "i")))
      (call-interactively 'albin/timeclock-in)
    (let* ((old-proj (nth 2 timeclock-last-event))
           (reason (read-string (format "🔄 Switching from '%s'. What did you do until now? " old-proj)))
           (mapping (albin/load-timeclock-projects))
           (active-projs (delq nil (mapcar (lambda (x) (when (plist-get (cdr x) :active) (car x))) mapping)))
           (new-proj (completing-read "Clock in on new project: " active-projs nil nil nil nil nil)))
      (setq reason (if (albin/is-empty reason) "" reason))
      (albin/timeclock-out reason)
      (let* ((props (cdr (assoc new-proj mapping)))
             (export-name (if props (plist-get props :export-code) new-proj)))
        (setq albin-timeclock-paused-project nil)
        (when (and albin-timeclock-paused-file (file-exists-p albin-timeclock-paused-file)) (delete-file albin-timeclock-paused-file))
        (timeclock-log "i" (if (albin/is-empty export-name) nil (substring-no-properties export-name)))
        (albin/timeclock-update-modeline)
        (message "⏱️ Switched to '%s'" new-proj)))))

(defun albin/timeclock-adjust-start (minutes)
  "Adjusts the start time of the current session back by MINUTES minutes."
  (interactive "nOops, forgot to clock in! How many minutes ago did you start? ")
  (if (not (and timeclock-last-event (string= (car timeclock-last-event) "i")))
      (message "⚠️ You must be clocked in to adjust the start time!")
    (let* ((file (or timeclock-file (expand-file-name "timelog" user-emacs-directory)))
           (current-start-time (nth 1 timeclock-last-event))
           (new-start-time (time-subtract current-start-time (seconds-to-time (* minutes 60))))
           (new-time-str (format-time-string "%Y/%m/%d %H:%M:%S" new-start-time))
           (project (nth 2 timeclock-last-event)))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-max))
        (when (bolp) (backward-char 1))
        (beginning-of-line)
        (when (looking-at "^i ")
          (delete-region (point) (line-end-position))
          (insert (format "i %s %s" new-time-str (if project project "")))
          (write-region (point-min) (point-max) file nil 'silent)
          (timeclock-reread-log)
          (albin/timeclock-update-modeline)
          (message "⏪ Time machine activated! Start time moved back by %d minutes." minutes))))))

(defun albin/timeclock-edit-project ()
  "Interactively edit properties of an existing project."
  (interactive)
  (let* ((mapping (albin/load-timeclock-projects))
         (proj-names (mapcar #'car mapping))
         (selected-proj (completing-read "Edit project config: " proj-names nil t)))
    (when selected-proj
      (let* ((props (cdr (assoc selected-proj mapping)))
             (code (read-string (format "Export code (%s): " (plist-get props :export-code)) nil nil (plist-get props :export-code)))
             (rounding-str (completing-read "Rounding resolution: " '("0.5" "0.25" "1.0" "None") nil nil (let ((r (plist-get props :rounding))) (if r (number-to-string r) "None"))))
             (rounding (if (string-match-p "^[0-9.]+$" rounding-str) (string-to-number rounding-str) nil))
             (round-up (if rounding (y-or-n-p "Always round UP? ") nil))
             (active (y-or-n-p "Is project ACTIVE? ")))
        (setq mapping (assq-delete-all selected-proj mapping))
        (push (cons selected-proj (list :export-code code :rounding rounding :round-up round-up :active active)) mapping)
        (albin/save-timeclock-projects mapping)
        (message "✅ Project '%s' updated!" selected-proj)))))

(defun albin/timeclock-show-red-days ()
  "Shows the year's public holidays in a neat popup buffer."
  (interactive)
  (let* ((year (string-to-number (format-time-string "%Y")))
         (holiday-data (albin/swedish-red-days year))
         (buf-name "*Public Holidays*"))
    (with-current-buffer (get-buffer-create buf-name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format " 🔴 SWEDISH PUBLIC HOLIDAYS %d\n" year) 'face 'font-lock-type-face))
        (insert " ------------------------------------------------------------\n")
        (dolist (item holiday-data)
          (let* ((date (car item))
                 (name (cdr item))
                 (y (string-to-number (substring date 0 4)))
                 (m (string-to-number (substring date 5 7)))
                 (d (string-to-number (substring date 8 10)))
                 (time (encode-time 0 0 0 d m y))
                 (dow (string-to-number (format-time-string "%u" time)))
                 (dow-name (nth (1- dow) '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))))
            (insert (format "  %s  %s  %s\n"
                            (propertize date 'face 'font-lock-keyword-face)
                            (propertize dow-name 'face 'font-lock-comment-face)
                            (propertize name 'face 'font-lock-string-face)))))
        (insert " ------------------------------------------------------------\n")
        (insert (propertize "\n (These days contribute 0h expected time in the flex calculation)\n" 'face 'font-lock-doc-face))
        (insert (propertize " Press 'q' to close.\n" 'face 'font-lock-comment-face))
        (special-mode)
        (goto-char (point-min))))
    (display-buffer buf-name '((display-buffer-reuse-window display-buffer-pop-up-window)
                               (window-height . fit-window-to-buffer)))))

(defun albin/timeclock-show-flex ()
  (interactive)
  (let* ((sessions (albin/get-timelog-sessions))
         (flex-data (albin/calculate-flex sessions))
         (total-flex (nth 0 flex-data)))
    (message "%s  Total flextime (%s): %s%.2f hours" (nerd-icons-faicon "nf-fa-bar_chart") albin-timeclock-current-profile (if (> total-flex 0) "+" "") total-flex)))

(defun albin/timeclock-daily-summary (&optional date)
  "Generate a detailed report for DATE (defaults to today)."
  (interactive)
  (let* ((target-date (or date (org-read-date nil nil nil "Daily summary for date: ")))
         (raw-sessions (albin/get-timelog-sessions))
         (merged-sessions (albin/prepare-report-sessions raw-sessions))
         (rounded-sessions (car (albin/apply-time-carry merged-sessions)))
         (sessions '())
         (total-raw 0.0)
         (total-rounded 0.0)
         (buf-name (format "*Day Summary: %s (%s)*" albin-timeclock-current-profile target-date)))
    (dolist (s merged-sessions)
      (when (string= (nth 0 s) target-date)
        (setq total-raw (+ total-raw (nth 3 s)))))
    (dolist (s rounded-sessions)
      (when (string= (nth 0 s) target-date)
        (push s sessions)
        (setq total-rounded (+ total-rounded (nth 3 s)))))
    (setq sessions (reverse sessions))
    (with-current-buffer (get-buffer-create buf-name)
      (erase-buffer)
      (org-mode)
      (insert (format "#+TITLE: Daily Time Report (%s)\n" albin-timeclock-current-profile))
      (insert (format "#+SUBTITLE: %s\n\n" target-date))
      (insert (format "* %s Summary\n" (nerd-icons-faicon "nf-fa-clock_o")))
      (insert (format "  - Hours worked: %.2f h\n" total-raw))
      (insert (format "  - Billable: %.2f h\n" total-rounded))
      (insert (format "  - Sessions: %d\n\n" (length sessions)))
      (insert (format "* %s Detailed Log\n" (nerd-icons-faicon "nf-fa-list")))
      (if sessions
          (dolist (s sessions)
            (insert (format "  - [%s - %s] *%s* (%.2f h) » %s\n"
                            (nth 4 s)
                            (nth 5 s)
                            (nth 1 s)
                            (nth 3 s)
                            (nth 2 s))))
        (insert "  - No sessions found for this date.\n"))
      (display-buffer (current-buffer)))))

(defun albin/timeclock-weekly-summary ()
  "Generates a detailed weekly report."
  (interactive)
  (let* ((end-date (format-time-string "%Y-%m-%d"))
         (start-date (format-time-string "%Y-%m-%d" (time-subtract (current-time) (days-to-time 7))))
         (raw-sessions (albin/get-timelog-sessions))
         (merged-sessions (albin/prepare-report-sessions raw-sessions))
         (rounded-sessions (car (albin/apply-time-carry merged-sessions)))
         (project-raw-hours (make-hash-table :test 'equal))
         (project-rounded-hours (make-hash-table :test 'equal))
         (daily-sessions (make-hash-table :test 'equal))
         (mapping (albin/load-timeclock-projects))
         (total-raw 0.0) (total-rounded 0.0) (session-counts 0)
         (buf-name (format "*Summary: %s*" albin-timeclock-current-profile)))
    (dolist (s merged-sessions)
      (let* ((date (nth 0 s)) (proj (nth 1 s)) (raw-hrs (nth 3 s)))
        (when (and (not (string< date start-date)) (not (string< end-date date)))
          (setq total-raw (+ total-raw raw-hrs))
          (setq session-counts (1+ session-counts))
          (puthash proj (+ (gethash proj project-raw-hours 0.0) raw-hrs) project-raw-hours)
          (puthash date (append (gethash date daily-sessions '()) (list s)) daily-sessions))))
    (dolist (s rounded-sessions)
      (let ((date (nth 0 s)) (proj (nth 1 s)) (rnd-hrs (nth 3 s)))
        (when (and (not (string< date start-date)) (not (string< end-date date)))
          (setq total-rounded (+ total-rounded rnd-hrs))
          (puthash proj (+ (gethash proj project-rounded-hours 0.0) rnd-hrs) project-rounded-hours))))
    (with-current-buffer (get-buffer-create buf-name)
      (erase-buffer) (org-mode)
      (insert (format "#+TITLE: Time Report (%s)\n#+SUBTITLE: %s to %s\n\n" albin-timeclock-current-profile start-date end-date))
      (insert (format "* %s Summary\n" (nerd-icons-faicon "nf-fa-bar_chart")) (format "  - Hours worked: %.2f h\n  - Billable: %.2f h\n  - Sessions: %d\n\n" total-raw total-rounded session-counts))
      (insert (format "* %s Project Breakdown\n" (nerd-icons-faicon "nf-fa-folder_open")) "| Project | Code | Worked | Billable | Share |\n|---------+------+----------+----------+-------|\n")
      (let ((proj-list '())) (maphash (lambda (k v) (push (cons k v) proj-list)) project-rounded-hours)
           (dolist (p (sort proj-list (lambda (a b) (> (cdr a) (cdr b)))))
             (let* ((name (if (albin/is-empty (car p)) "Other" (car p))) (rnd (cdr p)) (raw (gethash (car p) project-raw-hours 0.0))
                    (code (albin/timeclock-project-export-code (car p) mapping))
                    (perc (if (> total-rounded 0) (* (/ rnd total-rounded) 100) 0)))
               (insert (format "| %s | %s | %.2f h | %.2f h | %d%% |\n" name code raw rnd perc)))))
      (org-table-align) (insert (format "\n* %s Detailed Log\n" (nerd-icons-faicon "nf-fa-calendar")))
      (let ((dates (sort (let (d) (maphash (lambda (k v) (push k d)) daily-sessions) d) 'string<)))
        (dolist (date dates)
          (let ((day-total 0.0) (sessions (gethash date daily-sessions)))
            (dolist (s sessions) (setq day-total (+ day-total (nth 3 s))))
            (insert (format "** %s (%.2f h)\n" date day-total))
            (dolist (s sessions)
              (insert (format "   - [%s - %s] *%s* (%.2f h) » %s\n" (nth 4 s) (nth 5 s) (nth 1 s) (nth 3 s) (nth 2 s)))))))
      (display-buffer (current-buffer)))))

(defcustom albin-timeclock-export-directory "~/Desktop/"
  "Default directory offered when exporting a timeclock CSV report."
  :type 'directory
  :group 'albin-timeclock)

(defun albin/csv-escape-field (value)
  "Format VALUE as one properly quoted, escaped CSV field."
  (format "\"%s\"" (replace-regexp-in-string "\"" "\"\"" (format "%s" value))))

(defun albin/timeclock-export-csv ()
  (interactive)
  (let* ((start-date (org-read-date nil nil nil "Export from: "))
         (end-date (org-read-date nil nil nil "Export to: "))
         (raw-sessions (albin/get-timelog-sessions))
         (merged (albin/prepare-report-sessions raw-sessions))
         (sessions (car (albin/apply-time-carry merged)))
         (mapping (albin/load-timeclock-projects))
         (file-path (read-file-name "Save CSV to: " albin-timeclock-export-directory
                                     (format "time_%s.csv" (downcase albin-timeclock-current-profile))))
         (rows (list "Project,ExportCode,Description,Date,Duration")))
    (dolist (s sessions)
      (let* ((date (nth 0 s)) (proj (nth 1 s)) (desc (nth 2 s)) (hrs (nth 3 s)))
        (when (and (not (string< date start-date)) (not (string< end-date date)))
          ;; Only the numeric duration gets a Swedish decimal comma; project
          ;; and description text keep any literal periods they contain.
          (push (mapconcat #'albin/csv-escape-field
                            (list proj (albin/timeclock-project-export-code proj mapping) desc date
                                  (replace-regexp-in-string "\\." "," (format "%.2f" hrs)))
                            ",")
                rows))))
    (with-temp-file file-path
      (insert (mapconcat #'identity (nreverse rows) "\n") "\n"))
    (message "✅ CSV Exported!")))

(defun albin/timeclock--session-choices (date)
  "Return an alist of (LABEL . SESSION) for completed sessions on DATE."
  (let ((choices '()))
    (dolist (s (albin/get-timelog-sessions))
      (when (and (string= (nth 0 s) date)
                 (not (string= (nth 2 s) "Ongoing session")))
        (push (cons (format "[%s-%s] %s: %s (%s)"
                            (nth 4 s) (nth 5 s)
                            (if (albin/is-empty (nth 1 s)) "Other" (nth 1 s))
                            (if (albin/is-empty (nth 2 s)) "(no description)" (nth 2 s))
                            (albin/format-hours-to-hm (nth 3 s)))
                    s)
              choices)))
    (nreverse choices)))

(defun albin/timeclock-edit-session (&optional date)
  "Edit the description and/or duration of a completed session on DATE
(defaults to prompting, like the other reports). Only touches the
session's closing (\"o\") log line — the project on the opening (\"i\")
line is left alone; use `albin/timeclock-edit-log' for that, or for
sessions that span midnight (which this can't safely locate)."
  (interactive)
  (let* ((target-date (or date (org-read-date nil nil nil "Edit session on date: ")))
         (choices (albin/timeclock--session-choices target-date)))
    (if (not choices)
        (message "No completed sessions found on %s." target-date)
      (let* ((label (completing-read (format "Edit which session on %s: " target-date)
                                     (mapcar #'car choices) nil t))
             (session (cdr (assoc label choices)))
             (old-reason (nth 2 session))
             (old-hours (nth 3 session))
             (start-time (nth 4 session))
             (old-end-time (nth 5 session))
             (slash-date (replace-regexp-in-string "-" "/" target-date))
             (new-reason (read-string "New description: " old-reason))
             (new-hours-str (read-string
                             (format "New duration in hours (currently %.2f): " old-hours)
                             nil nil (number-to-string old-hours)))
             (new-hours (if (albin/is-empty new-hours-str) old-hours (string-to-number new-hours-str)))
             (old-line (format "o %s %s%s" slash-date old-end-time
                               (if (albin/is-empty old-reason) "" (concat " " old-reason))))
             (new-end-time (if (= new-hours old-hours)
                               old-end-time
                             (format-time-string
                              "%H:%M:%S"
                              (time-add (encode-time (parse-time-string (concat target-date " " start-time)))
                                        (seconds-to-time (round (* new-hours 3600)))))))
             (new-line (format "o %s %s%s" slash-date new-end-time
                               (if (albin/is-empty new-reason) "" (concat " " new-reason)))))
        (if (albin/timeclock--replace-log-line old-line new-line)
            (progn
              (timeclock-reread-log)
              (albin/timeclock-update-modeline)
              (message "✅ Session updated."))
          (message "⚠️ Couldn't locate that session's exact log line (it may span midnight); nothing was changed. Use `albin/timeclock-edit-log' to fix it by hand."))))))

(defun albin/timeclock-doctor ()
  "Scan the current profile's timelog for structural problems — malformed
lines, clock-ins without a matching clock-out (or vice versa), sessions
that end before they start, and a session left open for more than a day —
and show them in a buffer."
  (interactive)
  (let* ((issues (albin/timeclock--find-log-issues timeclock-file))
         (buf-name (format "*Timeclock Doctor: %s*" albin-timeclock-current-profile)))
    (with-current-buffer (get-buffer-create buf-name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format " 🩺 TIMECLOCK DOCTOR — %s\n" albin-timeclock-current-profile) 'face 'font-lock-type-face))
        (insert " ------------------------------------------------------------\n")
        (if issues
            (dolist (issue issues)
              (insert (propertize " ⚠ " 'face 'warning) issue "\n"))
          (insert (propertize " ✅ No issues found.\n" 'face 'success)))
        (insert " ------------------------------------------------------------\n")
        (insert (propertize " Press 'q' to close.\n" 'face 'font-lock-comment-face))
        (special-mode)
        (goto-char (point-min))))
    (display-buffer buf-name '((display-buffer-reuse-window display-buffer-pop-up-window)
                               (window-height . fit-window-to-buffer)))))

(provide 'albin-timeclock-commands)
