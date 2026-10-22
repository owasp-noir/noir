package repo

import "net/http"

// GetIssue serves one issue.
func GetIssue(w http.ResponseWriter, r *http.Request) {}

// GetPull serves one pull request.
func GetPull(w http.ResponseWriter, r *http.Request) {}

// GetContents serves a file at any depth.
func GetContents(w http.ResponseWriter, r *http.Request) {}
