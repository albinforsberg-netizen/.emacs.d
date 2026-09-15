;; -*- lexical-binding: t; -*-

;; Profile selection and the per-profile file paths (timelog, diary,
;; projects, paused-session marker) derived from it.

(require 'subr-x)
(require 'timeclock)

(defgroup albin-timeclock nil
  "Personal timeclock and time-tracking system."
  :group 'applications
  :prefix "albin-timeclock-")

(defcustom albin-timeclock-profiles '("Work" "Personal")
  "List of available timeclock profiles."
  :type '(repeat string)
  :group 'albin-timeclock)

(defcustom albin-timeclock-data-directory
  "~/timeclock"
  "Directory for the per-profile timelog, diary, project settings and
paused-session marker.

By default, this is the ~/timeclock folder in the user's home directory.
Set it explicitly (with `setq', or `use-package's `:init', *before*
(require \='albin-timeclock) runs) to pin it to a different folder,
or set it to nil to auto-detect the directory from an existing `timeclock-file'."
  :type '(choice (const :tag "Auto" nil) directory)
  :group 'albin-timeclock)

(defvar albin-timeclock-profile-save-file
  (expand-file-name "timeclock-active-profile.txt" albin-timeclock-data-directory)
  "File to remember the last used profile across Emacs restarts.")

(defun albin/save-active-profile ()
  "Save the current profile to disk as pure text."
  (write-region albin-timeclock-current-profile nil albin-timeclock-profile-save-file nil 'silent))

(defun albin/load-active-profile ()
  "Load the last active profile safely, default to Work."
  (let ((prof "Work"))
    (when (file-exists-p albin-timeclock-profile-save-file)
      (with-temp-buffer
        (insert-file-contents albin-timeclock-profile-save-file)
        (setq prof (string-trim (buffer-string)))))
    (if (member prof albin-timeclock-profiles) prof "Work")))

(defvar albin-timeclock-current-profile (albin/load-active-profile)
  "The currently active profile.")

(defvar albin-timeclock-projects-file nil)
(defvar albin-timeclock-diary-file nil)
(defvar albin-timeclock-paused-file nil)

(defun albin/timeclock-update-paths ()
  "Updates file paths depending on the currently selected profile and ensures they exist."
  (unless (stringp albin-timeclock-current-profile)
    (setq albin-timeclock-current-profile "Work"))

  (let* ((existing-timeclock-dir
          (when (and (stringp timeclock-file)
                     (file-exists-p timeclock-file))
            (file-name-directory timeclock-file)))
         (base-dir (or albin-timeclock-data-directory
                       existing-timeclock-dir
                       user-emacs-directory))
         (suffix (downcase albin-timeclock-current-profile)))

    (unless (file-directory-p base-dir)
      (make-directory base-dir t))

    (setq timeclock-file (expand-file-name (format "timelog-%s" suffix) base-dir))
    (setq albin-timeclock-projects-file (expand-file-name (format "timeclock-projects-%s.eld" suffix) base-dir))
    (setq albin-timeclock-diary-file (expand-file-name (format "dagbok-%s.org" suffix) base-dir))
    (setq albin-timeclock-paused-file (expand-file-name (format "timeclock-paused-%s.txt" suffix) base-dir))

    (unless (file-exists-p timeclock-file)
      (write-region "" nil timeclock-file nil 'silent))))

(albin/timeclock-update-paths)
(timeclock-reread-log)

(provide 'albin-timeclock-profiles)
