;; -*- lexical-binding: t; -*-

;; Org diary logging and the git-based backup of timeclock data files.

(require 'timeclock)
(require 'albin-timeclock-profiles)
(require 'albin-timeclock-sessions)

;; Defined in albin-timeclock-modeline.el; only called from inside the
;; after-save-hook lambda below, long after every module has loaded, so
;; this doesn't need (or want) a `require' — that would create a load
;; cycle, since the mode-line module hooks nothing back into this one.
(declare-function albin/timeclock-update-modeline "albin-timeclock-modeline")

(defun albin/append-to-diary (project reason duration-hours)
  (when (and reason (not (albin/is-empty reason)) (not (string-match-p "---BREAK---" reason)))
    (let* ((date-heading (format-time-string "* %Y-%m-%d %A"))
           (time-str (format-time-string "%H:%M"))
           (dur-str (albin/format-hours-to-hm duration-hours))
           (proj-str (if (albin/is-empty project) "Other" project))
           (entry (format "- [%s] *%s* (%s): %s\n" time-str proj-str dur-str reason)))
      (with-current-buffer (find-file-noselect albin-timeclock-diary-file)
        (goto-char (point-max))
        (unless (save-excursion (re-search-backward (concat "^" (regexp-quote date-heading)) nil t))
          (unless (bolp) (insert "\n"))
          (insert "\n" date-heading "\n"))
        (goto-char (point-max))
        (insert entry)
        (save-buffer)))))

(defun albin/timeclock-open-diary ()
  (interactive)
  (find-file albin-timeclock-diary-file)
  (message "📖 Opened diary for: %s" albin-timeclock-current-profile))

(defun albin/timeclock-edit-log ()
  (interactive)
  (find-file timeclock-file)
  (add-hook 'after-save-hook
            (lambda ()
              (timeclock-reread-log)
              (albin/timeclock-update-modeline)
              (message "🔄 Timelog synced to memory!"))
            nil t)
  (message "✏️ Editing raw timelog for: %s. Save when done!" albin-timeclock-current-profile))

(defun albin/timeclock--git (&rest args)
  "Run git with ARGS in the timeclock data directory.
Returns (EXIT-CODE . OUTPUT), capturing combined stdout/stderr instead of
discarding it, so a failure can actually be diagnosed. Uses `call-process'
directly instead of a shell string, which avoids spawning an extra shell
process per call and behaves identically on macOS, Linux and Windows."
  (with-temp-buffer
    (let ((code (apply #'call-process "git" nil t nil args)))
      (cons code (string-trim (buffer-string))))))

(defconst albin-timeclock-backup-log-buffer-name "*Timeclock Backup Log*"
  "Buffer collecting a timestamped history of backup attempts and their
outcome, so failures are never *just* discarded even when the backup runs
silently (e.g. automatically after clocking out, or on Emacs exit).")

(defvar albin-timeclock--last-backup-failure nil
  "Text of the last reported backup failure.
Used to avoid repeating the identical warning on every automatic backup
attempt (e.g. after every clock-out) until something actually changes.")

(defun albin/timeclock--backup-log (fmt &rest args)
  "Append a timestamped line to the backup log buffer."
  (with-current-buffer (get-buffer-create albin-timeclock-backup-log-buffer-name)
    (goto-char (point-max))
    (insert (format-time-string "[%Y-%m-%d %H:%M:%S] ") (apply #'format fmt args) "\n")))

(defun albin/timeclock--backup-ok (verbose fmt &rest args)
  "Log a successful/no-op backup step. Only echoes a message when VERBOSE
(an interactive invocation) — silent, automatic backups shouldn't spam."
  (setq albin-timeclock--last-backup-failure nil)
  (let ((text (apply #'format fmt args)))
    (albin/timeclock--backup-log "%s" text)
    (when verbose (message "☁️ %s" text))))

(defun albin/timeclock--backup-fail (fmt &rest args)
  "Log a backup failure. Always surfaced with a message — unlike a
successful step, a failure must never be silently swallowed — but only
once per distinct failure, so a persistent problem (e.g. no git remote
configured yet) doesn't re-nag on every single clock-out."
  (let ((text (apply #'format fmt args)))
    (albin/timeclock--backup-log "FAILED: %s" text)
    (unless (equal text albin-timeclock--last-backup-failure)
      (setq albin-timeclock--last-backup-failure text)
      (message "⚠️ Timeclock backup failed: %s (M-x albin/timeclock-show-backup-log for details)" text))))

(defun albin/timeclock-show-backup-log ()
  "Show the timeclock git backup log."
  (interactive)
  (display-buffer (get-buffer-create albin-timeclock-backup-log-buffer-name)))

(defun albin/timeclock--git-push-async (verbose)
  "Push in the background and log/report the outcome once it's known.
Fire-and-forget by design: Emacs never blocks waiting on the network, so
if it hasn't finished by the time Emacs exits, the already-made commit is
still safe on disk and the next backup will push it along with anything
newer."
  (make-process
   :name "albin-timeclock-git-push"
   :buffer (generate-new-buffer " *albin-timeclock-git-push*")
   :command '("git" "push")
   :noquery t
   :sentinel
   (lambda (proc _event)
     (unless (process-live-p proc)
       (let ((output (with-current-buffer (process-buffer proc) (string-trim (buffer-string))))
             (status (process-exit-status proc)))
         (if (zerop status)
             (albin/timeclock--backup-ok verbose "Push succeeded.")
           (albin/timeclock--backup-fail "git push (exit %s): %s" status output))
         (kill-buffer (process-buffer proc)))))))

(defun albin/timeclock-git-backup ()
  "Commit timeclock/diary files locally, then push in the background.
Adding and committing is synchronous (fast, local-only), so it always
finishes before Emacs exits. See `albin/timeclock--git-push-async' for why
the push itself doesn't block.

Called automatically after every clock-out and on Emacs exit, as well as
being available as a manual command — in all cases outcomes are recorded
in `albin-timeclock-backup-log-buffer-name', and failures (but not routine
successes) are always messaged, so backups can't silently stop working."
  (interactive)
  (let ((verbose (called-interactively-p 'any)))
    (if (not (executable-find "git"))
        (albin/timeclock--backup-fail "git not found on PATH.")
      ;; `timeclock-file' is always set by `albin/timeclock-update-paths' by
      ;; the time this runs, and points wherever the data actually lives —
      ;; the auto-detected directory, an explicit `albin-timeclock-data-directory',
      ;; or the `user-emacs-directory' fallback.
      (let* ((default-directory (file-name-directory timeclock-file))
             (add (albin/timeclock--git "add" "--"
                                         "timelog-*" "timeclock-projects-*.eld"
                                         "dagbok-*.org" "timeclock-active-profile.txt"
                                         "timeclock-paused-*.txt")))
        (if (not (zerop (car add)))
            (albin/timeclock--backup-fail "git add: %s" (cdr add))
          (let ((diff (albin/timeclock--git "diff" "--cached" "--quiet")))
            (if (zerop (car diff))
                (albin/timeclock--backup-ok verbose "Nothing new to back up.")
              (let ((commit (albin/timeclock--git
                             "commit" "-m"
                             (format "⏱ Auto-backup timeclock: %s" (format-time-string "%Y-%m-%d %H:%M")))))
                (if (not (zerop (car commit)))
                    (albin/timeclock--backup-fail "git commit: %s" (cdr commit))
                  (albin/timeclock--backup-ok verbose "Committed: %s" (car (split-string (cdr commit) "\n")))
                  (albin/timeclock--git-push-async verbose))))))))))

(add-hook 'kill-emacs-hook #'albin/timeclock-git-backup)

(provide 'albin-timeclock-diary)
