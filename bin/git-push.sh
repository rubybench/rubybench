#!/bin/bash
message="$@"

set -x
git add .
if ! git diff-index --quiet HEAD --; then
  if [[ -n "$GITHUB_ACTION" ]]; then
    git config --global user.email "noreply@github.com"
    git config --global user.name "GitHub"
  fi
  git commit -m "$message"
  git pull --rebase origin master
  git push origin master
fi
