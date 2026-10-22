#!/usr/bin/env bash
#
# End-to-end tests for bin/drupal-qa-setup. Each scenario gets a fresh HOME,
# a fake Pantheon and a fake GitHub (bare repositories that github.com URLs
# are rewritten to), drives the wizard through expect, then checks what it
# left behind: files, commits, secrets, keys.
#
#   tests/setup/run.sh            # every scenario
#   tests/setup/run.sh fresh      # one scenario
#
# Needs: bash, git, expect, php, ssh-keygen.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
WIZARD="$HERE/../../bin/drupal-qa-setup"
PASS=0
FAIL=0
ONLY=${1:-}

fixture() { # fixture DIR PHP [v1|v2|none]
  local dir=$1 php=$2 qa=${3:-none}
  mkdir -p "$dir/web/modules/custom" && cd "$dir" || exit 1
  git init -q -b master
  git config user.name "Test" && git config user.email "test@example.test"
  cat > composer.json << EOF
{
    "name": "acme/site",
    "require": {
        "drupal/core-recommended": "^11"
    },
    "require-dev": {},
    "config": {
        "platform": {
            "php": "$php"
        }
    },
    "extra": {
        "drupal-scaffold": {
            "locations": {
                "web-root": "./web"
            }
        }
    }
}
EOF
  local dev='[]'
  [ "$qa" = v1 ] && dev='[{"name": "thronedigital/drupal-qa", "version": "v1.3.3"}]'
  [ "$qa" = v2 ] && dev='[{"name": "thronedigital/drupal-qa", "version": "v2.1.0"},
        {"name": "drupal/core-dev", "version": "11.4.8"}]'
  cat > composer.lock << EOF
{
    "packages": [
        {
            "name": "drupal/core",
            "version": "11.4.8"
        }
    ],
    "packages-dev": $dev
}
EOF
  printf 'api_version: 1\nphp_version: 8.3\n' > pantheon.yml
  if [ "$qa" = v1 ]; then
    mkdir -p .github/workflows
    for f in pr-checks.yml multidev.yml multidev-cleanup.yml deploy-pantheon.yml; do
      printf 'jobs:\n  x:\n    uses: DanePete/drupal-qa/.github/workflows/%s@v1\n' "$f" > ".github/workflows/$f"
    done
  fi
  git add -A && git commit -q -m "Initial site"
  local host="codeserver.dev.$FAKE_UUID"
  git remote add origin "ssh://$host@$host.drush.in:2222/~/repository.git"
}

setup_world() { # fresh HOME, fake GitHub and Pantheon state
  T=$(mktemp -d "${TMPDIR:-/tmp}/qa-setup-test.XXXXXX")
  export HOME="$T/home" FAKE_STATE="$T/state" FAKE_GH="$T/github" FAKE_LOG="$T/log" FAKE_FIXTURE="$T/fixture"
  export FAKE_COMMENT="$T/comment" FAKE_UUID=11111111-2222-3333-4444-555555555555 FAKE_SITE=acme-site
  mkdir -p "$HOME/.ssh" "$FAKE_STATE" "$FAKE_GH"
  : > "$FAKE_LOG"
  git config --global url."file://$FAKE_GH/".insteadOf "https://github.com/"
  git config --global init.defaultBranch master
  git config --global user.name "Test" && git config --global user.email "test@example.test"
  cat > "$FAKE_COMMENT" << 'EOF'
<!-- drupal-qa -->
### Drupal QA

**Environment:** [pr-7](https://pr-7-acme-site.pantheonsite.io)

| Step | Result |
|---|---|
| PHPCS | ✅ passed |
| Composer audit | ⚠️ failed (warn only) |
| Behat | ✅ passed |
EOF
  export PATH="$HERE/fakebin:$PATH" TERM=xterm-256color DRUPAL_QA_NO_ANIMATION=1
}

# drive SCENARIO_EXPECT_BODY: runs the wizard under expect in the cwd.
drive() {
  local args=$1 body=$2
  expect -c "
    set timeout 20
    log_file -noappend $T/transcript
    spawn -noecho bash $WIZARD $args
    proc pick {pattern keys} {
      expect {
        -re \$pattern { send -- \$keys }
        timeout { puts \"\\nTIMEOUT waiting for: \$pattern\"; exit 9 }
        eof { puts \"\\nENDED early, waiting for: \$pattern\"; exit 8 }
      }
    }
    $body
    expect {
      eof { }
      timeout { puts \"\\nTIMEOUT waiting for the end\"; exit 9 }
    }
    catch wait result
    exit [lindex \$result 3]
  " > "$T/expect.out" 2>&1
}

# has_bytes PRINTF-FORMAT FILE: the file contains these exact bytes.
# shellcheck disable=SC2059 # the format is the point: it spells the bytes.
has_bytes() { LC_ALL=C grep -a -q "$(printf "$1")" "$2"; }

# Checks for c: what the fakes were asked, what the wizard said, what a commit holds.
logged() { grep -q -- "$1" "$FAKE_LOG"; }
said() { grep -a -q -- "$1" "$T/transcript"; }
shows() { git --git-dir="$1" show "$2" 2> /dev/null | grep -q -- "$3"; } # shows REPO REV:PATH PATTERN

c() { # c "description" test-command...
  local d=$1
  shift
  if "$@" > /dev/null 2>&1; then
    printf '    \033[32m✓\033[0m %s\n' "$d"
  else
    printf '    \033[31m✗\033[0m %s\n' "$d"
    SCEN_FAIL=1
  fi
}

scenario() { # scenario NAME "title"
  NAME=$1
  [ -n "$ONLY" ] && [ "$ONLY" != "$NAME" ] && return 1
  printf '\n\033[1m%s\033[0m: %s\n' "$NAME" "$2"
  SCEN_FAIL=0
  setup_world
  return 0
}

done_scenario() {
  if [ "$SCEN_FAIL" = 0 ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1))
    grep -a -E "TIMEOUT|ENDED" "$T/expect.out" | sed 's/^/    /'
    printf '    transcript: %s\n' "$T/transcript"
  fi
}


# ─────────────────────────────────────────────────────────────────────────
if scenario fresh "a site only in Pantheon's git; new GitHub repo; first test; watch the run"; then
  fixture "$FAKE_FIXTURE" 8.1.13 none > /dev/null
  sed -i.bak 's/| Behat | ✅ passed |/| Behat | ⚠️ failed (warn only) |/' "$FAKE_COMMENT" && rm -f "$FAKE_COMMENT.bak"
  export FAKE_BEHAT_FAILS=1
  mkdir -p "$T/empty" && cd "$T/empty" || exit 1
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "Where is the site" "\r"
    pick "Type part of its name" "acme-s\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Set config.platform.php to 8.3" "y"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Who should own" "2"
    pick "Repository name" "\r"
    pick "Visibility" "\r"
    pick "Create acme-org/acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Paste the token" "bad-token\r"
    pick "Paste the token" "good-token\r"
    pick "Press Enter to continue" "\r"
    pick "Add the public half" "y"
    pick "Press Enter to continue" "\r"
    pick "Add a first test" "y"
    pick "phrase on the home page" "Welcome to Acme\r"
    pick "Commit to" "y"
    pick "Press Enter to continue" "\r"
    pick "first run passed" ""
    pick "Press Enter to continue" "\r"
  '
  rc=$?
  unset FAKE_BEHAT_FAILS
  repo="$FAKE_GH/acme-org/acme-site.git"
  site="$HOME/pantheon-local-copies/acme-site"
  c "the wizard finished cleanly (exit $rc)" test "$rc" = 0
  c "cloned the site from Pantheon" test -d "$site/.git"
  c "raised config.platform.php to 8.3" grep -q '"php": "8.3"' "$site/composer.json"
  c "required thronedigital/drupal-qa" grep -q 'thronedigital/drupal-qa' "$site/composer.json"
  c "required drupal/core-dev matched to core" grep -q '"drupal/core-dev": "~11.4.8"' "$site/composer.json"
  c "reported that no existing package changed" said "No package the site already had changed version"
  c "created acme-org/acme-site with master" git --git-dir="$repo" rev-parse --verify -q master
  c "pushed the branch chore/drupal-qa" git --git-dir="$repo" rev-parse --verify -q chore/drupal-qa
  workflow=chore/drupal-qa:.github/workflows/drupal-qa.yml
  c "the commit has the workflow" shows "$repo" "$workflow" 'pantheon_site: acme-site'
  c "the workflow deploys from master" shows "$repo" "$workflow" 'branches: \[master\]'
  c "the commit has the first test" \
    shows "$repo" chore/drupal-qa:tests/behat/features/acme-site.feature 'Welcome to Acme'
  c "the commit has composer.lock" sh -c "git --git-dir='$repo' show chore/drupal-qa --stat | grep -q composer.lock"
  c "rejected the bad token, set the good one" grep -q 'secret PANTHEON_MACHINE_TOKEN set (10 chars)' "$FAKE_LOG"
  c "set PANTHEON_SSH_KEY" grep -q 'secret PANTHEON_SSH_KEY set' "$FAKE_LOG"
  c "made an RSA key" sh -c "head -1 '$HOME/.ssh/drupal_qa' | grep -q 'RSA PRIVATE KEY'"
  c "added the key to Pantheon" test -s "$FAKE_STATE/key-added"
  c "opened the pull request" logged 'gh pr create -R acme-org/acme-site --base master --head chore/drupal-qa'
  c "opened the run in the browser" logged 'open https://github.com/acme-org/acme-site/actions/runs/4242'
  c "counted the warnings instead of calling it a clean pass" said "passed, with 2 warning(s)"
  c "named the Behat scenario that failed, and why" said 'was not found anywhere in the text'
  c "linked the multidev" said "pr-7-acme-site.pantheonsite.io"
  c "wrote the permission the results comment needs" shows "$repo" "$workflow" 'pull-requests: write'
  c "never printed the token" sh -c "! grep -q 'good-token' '$T/transcript'"
  c "never force-pushed" sh -c "! grep -q -- '--force' '$FAKE_LOG'"
  c "drew the job board's icons intact" has_bytes '\342\234\223\033\\[0m Plan' "$T/transcript"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario rerun "already installed and on GitHub with both secrets: keep everything"; then
  fixture "$FAKE_FIXTURE" 8.3 v2 > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  mkdir -p .github/workflows
  cat > .github/workflows/drupal-qa.yml << 'EOF'
name: Drupal QA

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]
  push:
    branches: [master]

jobs:
  qa:
    permissions:
      contents: read
      pull-requests: write
    uses: DanePete/drupal-qa/.github/workflows/pipeline.yml@v2
    with:
      pantheon_site: acme-site
    secrets:
      PANTHEON_MACHINE_TOKEN: ${{ secrets.PANTHEON_MACHINE_TOKEN }}
      PANTHEON_SSH_KEY: ${{ secrets.PANTHEON_SSH_KEY }}
EOF
  git add -A && git commit -q -m "drupal-qa"
  mkdir -p "$FAKE_GH/acme-org" && git init -q --bare "$FAKE_GH/acme-org/acme-site.git"
  git remote add github "https://github.com/acme-org/acme-site.git" && git push -q github master
  export FAKE_SECRETS="PANTHEON_MACHINE_TOKEN PANTHEON_SSH_KEY"
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "already up to date" ""
    pick "Press Enter to continue" "\r"
    pick "Using .*acme-org/acme-site" ""
    pick "Press Enter to continue" "\r"
    pick "Keep it" "y"
    pick "Press Enter to continue" "\r"
    pick "Keep it" "y"
    pick "Press Enter to continue" "\r"
    pick "Add a first test" "n"
    pick "Press Enter to continue" "\r"
    pick "First run" ""
    pick "Press Enter to continue" "\r"
  '
  rc=$?
  unset FAKE_SECRETS
  c "the wizard finished cleanly (exit $rc)" test "$rc" = 0
  c "didn't run composer require" sh -c "! grep -q 'composer require' '$FAKE_LOG'"
  c "didn't touch the secrets" sh -c "! grep -q 'gh secret set' '$FAKE_LOG'"
  c "didn't add a key" test ! -e "$FAKE_STATE/key-added"
  c "didn't open a pull request" sh -c "! grep -q 'gh pr create' '$FAKE_LOG'"
  c "left the working tree clean" test -z "$(git status --porcelain)"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario upgrade "drupal-qa v1 with its four workflows"; then
  fixture "$FAKE_FIXTURE" 8.3 v1 > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  mkdir -p "$FAKE_GH/acme-org" && git init -q --bare "$FAKE_GH/acme-org/acme-site.git"
  git remote add github "https://github.com/acme-org/acme-site.git" && git push -q github master
  export FAKE_SECRETS="PANTHEON_MACHINE_TOKEN PANTHEON_SSH_KEY"
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "v1: setup upgrades it" ""
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Remove them" "y"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Keep it" "y"
    pick "Press Enter to continue" "\r"
    pick "Keep it" "y"
    pick "Press Enter to continue" "\r"
    pick "Add a first test" "n"
    pick "Commit to" "y"
    pick "Press Enter to continue" "\r"
    pick "first run passed" ""
    pick "Press Enter to continue" "\r"
  '
  rc=$?
  unset FAKE_SECRETS
  repo="$FAKE_GH/acme-org/acme-site.git"
  c "the wizard finished cleanly (exit $rc)" test "$rc" = 0
  c "upgraded with -W, adding core-dev" \
    logged 'composer require --dev thronedigital/drupal-qa:^2.1 drupal/core-dev:~11.4.8 -W'
  changes=$(git --git-dir="$repo" show --name-status --format= chore/drupal-qa)
  c "the commit removes all four v1 workflows" test "$(grep -c '^D' <<< "$changes")" = 4
  c "the commit adds drupal-qa.yml" grep -q 'A.*drupal-qa.yml' <<< "$changes"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario taken "the name is taken by different history: refuse, pick another; Composer fails once"; then
  fixture "$FAKE_FIXTURE" 8.3 none > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  export FAKE_COMPOSER_FAIL_ONCE=1
  mkdir -p "$FAKE_GH/acme-org" "$T/other"
  other="$FAKE_GH/acme-org/acme-site.git"
  git init -q --bare "$other"
  (cd "$T/other" && git init -q -b master && git commit -q --allow-empty -m "Someone else's work" \
    && git push -q "$other" master)
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Let Composer update the packages" "y"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Who should own" "2"
    pick "Repository name" "\r"
    pick "What should setup do" "\r"
    pick "Different histories" ""
    pick "Repository name" "acme-site-2\r"
    pick "Visibility" "\r"
    pick "Create acme-org/acme-site-2" "y"
    pick "Press Enter to continue" "\r"
    pick "Paste the token" "good-token\r"
    pick "Press Enter to continue" "\r"
    pick "Add the public half" "y"
    pick "Press Enter to continue" "\r"
    pick "Add a first test" "n"
    pick "Commit to" "y"
    pick "Press Enter to continue" "\r"
    pick "first run passed" ""
    pick "Press Enter to continue" "\r"
  '
  rc=$?
  unset FAKE_COMPOSER_FAIL_ONCE
  c "the wizard finished cleanly (exit $rc)" test "$rc" = 0
  c "retried Composer with -W after it failed" \
    logged 'composer require --dev thronedigital/drupal-qa:^2.1 drupal/core-dev:~11.4.8 -W'
  c "explained the first failure instead of dumping it" said "without updating some installed packages"
  c "left the other repository's history alone" \
    test "$(git --git-dir="$other" log --format=%s master)" = "Someone else's work"
  c "never force-pushed" sh -c "! grep -q -- '--force' '$FAKE_LOG'"
  c "created acme-site-2 instead" \
    git --git-dir="$FAKE_GH/acme-org/acme-site-2.git" rev-parse --verify -q chore/drupal-qa
  c "removed the abandoned remote" sh -c "git remote get-url github | grep -q acme-site-2"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario older "GitHub has an older copy of the same history: fast-forward it"; then
  fixture "$FAKE_FIXTURE" 8.3 none > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  mkdir -p "$FAKE_GH/acme-org" && git init -q --bare "$FAKE_GH/acme-org/acme-site.git"
  git push -q "$FAKE_GH/acme-org/acme-site.git" master
  git commit -q --allow-empty -m "Newer work on Pantheon"
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Who should own" "2"
    pick "Repository name" "\r"
    pick "What should setup do" "\r"
    pick "older copy" ""
    pick "Press Enter to continue" "\r"
    pick "Paste the token" "good-token\r"
    pick "Press Enter to continue" "\r"
    pick "Add the public half" "n"
    pick "Press Enter to continue" "\r"
    pick "Add a first test" "n"
    pick "Commit to" "n"
    pick "Press Enter to continue" "\r"
    pick "First run" ""
    pick "Press Enter to continue" "\r"
    pick "Still to do" ""
  '
  rc=$?
  c "the wizard finished cleanly (exit $rc)" test "$rc" = 0
  c "brought GitHub's master up to date" \
    test "$(git --git-dir="$FAKE_GH/acme-org/acme-site.git" log -1 --format=%s master)" = 'Newer work on Pantheon'
  c "listed the key to add by hand" grep -q 'Add .*drupal_qa.pub at https://dashboard.pantheon.io' "$T/transcript"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario dryrun "--dry-run from scratch changes nothing"; then
  fixture "$FAKE_FIXTURE" 8.1.13 none > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  before=$(git status --porcelain; cat composer.json)
  drive "--dry-run" '
    pick "Nothing will change" ""
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Set config.platform.php" "y"
    pick "would.*composer require" ""
    pick "Press Enter to continue" "\r"
    pick "would.*write .github/workflows/drupal-qa.yml" ""
    pick "Press Enter to continue" "\r"
    pick "Who should own" "2"
    pick "Repository name" "\r"
    pick "Visibility" "\r"
    pick "Create acme-org/acme-site" "y"
    pick "would.*Creating acme-org/acme-site" ""
    pick "Press Enter to continue" "\r"
    pick "Paste the token" "good-token\r"
    pick "would.*PANTHEON_MACHINE_TOKEN" ""
    pick "Press Enter to continue" "\r"
    pick "Add the public half" "y"
    pick "Press Enter to continue" "\r"
    pick "Add a first test" "y"
    pick "phrase on the home page" "Hello\r"
    pick "Commit to" "y"
    pick "Press Enter to continue" "\r"
    pick "First run" ""
    pick "Press Enter to continue" "\r"
  '
  rc=$?
  after=$(git status --porcelain; cat composer.json)
  c "the wizard finished cleanly (exit $rc)" test "$rc" = 0
  c "no file changed" test "$before" = "$after"
  c "no GitHub repository was created" test -z "$(ls "$FAKE_GH")"
  c "no secret was set" sh -c "! grep -q 'gh secret set' '$FAKE_LOG'"
  c "no key was made or added" sh -c "test ! -e '$HOME/.ssh/drupal_qa' && test ! -e '$FAKE_STATE/key-added'"
  c "Composer never ran" sh -c "! grep -q 'composer require' '$FAKE_LOG'"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario login "Terminus logged out: log in with a token, reuse it for the secret"; then
  fixture "$FAKE_FIXTURE" 8.3 none > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  export FAKE_TERMINUS_LOGGED_OUT=1 FAKE_MULTIDEV=0 FAKE_COMMENT=/nonexistent
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Paste the token" "good-token\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "checks only" ""
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "multidev.*false" ""
    pick "Press Enter to continue" "\r"
    pick "Who should own" "\r"
    pick "Repository name" "\r"
    pick "Visibility" "\r"
    pick "Create devuser/acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Use the token you logged Terminus in with" "y"
    pick "Press Enter to continue" "\r"
    pick "Add the public half" "y"
    pick "Press Enter to continue" "\r"
    pick "Add a first test" "n"
    pick "Commit to" "y"
    pick "Press Enter to continue" "\r"
    pick "The first run finished" ""
    pick "Press Enter to continue" "\r"
  '
  rc=$?
  unset FAKE_TERMINUS_LOGGED_OUT FAKE_MULTIDEV
  repo="$FAKE_GH/devuser/acme-site.git"
  c "the wizard finished cleanly (exit $rc)" test "$rc" = 0
  c "logged Terminus in" grep -q 'terminus auth:login' "$FAKE_LOG"
  c "reused the token for the secret" grep -q 'secret PANTHEON_MACHINE_TOKEN set (10 chars)' "$FAKE_LOG"
  c "wrote multidev: false" shows "$repo" chore/drupal-qa:.github/workflows/drupal-qa.yml 'multidev: false'
  c "said plainly when the results never reached the pull request" said "never reached the pull request"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario interrupt "Ctrl-C at a menu and at a text prompt stops cleanly"; then
  fixture "$FAKE_FIXTURE" 8.3 none > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Who should own" "\003"
    pick "Stopped" ""
  '
  rc=$?
  c "stopped at the owner menu with the resume message (exit $rc)" grep -a -q "Run it again any time" "$T/transcript"
  c "left the terminal echoing" sh -c "! grep -a -q 'stty: ' '$T/expect.out'"
  done_scenario
fi

# ─────────────────────────────────────────────────────────────────────────
if scenario refused "GitHub refuses the new repository: choose again, without Internal on a personal account"; then
  fixture "$FAKE_FIXTURE" 8.3 none > /dev/null
  cd "$FAKE_FIXTURE" || exit 1
  export FAKE_GH_CREATE_FAILS=1
  drive "" '
    pick "Press Enter to start" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Use acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Press Enter to continue" "\r"
    pick "Who should own" "\r"
    pick "Repository name" "\r"
    pick "Visibility" "\r"
    pick "Create devuser/acme-site" "y"
    pick "Choose again" ""
    pick "Who should own" "2"
    pick "Repository name" "\r"
    pick "Visibility" "\r"
    pick "Create acme-org/acme-site" "y"
    pick "Press Enter to continue" "\r"
    pick "Paste the token" "\003"
    pick "Stopped" ""
  '
  unset FAKE_GH_CREATE_FAILS
  c "went back to the owner menu after the refusal" grep -a -q "Choose again" "$T/transcript"
  c "never offered Internal" sh -c "! grep -a -q 'Internal' '$T/transcript'"
  c "created acme-org/acme-site on the second try" \
    git --git-dir="$FAKE_GH/acme-org/acme-site.git" rev-parse --verify -q master
  c "left no stray remote behind" sh -c "cd '$FAKE_FIXTURE' && git remote get-url github | grep -q acme-org/acme-site"
  done_scenario
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
