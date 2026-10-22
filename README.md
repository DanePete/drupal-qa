# drupal-qa

**Every pull request on your Pantheon Drupal site gets its own copy of the site,
checked, deployed and smoke-tested, with the results posted right on the pull
request. Merging deploys to dev the same way.**

You add one Composer package, one workflow file and two secrets. Nothing blocks a
merge until you say so.

![The comment drupal-qa posts on a pull request: a link to the pull request's own Pantheon environment and a result for every step](docs/images/run-pr-comment.png)

- [What it does](#what-it-does)
- [Install](#install)
- [Getting the two secrets](#getting-the-two-secrets)
- [Adopting a site whose code is only on Pantheon](#adopting-a-site-whose-code-is-only-on-pantheon)
- [What's included](#whats-included)
- [Options](#options)
- [Writing your own tests](#writing-your-own-tests)
- [Troubleshooting](#troubleshooting)
- [Pantheon's GitHub integration and drupal-qa](#pantheons-github-integration-and-drupal-qa)
- [Upgrading from v1](#upgrading-from-v1)
- [Releasing](#releasing)

## What it does

| When | What happens |
|---|---|
| **You open or push to a pull request** | Code checks and PHPUnit run. The code goes to a Pantheon multidev named `pr-<number>`, made from live the first time (from dev if the site has no live yet). drupal-qa waits until Pantheon is really serving the new code, then runs database updates and config import, checks that config matches, and runs the smoke tests against that environment. The results land on the pull request as a comment. |
| **You merge** | The same steps, against `dev`. |
| **You close the pull request** | Its multidev is deleted. |

![The run in GitHub Actions: plan, code checks and PHPUnit, deploy, Behat, summary, and the multidev clean-up that runs when the pull request closes](docs/images/run-actions-graph.png)

A few things it guarantees, because they are where CI usually lies:

- **Nothing reports green without running.** A step that crashes or runs zero
  tests fails. A check that only warns still shows ⚠️; it never shows as passed.
- **It doesn't race Pantheon.** Pantheon reports a deploy as done before the
  environment serves the new files. drupal-qa picks a file the commit changed and
  waits until the environment serves that exact file. Only then does it touch the
  database.
- **Builds queue; they never cancel.** Cancelling a multidev part way through
  leaves a broken environment Pantheon can't roll back, so a new push waits for
  the build that is already running.
- **Pantheon's bot protection doesn't fake a result.** Pantheon's CDN challenges
  automated visitors with a 403 that looks exactly like Drupal saying "access
  denied". drupal-qa sends the site's bot-bypass token with every test request,
  and a challenged request fails the run instead of passing a test.

## Install

You need a Drupal 10 or 11 site on Pantheon with its code on GitHub, and Composer.
Multidev needs a Gold workspace or higher; without it, set `multidev: false` and
pull requests get the checks without an environment. If the site's code is only
in Pantheon's own git so far, start with
[Adopting a site whose code is only on Pantheon](#adopting-a-site-whose-code-is-only-on-pantheon).

**1. Add the package.**

```bash
composer require --dev thronedigital/drupal-qa
```

That brings PHPCS with the Drupal standard, PHPStan with `phpstan-drupal`, PHPUnit
and Behat. Nothing is copied into your project. When the project has its own
`phpunit.xml`, `phpstan.neon` or `behat.yml`, CI uses it; otherwise it uses the
package's.

**2. Add `.github/workflows/drupal-qa.yml`.**

```yaml
name: Drupal QA

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]
  push:
    branches: [main]

jobs:
  qa:
    uses: DanePete/drupal-qa/.github/workflows/pipeline.yml@v2
    with:
      pantheon_site: my-site
    secrets:
      PANTHEON_MACHINE_TOKEN: ${{ secrets.PANTHEON_MACHINE_TOKEN }}
      PANTHEON_SSH_KEY: ${{ secrets.PANTHEON_SSH_KEY }}
```

Change two things:

- `my-site` to the site's Pantheon machine name. `terminus site:list` shows it.
- `main` to your default branch, if it's called something else. A repository
  cloned from Pantheon starts on `master`.

**3. Add two secrets** to the repository. [Getting the two secrets](#getting-the-two-secrets)
shows where each one comes from.

**4. Open a pull request.** Commit the two files on a branch, push it and open a
pull request. The first run takes ten minutes or so, most of it Pantheon creating
the multidev. Later pushes to the same pull request are quicker.

![A pull request's checks: each drupal-qa job is its own check, the multidev clean-up waits for the pull request to close, and merging deploys to dev](docs/images/run-pr-checks.png)

On Pantheon, the multidev appears on its own:

![Pantheon's Multidev page with the pr-3 environment drupal-qa created for pull request 3](docs/images/run-pantheon-multidev.png)

## Getting the two secrets

drupal-qa logs in to Pantheon as you: Terminus with a token, git with an SSH key.
Both secrets act as your Pantheon account, so add them only to repositories you
trust.

### `PANTHEON_MACHINE_TOKEN`

In the Pantheon dashboard, open your avatar menu, choose **User settings**, then
**Personal Access Tokens**, and press **Add token**. Name it after the repository
and copy the token; Pantheon shows it only once.

![Pantheon's User settings, Personal Access Tokens tab, with the Add token button highlighted](docs/images/setup-pantheon-token.png)

New tokens expire after 90 days. When one does, every run fails at "Log in to
Pantheon"; make a new token and replace the secret. Tokens made before September
2026 (Pantheon called them machine tokens) don't expire.

### `PANTHEON_SSH_KEY`

Make a key pair just for this. It has to be RSA, because Terminus refuses ed25519
keys:

```bash
ssh-keygen -t rsa -b 4096 -m PEM -N "" -C "drupal-qa" -f ~/.ssh/drupal_qa
```

That writes the private half to `~/.ssh/drupal_qa` and the public half to
`~/.ssh/drupal_qa.pub`. Give Pantheon the **public** half: **User settings**, then
**SSH Keys**, then **Add New Key**, and paste the contents of
`~/.ssh/drupal_qa.pub`.

![Pantheon's User settings, SSH Keys tab, with the Add New Key button highlighted](docs/images/setup-pantheon-ssh-key.png)

### Adding them to GitHub

In the repository, open **Settings**, then **Secrets and variables**, then
**Actions**, and press **New repository secret**.

![GitHub's Actions secrets page for a repository, with Settings, Secrets and variables, Actions and New repository secret highlighted](docs/images/setup-github-secrets.png)

Add `PANTHEON_MACHINE_TOKEN` with the token as its value, then
`PANTHEON_SSH_KEY` with the whole **private** key file, from
`-----BEGIN RSA PRIVATE KEY-----` to the end.

![GitHub's New secret form with the name PANTHEON_MACHINE_TOKEN filled in](docs/images/setup-github-new-secret.png)

Or from a terminal in the repository, with the [GitHub CLI](https://cli.github.com/):

```bash
gh secret set PANTHEON_MACHINE_TOKEN      # paste the token when it asks
gh secret set PANTHEON_SSH_KEY < ~/.ssh/drupal_qa
```

To set them once for every repository in a GitHub organization, use
**Organization settings** instead, or add `--org <org> --visibility all` to those
commands.

## Adopting a site whose code is only on Pantheon

Plenty of sites have never had a GitHub repository: their code lives in Pantheon's
git and nowhere else. Bringing one over is a handful of commands, and Pantheon
keeps working exactly as before.

```bash
# 1. Pull the code down from Pantheon. It lands in ~/pantheon-local-copies/my-site.
terminus local:clone my-site
cd ~/pantheon-local-copies/my-site

# 2. Install it, then add drupal-qa.
composer install
composer require --dev thronedigital/drupal-qa

# 3. Add the workflow, from this repository's example.
mkdir -p .github/workflows
curl -fsSL https://raw.githubusercontent.com/DanePete/drupal-qa/main/examples/drupal-qa.yml \
  -o .github/workflows/drupal-qa.yml
```

In `.github/workflows/drupal-qa.yml`, set `pantheon_site: my-site` and change
`branches: [main]` to `branches: [master]`, because Pantheon's branch is `master`.

```bash
# 4. Make the GitHub repository and push to it.
gh repo create my-org/my-site --private --source . --remote github --push

# 5. Add the two secrets (see "Getting the two secrets").
gh secret set PANTHEON_MACHINE_TOKEN
gh secret set PANTHEON_SSH_KEY < ~/.ssh/drupal_qa

# 6. Commit drupal-qa on a branch and open a pull request.
git checkout -b chore/drupal-qa
git add composer.json composer.lock .github/workflows/drupal-qa.yml
git commit -m "chore: add drupal-qa"
git push -u github chore/drupal-qa
gh pr create --fill
```

From then on, GitHub is where code changes start. drupal-qa pushes each merge to
Pantheon's `master`, which is what dev runs.

Two things to know:

- **Commits made on Pantheon stop a deploy.** A one-click update in the dashboard
  or an Autopilot update adds a commit to Pantheon's `master` that GitHub doesn't
  have. drupal-qa won't push over it; merge it into GitHub first (see
  [Troubleshooting](#troubleshooting)).
- **Leave SFTP mode off.** Code changed on the server in SFTP mode isn't in git,
  so the next deploy overwrites it.

## What's included

### Checks on every pull request

| Check | What it catches | By default |
|---|---|---|
| **PHPCS** | Drupal coding standard, in custom modules, profiles and every theme that isn't contrib | warns |
| **PHPStan** | Bugs found by static analysis, with `phpstan-drupal`, level 1 | warns |
| **YAML lint** | Syntax errors and duplicate keys in config, which stop an import | warns |
| **Composer audit** | Dependencies with known security advisories | warns |
| **Secret scan** | Passwords and keys committed by mistake ([gitleaks](https://github.com/gitleaks/gitleaks), on the pull request's own commits) | warns |
| **PHPUnit** | Your unit and kernel tests, plus the package's own checks below | **blocks** |

### After every deploy

| Step | What it does | By default |
|---|---|---|
| **Serving this commit** | Waits until the environment serves a file from this exact commit | always runs |
| **Database updates** | `drush updatedb` | **blocks** |
| **Config import** | `drush config:import` | **blocks** |
| **Config status** | Confirms config on the environment now matches the code | warns |
| **Behat** | The smoke tests below, against the environment's real URL | warns |

To make a warning block, list it under `required` ([Options](#options)).

### PHPUnit tests that come with it

These run with your own tests on every pull request. There is nothing to set up.

| Test | Checks that |
|---|---|
| `ComposerValidationTest` | `composer.json` exists and is valid JSON |
| | `composer.lock` exists |
| | debug packages such as kint or var-dumper aren't in `require` (a note only, never a failure) |
| | every local patch file listed under `extra.patches` exists |
| `ModuleInfoTest` | every custom module's `.info.yml` is valid YAML |
| | each one has `name`, `type` and `core_version_requirement` |
| | none still uses the retired `core:` key |
| `DrupalBootstrapTest` | Drupal's unit test base class, autoloader and string translation load |

### Behat smoke tests that come with it

These run against the deployed environment, logged out unless a scenario says
otherwise. Logged-in scenarios create a throwaway user through Drush and delete it
afterwards.

| Feature | Scenarios |
|---|---|
| **Pages load** | The front page returns 200. A missing page returns a real 404. |
| **Logging in** | The login form loads. Anonymous visitors get 403 at `/admin`. A logged-in user reaches `/user`. |
| **Access control** | Anonymous visitors get 403 at `/admin/structure`, `/admin/config` and `/admin/people`. An administrator reaches `/admin`. |
| **Shopping cart** | Runs only when `drupal/commerce` is installed. Visitors can open `/cart`; a new customer sees an empty cart. |

### Default configs

When the project has none of its own, CI uses the package's
`config/phpunit.xml.dist`, `config/phpstan.neon.dist` and `config/behat.yml.dist`.
Your own `phpunit.xml`, `phpstan.neon` or `behat.yml` always wins.

## Options

Every option has a default. Add one only to change it:

```yaml
    with:
      pantheon_site: my-site
      required: phpcs phpunit   # these block a merge or deploy instead of warning
      skip: behat               # these don't run at all
      code_host: github-app     # Pantheon's GitHub App deploys this site; see below
      multidev: false           # no multidev: pull requests get checks only
```

| Option | Default | Meaning |
|---|---|---|
| `pantheon_site` | none | The site's machine name. Not needed with `code_host: none`. |
| `required` | empty | Checks that fail the run instead of warning. |
| `skip` | empty | Steps that don't run. |
| `code_host` | `pantheon` | `pantheon`: drupal-qa pushes the code. `github-app`: Pantheon's GitHub App pushes it and drupal-qa does the rest. `none`: checks only, nothing deployed. |
| `multidev` | `true` | Multidev needs a Gold workspace or higher. Set `false` below that. |

`required` and `skip` take `phpcs`, `phpstan`, `yamllint`, `audit`, `secrets`,
`phpunit`, `behat` and `config`. `skip` also takes `updatedb` and `cim`, which can
be skipped but never downgraded to a warning: when they run and fail, the site is
broken.

To adopt gradually, start with the defaults, fix what the warnings show, then list
the clean checks under `required`.

Everything else is detected, not configured: the PHP version (from
`composer.json`'s `config.platform.php`, then `pantheon.yml`), which paths to
check, the config sync directory, whether the site has Commerce, and the site's
UUID.

## Writing your own tests

Put `.feature` files in `tests/behat/features/`. They run with the bundled smoke
tests and can use the Drupal Extension and Mink steps, plus these:

- `Given I am logged in as a new user with the "editor" role` creates a user on
  the environment through Drush, logs in with a one-time link, and deletes the
  user after the scenario.
- `Then I should see the ".selector" element`
- `Then I should not see the ".selector" element`

Every scenario starts logged out. For your own step definitions, extend
`DrupalQa\Behat\FeatureContext` and give the project its own `behat.yml`.

PHPUnit tests in `web/modules/custom/*/tests/src/Unit` and `.../Kernel` are found
automatically.

## Troubleshooting

**"Pantheon's bot protection challenges requests from CI".** The site is on
Pantheon's newer CDN and no bypass token reached the request. Check that
`terminus gcdn:bot-bypass <site>` returns a token for the account that owns the
token secret.

**"Could not create multidev pr-N".** The site has reached its multidev limit
(delete one you don't need), or it has no multidev (set `multidev: false`).

**"Pantheon's master has commits this branch does not".** Someone committed on
Pantheon: from the dashboard, in SFTP mode, or through an Autopilot update. Merge
Pantheon's `master` into GitHub first. In a clone made with `terminus local:clone`,
Pantheon is `origin`: `git pull origin master`, then push to GitHub.

**"still serves the old file after 15 minutes".** Pantheon's code log can show
your commit while the environment still runs the old build. An empty commit gives
it something new to sync, and usually clears it:
`git commit --allow-empty -m "chore: re-sync" && git push`.

**"Log in to Pantheon" fails on every run.** The token secret has expired or been
revoked. Make a new one ([Getting the two secrets](#pantheon_machine_token)) and
replace the secret.

**A new Pantheon site has both `main` and `master`.** Dev deploys from `master`;
`main` is the untouched starting template. Push `master` to GitHub as your default
branch.

**Composer audit shows ⚠️ on every pull request.** A dependency has a known
advisory. `composer audit` lists it; updating the package usually clears it.

**PHPStan reports a lot on the first run.** It only warns until you add `phpstan`
to `required`. The default is level 1; for a stricter level, give the project a
`phpstan.neon`.

## Pantheon's GitHub integration and drupal-qa

Pantheon now has two ways to move code from GitHub to Pantheon. Neither one tests
anything, so they work alongside drupal-qa rather than replacing it: Pantheon's
tools move **code**, while drupal-qa moves code **and checks the result**.

- **The GitHub Application.** Generally available since April 2026 for Gold,
  Platinum and Diamond workspaces; GitLab followed (Terminus in June, the
  dashboard in August). The GitHub repository *is* the site's repository: pushing
  or merging to `main` deploys to dev, and pull requests get multidevs. No
  secrets, no Actions. ([docs](https://docs.pantheon.io/guides/external-repositories/github))
- **The `push-to-pantheon` GitHub Action.** Pantheon's own action for pushing to
  dev and to per-PR multidevs from a workflow. Still Early Access at 0.9.6; pin
  0.9.4 or later, which fixed a command injection.
  ([repository](https://github.com/pantheon-systems/push-to-pantheon))

What the GitHub Application **isn't**, as of October 2026:

- **A switch for an existing site.** It is chosen when a site is created
  (`terminus site:create … --vcs-provider=github`). Pantheon documents no way to
  move an existing site over; the realistic path is a new site plus a database,
  files and domain migration. Ask Pantheon before promising it.
- **A test runner.** Its GitHub permissions don't include commit statuses or
  checks, so it can't report a result, let alone stop a broken merge.
- **A Drupal deploy.** Nothing documents it running `updatedb` or
  `config:import` after the code lands.
- **SFTP or Pantheon git.** These sites have neither.

| | GitHub Application | `push-to-pantheon` | drupal-qa |
|---|---|---|---|
| **Plan** | Gold and up | Any | Any (multidev needs Gold and up) |
| **Existing sites** | No documented conversion | Yes | Yes |
| **Moves code** | Yes | Yes | Yes, or leaves it to the app (`code_host: github-app`) |
| **Multidev per pull request** | Yes | Yes | Yes (`pr-N`) |
| **Deletes it when the PR closes** | Not documented | On a later run | Yes |
| **PHPCS, PHPStan, PHPUnit, secret scan** | No | Add your own | Yes |
| **Can stop a broken deploy** | No | Through jobs you add | Yes, for checks under `required` |
| **`updatedb` and `config:import`** | Not documented | No | Yes, once the new code is served |
| **Waits until the new code is served** | No | No | Yes |
| **Smoke tests on the environment** | No | Your own | Behat, logged in and out |
| **Reports on the pull request** | Not documented | GitHub Deployments | Comment and run summary |
| **Secrets** | None | Token and SSH key | Token and SSH key |

"Not documented" means Pantheon's documentation doesn't say either way.

**Using drupal-qa with the GitHub Application.** Set `code_host: github-app`.
drupal-qa then pushes nothing: it waits for Pantheon to build `pr-N` or deploy
dev, then does everything else. Pantheon deploys whatever reaches `main`, so make
drupal-qa's checks required in branch protection if a failing check should stop
the merge. Pantheon doesn't document the app's environment names; this mode
assumes `pr-N`, as in Pantheon's own Next.js docs.

## Upgrading from v1

v1 was `thronedigital/drupal-qa` 1.x, with four workflow files from
`DanePete/drupal-qa`. Its tags stay where they are, so nothing breaks until you
move. To move:

1. `composer require --dev thronedigital/drupal-qa:^2`
2. Delete `pr-checks.yml`, `multidev.yml`, `multidev-cleanup.yml` and
   `deploy-pantheon.yml`, and add the single workflow from [Install](#install).
   The old inputs map like this:
   - `phpcs_required: true` becomes `required: phpcs`.
   - `phpcs_paths` and `php_version` are detected now.
   - `run_behat: false` becomes `skip: behat`.
3. If v1 put `grumphp.yml.dist`, `CLAUDE.md` or `.github/copilot-instructions.md`
   in the project, v2 no longer manages them. Keep or delete them.

Behat in v1 never reached the multidev: its requests went to localhost, and its
logged-in scenarios couldn't create users. A project `behat.yml` written for v1
probably needs its `base_url` removed (CI sets it) and its login steps switched to
`I am logged in as a new user with the "…" role`.

## Releasing

Sites reference the workflow as `@v2`, a tag that moves. Every release tags the
exact version and then moves `v2` to the same commit. If `v2` isn't moved, every
site keeps running the old code.

```bash
git tag v2.0.3 && git tag -f v2 v2.0.3
git push origin v2.0.3 && git push -f origin v2
```

Test a change on a sandbox site first by pointing its workflow at `@main`.

## License

MIT
