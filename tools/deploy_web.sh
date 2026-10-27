#!/bin/bash
# Exports the web build and force-pushes it to the gh-pages branch of the repo's origin.
# One-time: create the GitHub repo, `git remote add origin <url>`, then after the first push
# enable Settings > Pages > Deploy from branch > gh-pages / (root).
set -e
cd "$(dirname "$0")/.."
REMOTE=$(git remote get-url origin)
tools/export_web.sh
cd build/web
rm -rf .git
git init -q
git checkout -q -b gh-pages
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-deploy}" -c user.email="${GIT_AUTHOR_EMAIL:-deploy@localhost}" commit -q -m "Deploy web build $(date +%F)"
git push -f "$REMOTE" gh-pages
echo "Pushed to gh-pages. URL: https://<user>.github.io/<repo>/"
