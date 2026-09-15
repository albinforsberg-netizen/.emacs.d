;; -*- lexical-binding: t; -*-

;; The transient menu that ties all the commands together, bound globally
;; to C-c t.

(require 'transient)
(require 'timeclock)
(require 'albin-timeclock-profiles)
(require 'albin-timeclock-diary)
(require 'albin-timeclock-commands)

(transient-define-prefix albin-timeclock-menu ()
  "Main menu for Albin Timeclock."
  [:description
   (lambda ()
     (let ((is-in (and timeclock-last-event (string= (car timeclock-last-event) "i"))))
       (format "Albin Timeclock (%s) - %s"
               (propertize albin-timeclock-current-profile 'face 'font-lock-keyword-face)
               (if is-in
                   (propertize (format "CLOCKED IN [%s]" (nth 2 timeclock-last-event)) 'face 'success)
                 (propertize "CLOCKED OUT" 'face 'warning)))))
   ["Actions"
    ("i" "Clock IN" albin/timeclock-in)
    ("o" "Clock OUT" albin/timeclock-out)
    ("b" "Take BREAK" albin/timeclock-break)
    ("r" "Resume" albin/timeclock-resume)
    ("c" "Switch Project" albin/timeclock-change)
    ("a" "Adjust Start Time" albin/timeclock-adjust-start)]
   ["Reports"
    ("t" "Daily Summary" albin/timeclock-daily-summary)
    ("s" "Weekly Summary" albin/timeclock-weekly-summary)
    ("f" "Show Flex" albin/timeclock-show-flex)
    ("h" "Show Public Holidays" albin/timeclock-show-red-days)
    ("e" "Export CSV" albin/timeclock-export-csv)]
   ["Settings & Files"
    ("p" "Switch Profile" albin/timeclock-switch-profile)
    ("P" "Project Settings" albin/timeclock-edit-project)
    ("d" "Open Diary" albin/timeclock-open-diary)
    ("E" "Edit Raw Log" albin/timeclock-edit-log)
    ("S" "Edit Session" albin/timeclock-edit-session)]
   ["System"
    ("B" "Git Backup" albin/timeclock-git-backup)
    ("D" "Doctor (check log)" albin/timeclock-doctor)
    ("L" "Show Backup Log" albin/timeclock-show-backup-log)]])

(global-set-key (kbd "C-c t") 'albin-timeclock-menu)

(provide 'albin-timeclock-menu)
