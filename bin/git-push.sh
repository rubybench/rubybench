#!/bin/bash
message="$@"

set -x
git add .
if ! git diff-index --quiet HEAD --; then
  git config --global user.email "noreply@github.com"
  git config --global user.name "GitHub"
  git commit -m "GitHub Actions: ${message}

on-behalf-of: @rubybench <noreply@github.com>"
  git push origin master
fi
