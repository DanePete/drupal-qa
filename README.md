# drupal-qa

**CI for Drupal sites on Pantheon.** Every pull request gets its own Pantheon
environment, deployed and smoke-tested, with the results posted on the pull request.

## TL;DR

Run this in the site's folder, or in an empty one to pull a site down from Pantheon:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DanePete/drupal-qa/main/bin/drupal-qa-setup)
```

The setup wizard installs the package, writes the workflow, connects GitHub, sets
both secrets, adds the SSH key to Pantheon and opens the first pull request. It
asks only what it can't work out, never prints a secret, never force-pushes, and
`--dry-run` changes nothing. [What each stage does](#the-setup-wizard).

This shows up on the pull request:

![The comment drupal-qa posts on a pull request: a link to the pull request's own Pantheon environment and a result for every step](docs/images/run-pr-comment.png)

| When | What happens |
|---|---|
| **Pull request** | Checks, then a multidev `pr-N`, database updates, config import and smoke tests. Results land on the PR. |
| **Merge** | The same, against `dev`. |
| **Close** | `pr-N` is deleted. |

Nothing blocks a merge until you list it under `required`, except PHPUnit, database
updates, config import and deploy hooks.

## Setup, step by step

The wizard does all of this; here it is by hand.

### 1. Add the package

```bash
composer require --dev thronedigital/drupal-qa "drupal/core-dev:~11.4.8"   # your core version
```

`drupal/core-dev` brings the PHPUnit tooling Drupal's own test classes need, matched
to your core. Drupal 10 and 11 both work.

### 2. Add the workflow

Save as `.github/workflows/drupal-qa.yml`:

```yaml
name: Drupal QA

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]
  push:
    branches: [main]          # your default branch; a clone of Pantheon's repo uses master

jobs:
  qa:
    uses: DanePete/drupal-qa/.github/workflows/pipeline.yml@v2
    with:
      pantheon_site: my-site  # terminus site:list
    secrets:
      PANTHEON_MACHINE_TOKEN: ${{ secrets.PANTHEON_MACHINE_TOKEN }}
      PANTHEON_SSH_KEY: ${{ secrets.PANTHEON_SSH_KEY }}
```

### 3. Add two secrets

Both act as your Pantheon account, so add them only to repositories you trust.

**The token.** Pantheon: avatar menu, **User settings**, **Personal Access Tokens**,
**Add token**. Copy it; you see it once. It expires after 90 days.

![Pantheon's Personal Access Tokens tab with Add token highlighted](docs/images/setup-pantheon-token.png)

**The SSH key.** Make an RSA key (Terminus refuses ed25519), then give Pantheon the
public half: **User settings**, **SSH Keys**, **Add New Key**, paste `~/.ssh/drupal_qa.pub`.

```bash
ssh-keygen -t rsa -b 4096 -m PEM -N "" -C "drupal-qa" -f ~/.ssh/drupal_qa
```

![Pantheon's SSH Keys tab with Add New Key highlighted](docs/images/setup-pantheon-ssh-key.png)

**Into GitHub.** Repository **Settings**, **Secrets and variables**, **Actions**,
**New repository secret**. Add `PANTHEON_MACHINE_TOKEN` (the token) and
`PANTHEON_SSH_KEY` (the whole private key file, `~/.ssh/drupal_qa`). Or use the two
`gh secret set` lines from the TL;DR.

![GitHub's Actions secrets page with the path to New repository secret highlighted](docs/images/setup-github-secrets.png)

![GitHub's New secret form with PANTHEON_MACHINE_TOKEN filled in](docs/images/setup-github-new-secret.png)

### 4. Open a pull request

The first run takes about ten minutes, mostly Pantheon building the multidev.

![A pull request's checks, one per drupal-qa job](docs/images/run-pr-checks.png)

![Pantheon's Multidev page with the pr-3 environment drupal-qa created](docs/images/run-pantheon-multidev.png)

## Site only in Pantheon's git?

The wizard handles this case: run it in an empty folder and pick the site. By hand,
pull it down, add drupal-qa, push it to a new GitHub repository:

```bash
terminus local:clone my-site && cd ~/pantheon-local-copies/my-site
composer install
composer require --dev thronedigital/drupal-qa "drupal/core-dev:~11.4.8"   # your core version
curl -fsSL --create-dirs -o .github/workflows/drupal-qa.yml \
  https://raw.githubusercontent.com/DanePete/drupal-qa/main/examples/drupal-qa.yml
# edit it: pantheon_site: my-site, branches: [master]

gh repo create my-org/my-site --private --source . --remote github --push
gh secret set PANTHEON_MACHINE_TOKEN
gh secret set PANTHEON_SSH_KEY < ~/.ssh/drupal_qa

git checkout -b chore/drupal-qa
git add composer.json composer.lock .github
git commit -m "chore: add drupal-qa"
git push -u github chore/drupal-qa && gh pr create --fill
```

From then on, changes start on GitHub and drupal-qa pushes merges to Pantheon's
`master`. Leave SFTP mode off, and merge any dashboard or Autopilot commit into
GitHub before the next deploy.

## The setup wizard

`bin/drupal-qa-setup` walks through ten stages, and each one checks what's already
done before changing anything:

| Stage | What it does |
|---|---|
| Tools | Checks git, Composer (or ddev), Terminus and the GitHub CLI, and logs them in. |
| Project | Uses the current folder, or pulls a site down from Pantheon. |
| Pantheon site | Finds the site from the git remote and checks it has multidev. |
| Package | Installs drupal-qa and a matching `drupal/core-dev`; raises an old PHP platform pin; upgrades v1. |
| Workflow | Writes `.github/workflows/drupal-qa.yml` for your default branch, showing it first. |
| GitHub | Uses the connected repository, or creates one. A taken name is only adopted if its history lines up. |
| Token | Opens Pantheon's token page, checks the token, saves it as a secret. |
| SSH key | Makes an RSA key, adds the public half to Pantheon, saves the private half as a secret. |
| Pull request | Optionally adds a first test of your own, then commits, pushes and opens the pull request. |
| First run | Watches the run live and shows the results. |

Run it again at any point: finished stages are found and skipped. Its scenario
tests live in `tests/setup/run.sh`.

## Reference

<details>
<summary><b>What runs</b>: every check, the bundled tests, and what blocks</summary>

![The run in GitHub Actions, annotated job by job](docs/images/run-actions-graph.png)

**On every pull request**

| Check | Catches | Default |
|---|---|---|
| PHPCS | Drupal coding standard in custom modules, profiles and non-contrib themes | warns |
| PHPStan | Static analysis with `phpstan-drupal`, level 1 | warns |
| YAML lint | Syntax errors and duplicate keys in config | warns |
| Composer audit | Dependencies with security advisories | warns |
| Secret scan | Committed passwords and keys ([gitleaks](https://github.com/gitleaks/gitleaks)) | warns |
| PHPUnit | Your unit and kernel tests, plus the bundled ones below | **blocks** |

**After every deploy**

| Step | Does | Default |
|---|---|---|
| Serving this commit | Waits until the environment serves a file from this exact commit | always |
| Database updates | `drush updatedb` | **blocks** |
| Config import | `drush config:import` | **blocks** |
| Deploy hooks | `drush deploy:hook`, as `drush deploy` runs on live | **blocks** |
| Config status | Config on the environment matches the code | warns |
| Status report | No errors on Drupal's status report | warns |
| Behat | The bundled smoke tests, against the real URL | warns |
| PHP errors logged | No PHP warnings or errors logged while Behat ran (needs dblog) | warns |

**Bundled PHPUnit tests**

| Test | Checks |
|---|---|
| `ComposerValidationTest` | `composer.json` is valid; `composer.lock` exists; local patch files exist; notes debug packages in `require` |
| `ModuleInfoTest` | Custom `.info.yml` files are valid YAML, have `name`, `type` and `core_version_requirement`, and don't use `core:` |
| `DrupalBootstrapTest` | Drupal's test base class, autoloader and string translation load |

**Bundled Behat smoke tests**

| Feature | Scenarios |
|---|---|
| Pages load | Front page is 200; a missing page is a real 404; every stylesheet and script on the front page loads; security headers are sent; the page can be cached; the newest page of each content type and vocabulary renders |
| Logging in | Login form and password reset load; `/admin` is 403 for visitors; registration is open exactly when the site allows it; a logged-in user reaches `/user` |
| Access control | `/admin/structure`, `/admin/config`, `/admin/people` are 403 for visitors; an administrator reaches `/admin` |
| Administration | Content, people and status report screens load; every content type's add form loads |
| Safe roles | Visitors and plain users hold no restricted permission and no unfiltered text format |
| Webforms | With Webform: each open webform page shows its submit button (never pressed) |
| Search | With core Search: the search page answers |
| XML sitemap | With Simple XML Sitemap or XML sitemap: `/sitemap.xml` is a sitemap |
| Meta tags | With Metatag: the front page has a title and one canonical link |
| Shopping cart | With Commerce: `/cart` opens; a new customer's cart is empty |

Logged-in scenarios create a throwaway user through Drush and delete it after.

**Why green means green**

- A step that crashes or runs zero tests fails; a warning shows ⚠️, never ✅.
- It waits until Pantheon serves the new code before touching the database.
- A new push waits for a multidev build in progress instead of cancelling it.
- It sends Pantheon's bot-bypass token, so a CDN challenge can't pass for Drupal's 403.

</details>

<details>
<summary><b>Options</b>: make checks block, skip steps, no multidev</summary>

```yaml
    with:
      pantheon_site: my-site
      required: phpcs phpunit   # block instead of warn
      skip: behat               # don't run
      code_host: github-app     # Pantheon's GitHub App deploys; drupal-qa does the rest
      multidev: false           # below Gold: checks only on pull requests
```

| Option | Default | Meaning |
|---|---|---|
| `pantheon_site` | none | Site machine name. Not needed with `code_host: none`. |
| `required` | empty | Checks that fail the run instead of warning. |
| `skip` | empty | Steps that don't run. |
| `code_host` | `pantheon` | `pantheon` (drupal-qa pushes), `github-app` (Pantheon's app pushes), `none` (checks only). |
| `multidev` | `true` | Needs a Gold workspace or higher. |

Names: `phpcs phpstan yamllint audit secrets phpunit behat config status watchdog`; `skip` also takes
`updatedb` and `cim`. Detected, not configured: PHP version, paths, config directory,
Commerce, site UUID. Your own `phpunit.xml`, `phpstan.neon` or `behat.yml` replaces
the package's.

</details>

<details>
<summary><b>Writing your own tests</b></summary>

- PHPUnit: `web/modules/custom/*/tests/src/Unit` and `.../Kernel` are found automatically.
- Behat: put `.feature` files in `tests/behat/features/`. On top of the Drupal
  Extension and Mink steps you get:
  - `Given I am logged in as a new user with the "editor" role`
  - `Then I should see the ".selector" element`
  - `Then I should not see the ".selector" element`

For your own step definitions, extend `DrupalQa\Behat\FeatureContext` and add a
`behat.yml`.

</details>

<details>
<summary><b>Troubleshooting</b></summary>

| Message | Fix |
|---|---|
| Pantheon's bot protection challenges requests from CI | `terminus gcdn:bot-bypass <site>` must return a token for the token's account. |
| Could not create multidev pr-N | Delete an unused multidev, or set `multidev: false`. |
| Pantheon's master has commits this branch does not | Someone committed on Pantheon. `git pull <pantheon remote> master`, push to GitHub. |
| still serves the old file after 15 minutes | `git commit --allow-empty -m "chore: re-sync" && git push` |
| Log in to Pantheon fails on every run | The token expired. Make a new one and replace the secret. |
| Composer audit ⚠️ every time | `composer audit` names the package; update it. |
| drupal/core-dev is missing | `composer require --dev "drupal/core-dev:~<your core version>"`. |
| The page can be cached for visitors fails | Set "Browser and proxy cache maximum age" at /admin/config/development/performance (15 minutes or more), then export config. |
| A new Pantheon site has `main` and `master` | Dev runs `master`. Use `master` as GitHub's default branch. |

</details>

<details>
<summary><b>Pantheon's GitHub App vs drupal-qa</b></summary>

Pantheon's [GitHub Application](https://docs.pantheon.io/guides/external-repositories/github)
(GA April 2026, Gold and up) makes your GitHub repository the site's repository:
merges to `main` deploy to dev and pull requests get multidevs. It moves **code**;
drupal-qa moves code **and checks the result**. They work together with
`code_host: github-app`.

| | GitHub App | drupal-qa |
|---|---|---|
| Existing sites | Chosen at site creation; no documented conversion | Any site |
| Multidev per PR | Yes | Yes |
| PHPCS, PHPStan, PHPUnit, secret scan | No | Yes |
| `updatedb`, `config:import` | Not documented | Yes |
| Smoke tests on the environment | No | Yes |
| Can stop a broken merge | No (no checks permission) | Yes, via `required` |
| Secrets | None | Two |

Pantheon's [`push-to-pantheon`](https://github.com/pantheon-systems/push-to-pantheon)
Action is still Early Access (0.9.6); pin 0.9.4 or later.

</details>

<details>
<summary><b>Upgrading from v1</b></summary>

1. `composer require --dev thronedigital/drupal-qa:^2`
2. Delete `pr-checks.yml`, `multidev.yml`, `multidev-cleanup.yml`, `deploy-pantheon.yml`;
   add the workflow from step 2. `phpcs_required: true` becomes `required: phpcs`;
   `run_behat: false` becomes `skip: behat`.
3. A v1 `behat.yml` probably needs its `base_url` removed.

</details>

<details>
<summary><b>Releasing</b></summary>

Sites use `@v2`, a tag that moves with every release:

```bash
git tag v2.0.3 && git tag -f v2 v2.0.3
git push origin v2.0.3 && git push -f origin v2
```

</details>

MIT licensed.
