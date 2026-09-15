;; -*- lexical-binding: t; -*-

;; Pure helpers: Swedish holiday math, rounding/formatting, parsing the raw
;; timelog into sessions (cached), merging sessions for reports, and
;; flex-time calculation. No interactive commands live here.

(require 'calendar)
(require 'subr-x)
(require 'time-date)
(require 'parse-time)

(defvar albin-timeclock-paused-project nil)
(defvar albin-timeclock-task-history nil
  "Minibuffer history for task descriptions.")
(defvar albin-timeclock-pending-reason nil
  "Suggested task description for the current active session.")

;; --- SWEDISH PUBLIC HOLIDAY HANDLING ---
(defun albin/calculate-easter (year)
  "Calculates Easter Sunday mathematically for a given year and returns an absolute calendar date."
  (let* ((a (% year 19))
         (b (/ year 100))
         (c (% year 100))
         (d (/ b 4))
         (e (% b 4))
         (f (/ (+ b 8) 25))
         (g (/ (+ b (- f) 1) 3))
         (h (% (+ (* 19 a) b (- d) (- g) 15) 30))
         (i (/ c 4))
         (k (% c 4))
         (l (% (+ 32 (* 2 e) (* 2 i) (- h) (- k)) 7))
         (m (/ (+ a (* 11 h) (* 22 l)) 451))
         (month (/ (+ h l (- (* 7 m)) 114) 31))
         (day (1+ (% (+ h l (- (* 7 m)) 114) 31))))
    (calendar-absolute-from-gregorian (list month day year))))

;; `albin/swedish-red-days', used just below, is defined in
;; albin-timeclock-commands.el (it returns dated holiday *names*, needed
;; for the holidays popup, not just bare dates).

(defvar albin-timeclock--holiday-cache nil
  "Internal cache for Swedish public holidays.")

(defun albin/get-holidays-list ()
  "Returns a list of date strings for flex time calculation."
  (if albin-timeclock--holiday-cache
      albin-timeclock--holiday-cache
    (let* ((current-year (string-to-number (format-time-string "%Y")))
           (years (list (1- current-year) current-year (1+ current-year)))
           (all-data '()))
      (dolist (y years)
        (setq all-data (append all-data (albin/swedish-red-days y))))
      ;; We store only the dates (car of the pairs) in the cache for fast lookup
      (setq albin-timeclock--holiday-cache (mapcar #'car all-data))
      albin-timeclock--holiday-cache)))

(defcustom albin-timeclock-expected-daily-hours 8.0
  "Expected hours of work on a weekday, used for flex-time calculations.
Weekends and Swedish public holidays always expect 0 hours."
  :type 'float
  :group 'albin-timeclock)

(defun albin/expected-hours-for-date (date-str)
  "Returns `albin-timeclock-expected-daily-hours' for weekdays, 0.0 for
weekends and Swedish public holidays."
  (let* ((year  (string-to-number (substring date-str 0 4)))
         (month (string-to-number (substring date-str 5 7)))
         (day   (string-to-number (substring date-str 8 10)))
         (time  (encode-time 0 0 0 day month year))
         (dow   (string-to-number (format-time-string "%u" time))) ;; 1=Mon, 7=Sun
         (is-weekend (> dow 5))
         (is-holiday (member date-str (albin/get-holidays-list))))
    (if (or is-weekend is-holiday)
        0.0
      albin-timeclock-expected-daily-hours)))
;; ---------------------------------

(defun albin/is-empty (s)
  "Safe check for empty string or nil."
  (or (null s) (string-empty-p s)))

(defun albin/round-hours-custom (hours resolution round-up)
  "Round decimal HOURS to the given RESOLUTION."
  (if (or (null resolution) (<= resolution 0))
      hours
    (let ((factor (/ 1.0 resolution)))
      (if round-up
          (/ (float (ceiling (* hours factor))) factor)
        (/ (float (round (* hours factor))) factor)))))

(defun albin/format-hours-to-hm (decimal-hours)
  "Format decimal hours to a human readable Xh YYm string."
  (let* ((h (truncate decimal-hours))
         (m (truncate (* (- decimal-hours h) 60))))
    (if (> h 0) (format "%dh %02dm" h m) (format "%dm" m))))

(defun albin/load-timeclock-projects ()
  "Loads projects and migrates old data."
  (let ((mapping (if (file-exists-p albin-timeclock-projects-file)
                     (with-temp-buffer
                       (insert-file-contents albin-timeclock-projects-file)
                       (condition-case nil (read (current-buffer)) (error nil)))
                   nil))
        (migrated '()))
    (dolist (entry mapping)
      (let ((proj (car entry))
            (val (cdr entry)))
        (if (stringp val)
            (push (cons proj (list :export-code val :rounding 0.5 :round-up nil :active t)) migrated)
          (push entry migrated))))
    (reverse migrated)))

(defun albin/save-timeclock-projects (mapping)
  (with-temp-file albin-timeclock-projects-file
    (let ((print-level nil) (print-length nil))
      (prin1 mapping (current-buffer)))))

(defun albin/timeclock-project-export-code (project mapping)
  "Return PROJECT's configured :export-code from MAPPING, falling back to
PROJECT itself (or \"Other\" if PROJECT is blank) when unset."
  (let* ((props (cdr (assoc project mapping)))
         (code (and props (plist-get props :export-code))))
    (cond
     ((not (albin/is-empty code)) code)
     ((albin/is-empty project) "Other")
     (t project))))

(defvar albin-timeclock--sessions-cache nil
  "Cache of the last parsed timelog, as (FILE MTIME SESSIONS).
Invalidated automatically whenever FILE's modification time changes.")

(defun albin/get-timelog-sessions ()
  "Return the parsed timelog sessions, cached until the file changes on disk."
  (let* ((timelog-file (or timeclock-file (expand-file-name "timelog-work" user-emacs-directory)))
         (mtime (and (file-exists-p timelog-file)
                     (file-attribute-modification-time (file-attributes timelog-file)))))
    (if (and albin-timeclock--sessions-cache
             (equal (nth 0 albin-timeclock--sessions-cache) timelog-file)
             (equal (nth 1 albin-timeclock--sessions-cache) mtime))
        (nth 2 albin-timeclock--sessions-cache)
      (let ((sessions (albin/timeclock--parse-sessions timelog-file)))
        (setq albin-timeclock--sessions-cache (list timelog-file mtime sessions))
        sessions))))

(defun albin/timeclock--parse-sessions (timelog-file)
  "Parse TIMELOG-FILE from scratch and return a list of sessions."
  (let ((current-project "")
        (current-start-date nil)
        (current-start-time nil)
        (accumulated-hours 0.0)
        (sessions '()))
    (if (not (file-exists-p timelog-file))
        '()
      (with-temp-buffer
        (insert-file-contents timelog-file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
            (when (string-match "^\\([ioO]\\) \\([0-9/]+\\) \\([0-9:]+\\)\\(?: \\(.*\\)\\)?" line)
              (let* ((event (match-string 1 line))
                     (date (replace-regexp-in-string "/" "-" (match-string 2 line)))
                     (time (match-string 3 line))
                     (raw-text (match-string 4 line))
                     (text (if raw-text (string-trim raw-text) "")))
                (cond
                 ((string= event "i")
                  (setq current-project text)
                  (setq current-start-date date current-start-time time))
                 ((and (member event '("o" "O")) current-start-time)
                  (let* ((reason text)
                         (start-str (concat current-start-date " " current-start-time))
                         (end-str (concat date " " time))
                         (t1 (encode-time (parse-time-string start-str)))
                         (t2 (encode-time (parse-time-string end-str)))
                         (diff-hours (/ (float (time-convert (time-subtract t2 t1) 'integer)) 3600.0)))
                    (setq accumulated-hours (+ accumulated-hours diff-hours))
                    (if (string-match-p "---BREAK---" reason)
                        (setq current-start-time nil)
                      (when (> accumulated-hours 0.0)
                        (push (list current-start-date current-project reason accumulated-hours current-start-time time) sessions))
                      (setq accumulated-hours 0.0 current-start-time nil))))))))
          (forward-line 1))
        (when (> accumulated-hours 0.0)
          (push (list current-start-date current-project "Ongoing session" accumulated-hours current-start-time (format-time-string "%H:%M:%S")) sessions))
        (reverse sessions)))))

(defun albin/timeclock--replace-log-line (old-line new-line)
  "Replace the first literal occurrence of OLD-LINE with NEW-LINE in
`timeclock-file'. Returns t if a replacement was made, nil if OLD-LINE
wasn't found (in which case the file is left untouched)."
  (with-temp-buffer
    (insert-file-contents timeclock-file)
    (goto-char (point-min))
    (if (search-forward old-line nil t)
        (progn
          (replace-match new-line t t)
          (write-region (point-min) (point-max) timeclock-file nil 'silent)
          t)
      nil)))

(defun albin/timeclock--find-log-issues (timelog-file)
  "Scan TIMELOG-FILE for structural problems: malformed lines, clock-ins
without a matching clock-out (and vice versa), sessions that end before
they start, and a session still open from more than a day ago. Returns a
list of human-readable issue strings, in file order."
  (let ((issues '())
        (open-since nil) ; (date . time) of an unmatched "i", or nil
        (line-no 0))
    (when (file-exists-p timelog-file)
      (with-temp-buffer
        (insert-file-contents timelog-file)
        (goto-char (point-min))
        (while (not (eobp))
          (setq line-no (1+ line-no))
          (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
            (unless (string-empty-p (string-trim line))
              (if (not (string-match "^\\([ioO]\\) \\([0-9/]+\\) \\([0-9:]+\\)\\(?: \\(.*\\)\\)?" line))
                  (push (format "Line %d: unrecognized entry: %s" line-no line) issues)
                (let* ((event (match-string 1 line))
                       (date (replace-regexp-in-string "/" "-" (match-string 2 line)))
                       (time (match-string 3 line)))
                  (cond
                   ((string= event "i")
                    (when open-since
                      (push (format "Line %d: clocked in again while session started %s %s was still open (its data was silently dropped)"
                                    line-no (car open-since) (cdr open-since))
                            issues))
                    (setq open-since (cons date time)))
                   ((member event '("o" "O"))
                    (if (not open-since)
                        (push (format "Line %d: clock-out with no matching clock-in" line-no) issues)
                      (let ((t1 (encode-time (parse-time-string (concat (car open-since) " " (cdr open-since)))))
                            (t2 (encode-time (parse-time-string (concat date " " time)))))
                        (when (time-less-p t2 t1)
                          (push (format "Line %d: session ends before it starts (%s %s -> %s %s)"
                                        line-no (car open-since) (cdr open-since) date time)
                                issues)))
                      (setq open-since nil))))))))
          (forward-line 1))))
    (when open-since
      (let ((days-open (/ (float-time (time-subtract
                                        (current-time)
                                        (encode-time (parse-time-string (concat (car open-since) " " (cdr open-since))))))
                           86400.0)))
        (when (> days-open 1)
          (push (format "Still clocked in since %s %s (%.1f days ago) — did you forget to clock out?"
                        (car open-since) (cdr open-since) days-open)
                issues))))
    (nreverse issues)))

(defun albin/merge-empty-sessions (sessions)
  "Merges sessions without text with the following session."
  (let ((merged '())
        (active-sessions (make-hash-table :test 'equal)))
    (dolist (s (reverse sessions))
      (let* ((date (nth 0 s))
             (proj (nth 1 s))
             (desc (nth 2 s))
             (hrs  (nth 3 s))
             (key  (concat date "|" proj)))
        (if (or (albin/is-empty desc) (string= desc "Ongoing session"))
            (let ((active (gethash key active-sessions)))
              (if active
                  (setcar (nthcdr 3 active) (+ (nth 3 active) hrs))
                (push (copy-sequence s) merged)))
          (let ((new-s (copy-sequence s)))
            (push new-s merged)
            (puthash key new-s active-sessions)))))
    merged))

(defun albin/merge-sessions-by-description (sessions)
  "Merge same-day sessions that share project and description."
  (let ((merged '())
        (by-key (make-hash-table :test 'equal)))
    (dolist (s sessions)
      (let* ((date (nth 0 s))
             (proj (nth 1 s))
             (desc (string-trim (or (nth 2 s) "")))
             (hrs (nth 3 s))
             (key (concat date "|" proj "|" desc))
             (existing (gethash key by-key)))
        (if (and existing (not (albin/is-empty desc)) (not (string= desc "Ongoing session")))
            (progn
              (setcar (nthcdr 3 existing) (+ (nth 3 existing) hrs))
              (setcar (nthcdr 5 existing) (nth 5 s)))
          (let ((new-s (copy-sequence s)))
            (push new-s merged)
            (when (and (not (albin/is-empty desc)) (not (string= desc "Ongoing session")))
              (puthash key new-s by-key))))))
    (nreverse merged)))

(defun albin/prepare-report-sessions (sessions)
  "Normalize SESSIONS for reports and exports."
  (albin/merge-sessions-by-description
   (albin/merge-empty-sessions sessions)))

(defun albin/timeclock-task-suggestions (&optional project)
  "Return recent unique task descriptions, preferring today's entries.
If PROJECT is non-nil, only include entries from that project."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (seen (make-hash-table :test 'equal))
         (today-suggestions '())
         (older-suggestions '())
         (sessions (reverse (albin/get-timelog-sessions))))
    (dolist (s sessions)
      (let* ((date (nth 0 s))
             (proj (nth 1 s))
             (desc (string-trim (or (nth 2 s) ""))))
        (when (and (not (albin/is-empty desc))
                   (not (string= desc "Ongoing session"))
                   (or (null project) (string= project proj))
                   (not (gethash desc seen)))
          (puthash desc t seen)
          (if (string= date today)
              (push desc today-suggestions)
            (push desc older-suggestions)))))
    (append (nreverse today-suggestions) (nreverse older-suggestions))))

(defun albin/apply-time-carry (sessions)
  "Rounds hours per project config but carries over the remainder."
  (let ((carry 0.0)
        (rounded-sessions '())
        (mapping (albin/load-timeclock-projects)))
    (dolist (s sessions)
      (let* ((proj (nth 1 s))
             (props (cdr (assoc proj mapping)))
             (resolution (if props (plist-get props :rounding) 0.5))
             (round-up (if props (plist-get props :round-up) nil))
             (exact-hours (+ (nth 3 s) carry))
             (rounded-hours (albin/round-hours-custom exact-hours resolution round-up))
             (new-s (copy-sequence s)))
        (setq carry (- exact-hours rounded-hours))
        (setcar (nthcdr 3 new-s) rounded-hours)
        (push new-s rounded-sessions)))
    (cons (reverse rounded-sessions) carry)))

(defun albin/calculate-flex (sessions &optional start-date end-date)
  (let* ((carry-result (albin/apply-time-carry sessions))
         (rounded-sessions (car carry-result))
         (daily-hours (make-hash-table :test 'equal))
         (total-flex 0.0)
         (period-flex 0.0)
         (period-days 0))
    (dolist (s rounded-sessions)
      (let ((date (nth 0 s))
            (hours (nth 3 s)))
        (puthash date (+ (gethash date daily-hours 0.0) hours) daily-hours)))
    (maphash (lambda (date hours)
               (let* ((expected (albin/expected-hours-for-date date))
                      (daily-flex (- hours expected)))
                 (setq total-flex (+ total-flex daily-flex))
                 (when (and start-date end-date
                            (not (string< date start-date))
                            (not (string< end-date date)))
                   (setq period-flex (+ period-flex daily-flex))
                   (setq period-days (1+ period-days)))))
             daily-hours)
    (list total-flex period-flex period-days)))

(provide 'albin-timeclock-sessions)
