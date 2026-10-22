# drupal-qa

CI for Drupal sites on Pantheon. Every pull request gets code checks and its own
multidev; every merge deploys to dev. Each deploy then waits until Pantheon is
actually serving the new code before it runs database updates, imports config and
smoke-tests the site.

- [Install](#install)
- [What runs](#what-runs)
- [Options](#options)
- [Install with Claude Code](#install-with-claude-code)
- [Pantheon's GitHub integration and drupal-qa](#pantheons-github-integration-and-drupal-qa)
- [Writing your own Behat tests](#writing-your-own-behat-tests)
- [Troubleshooting](#troubleshooting)
- [Upgrading from v1](#upgrading-from-v1)

## Install

**1. Add the package:**

```bash
composer require --dev thronedigital/drupal-qa
```

It brings PHPCS (Drupal standard), PHPStan with `phpstan-drupal`, PHPUnit and
Behat. You don't need to copy any config into the project. When the project has
its own `phpunit.xml`, `phpstan.neon` or `behat.yml`, CI uses that. Otherwise it
uses the package's defaults.

**2. Commit `.github/workflows/drupal-qa.yml`:**

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

**3. Add two secrets** under *Settings → Secrets and variables → Actions*. If you
add them once at organization level, every repository in the org can use them.

| Secret | What it is |
|---|---|
| `PANTHEON_MACHINE_TOKEN` | Pantheon dashboard → your account → *Machine Tokens*. |
| `PANTHEON_SSH_KEY` | The private half of a key on a Pantheon account that can reach the site. Make it RSA (`ssh-keygen -t rsa -b 4096 -m PEM`), because Terminus refuses ed25519 keys. |

The workflow passes the two secrets by name because `secrets: inherit` doesn't
reach a workflow in another account or organization.

That's the whole install. Open a pull request to see it run.

## What runs

| When | What happens |
|---|---|
| A pull request is opened or pushed | Code checks and PHPUnit run first. The code then goes to multidev `pr-N`, created from live the first time. drupal-qa waits until `pr-N` is serving the new code, then runs `updatedb`, `config:import` and `cache:rebuild`, checks `config:status` and runs Behat. The PR gets a comment with the URL and a results table. |
| The default branch is pushed (a merge) | The same steps, against `dev`. |
| A pull request is closed | `pr-N` is deleted. |

**What it checks:** PHPCS on your custom modules, profiles and every non-contrib
theme; PHPStan; yamllint on the config sync directory (syntax errors and duplicate keys, which stop an import); `composer audit`; a
[gitleaks](https://github.com/gitleaks/gitleaks) scan of the commits the change
adds; PHPUnit (unit, kernel and the package's own smoke tests); and Behat against
the deployed environment.

Some things it guarantees:

- **Nothing reports green without running.** A step that crashes or runs zero tests
  counts as failed. A check that only warns still shows ⚠️ in the run summary and
  in an annotation; it never shows as a pass.
- **It doesn't race Pantheon.** Pantheon's code log and workflow status both say a
  deploy is done before the container serves the new files. So drupal-qa picks a
  file the commit changed and polls its hash on the environment until it matches.
  Only then does it run `updatedb` and `config:import`.
- **Multidev builds queue; they never cancel.** Cancelling `multidev:create` part
  way through leaves a half-built environment that Pantheon can't roll back. A new
  push waits for the build already running, and so does closing the PR.
- **Pantheon's bot protection doesn't break the smoke tests.** Pantheon's
  next-generation CDN challenges automated traffic. That challenge is a 403 that
  looks exactly like Drupal denying access. CI fetches the site's bot-bypass token
  with the machine token it already has, and sends it on every Behat request. If a
  request is challenged anyway, the step fails instead of passing.

## Options

Every option has a default. Add one only when you want to change it:

```yaml
    with:
      pantheon_site: my-site
      required: phpcs phpunit   # these block a merge or deploy instead of warning
      skip: behat               # these don't run at all
      code_host: github-app     # Pantheon's GitHub App deploys this site; see below
      multidev: false           # the site has no multidev: pull requests get checks only
```

| Option | Default | Meaning |
|---|---|---|
| `pantheon_site` | none | The site's machine name. Not needed with `code_host: none`. |
| `required` | empty | Checks that fail the run instead of warning. |
| `skip` | empty | Steps that don't run. |
| `code_host` | `pantheon` | `pantheon`: drupal-qa pushes the code. `github-app`: Pantheon's GitHub App pushes it, and drupal-qa does the rest. `none`: checks only, nothing deployed. |
| `multidev` | `true` | Multidev needs a Gold workspace or higher. Set `false` below that. |

The names you can use in `required` and `skip` are `phpcs`, `phpstan`, `yamllint`,
`audit`, `secrets`, `phpunit`, `behat` and `config` (the post-deploy
`config:status`). `skip` also takes `updatedb` and `cim`.

**Nothing blocks a merge unless you ask it to**, with two exceptions:

- **PHPUnit blocks by default**, because a failing test means the site is broken.
- **`updatedb` and `config:import` can be skipped but never downgraded to a
  warning.** When they run and fail, the environment is broken.

To adopt gradually, start with the defaults, fix what the warnings show, and then
list the clean checks in `required`.

The rest is detected rather than configured:

- the PHP version, from `composer.json` `config.platform.php`, then `pantheon.yml`;
- which paths to check;
- the config sync directory;
- whether to run the Commerce smoke tests (yes when `drupal/commerce` is in
  `composer.lock`);
- the site's UUID.

## Install with Claude Code

Paste this into Claude Code from the site's repository root. It works out what it
can from the code, asks only what it can't, and shows you the file before writing
anything.

```text
Install thronedigital/drupal-qa (https://github.com/DanePete/drupal-qa) in this
Drupal project, which is hosted on Pantheon. Read that repository's README first.
Its "Install" and "Options" sections are the source of truth for the workflow
file and its inputs.

1. Work out what you can from the code, without asking:
   - the Pantheon site machine name. Look in .ddev/config.yaml, the git
     remotes, pantheon.yml, the project README and scripts. Never derive it
     from the site's display name or the repository name; if it isn't written
     down anywhere, it's a question for step 3;
   - whether ddev is used (if so, run composer as `ddev composer`);
   - the default branch, from `gh repo view --json defaultBranchRef`;
   - any existing .github/workflows files, especially v1 drupal-qa files
     (pr-checks.yml, multidev.yml, multidev-cleanup.yml, deploy-pantheon.yml
     calling DanePete/drupal-qa@v1), or a drupal-qa.yml that's already there
     (update it; don't add a second);
   - whether the project already has phpunit.xml, phpstan.neon or behat.yml.
2. Ask me before running any terminus command. If I agree, run only read-only
   ones: `terminus site:info <site>` to confirm the site, and
   `terminus multidev:list <site>` to see whether multidev is available.
3. Ask me only what you could not settle, in one multiple-choice round, with
   your recommendation first:
   - the site machine name, if you didn't find it;
   - Does Pantheon's GitHub App deploy this site (code_host: github-app), or does
     its code live in Pantheon's git repository (code_host: pantheon, the usual
     case)?
   - Does the site have multidev? Ask only if terminus did not tell you.
   Don't ask about strictness. The defaults warn and never block, which is the
   right start.
4. Create a branch named chore/drupal-qa. Then:
   - run `composer require --dev thronedigital/drupal-qa`;
   - write .github/workflows/drupal-qa.yml from the README, with only the inputs
     that differ from the defaults, and the push trigger set to the default
     branch;
   - if v1 drupal-qa is present, remove its four workflow files (the composer
     require above moves thronedigital/drupal-qa to v2);
   - show me the workflow file and the composer.json change, list the packages
     the lock file adds, and wait for my OK before committing.
5. Check that the secrets PANTHEON_MACHINE_TOKEN and PANTHEON_SSH_KEY exist, with
   `gh secret list`, and for an organization `gh secret list --org <org>`. Listing
   org secrets needs org admin; if that fails, tell me the org level wasn't
   checked. Never ask me to paste a secret into the chat. If one is missing, give
   me the exact `! gh secret set NAME` command to run myself, and remind me that
   the SSH key must be RSA.
6. Commit. Ask me before pushing and opening the pull request. Then watch the
   run with `gh run watch` and explain its summary table to me, step by step.
```

## Pantheon's GitHub integration and drupal-qa

Pantheon now offers two ways to get code from GitHub to Pantheon. People reasonably
ask whether that makes drupal-qa unnecessary. Not quite: Pantheon's tools move
**code**, while drupal-qa moves code **and checks the result**. The two work
together.

### What Pantheon shipped

- **The GitHub Application.** Generally available since April 2026 for Gold,
  Platinum and Diamond workspaces; GitLab support arrived in August. Your GitHub
  repository *is* the site's repository. Pantheon creates a multidev for each open
  pull request and deploys the default branch to dev. You configure nothing in
  Actions and need no secrets. ([docs](https://docs.pantheon.io/guides/external-repositories/github),
  [announcement](https://docs.pantheon.io/release-notes/2026/04/github-application-ga))
- **The `push-to-pantheon` GitHub Action.** Pantheon's own action for pushing code
  to dev and to per-PR multidevs from your workflow. It is labelled *Early Access*,
  and its README says: "Only teams with pre-existing Continuous Integration
  pipelines that they could fall back to, should try this repository at this
  time." ([repository](https://github.com/pantheon-systems/push-to-pantheon))

### What the GitHub App is and isn't

**It is:**

- A connection between a GitHub or GitLab repository and a Pantheon site, so code
  moves without a CI pipeline.
- Automatic multidevs for pull requests, and automatic deploys of the default
  branch to dev.
- Pantheon running `composer install` (Integrated Composer) on each deploy.

**It isn't:**

- **Available on every plan.** It needs a Gold, Platinum or Diamond workspace.
- **A switch for an existing site.** It's chosen when a site is created
  (`terminus site:create … --vcs-provider=github`, or "use an existing
  repository" for a repository already in Pantheon's layout). Pantheon documents
  no way to move an existing site's code over. For a site like that, the realistic
  path is a new site plus a database, files and domain migration. Ask Pantheon
  support before promising it.
- **A test runner.** Nothing in it runs PHPCS, PHPStan, PHPUnit or smoke tests,
  and nothing stops a merge that breaks the site from deploying.
- **A Drupal deploy.** Pantheon doesn't document running `updatedb` or
  `config:import` after the code lands, or checking that config matches.
- **A front-end build.** Pantheon runs `composer install` only, not `npm run build`.
- **SFTP mode.** These sites have no SFTP mode and no Pantheon git repository.

### Side by side

| | Pantheon GitHub App | `push-to-pantheon` Action | drupal-qa |
|---|---|---|---|
| **Plan** | Gold, Platinum, Diamond | Any | Any (multidev needs Gold or higher) |
| **Maturity** | Generally available | Early Access, before 1.0 | v2 |
| **Existing sites** | Chosen at site creation; no documented conversion | Yes | Yes |
| **Moves code to Pantheon** | Yes | Yes | Yes, or leaves it to the GitHub App (`code_host: github-app`) |
| **Multidev per pull request** | Yes | Yes (`pr-N` or named after the branch) | Yes (`pr-N`) |
| **Deletes the multidev when the PR closes** | Not documented | On a later run, with `delete_old_environments` | Yes, when the PR closes |
| **Builds** | `composer install` | Whatever steps you add | Pantheon's Integrated Composer |
| **PHPCS, PHPStan, PHPUnit, secret scan** | No | No (add your own jobs) | Yes; warn by default, block when listed in `required` |
| **Can stop a broken deploy** | No | Only through jobs you add | Yes, for checks listed in `required` |
| **`updatedb` and `config:import`** | Not documented | No | Yes, once the new code is served |
| **Checks the environment serves the new code** | No | No | Yes, by comparing a file's hash on the container |
| **Smoke tests against the environment** | No | No (its example runs your own Playwright job) | Behat, including logged-in pages |
| **Gets through Pantheon's bot protection** | Not applicable | Not applicable | Yes, with the site's bot-bypass token |
| **Reports back on the PR** | Not documented | GitHub Deployments in the PR timeline | Run summary and PR comment |
| **Secrets you manage** | None | SSH key and machine token | SSH key and machine token (once per organization) |

Where a cell says "not documented", Pantheon's documentation doesn't say either
way. It doesn't mean "no".

### Using drupal-qa with the GitHub App

Set `code_host: github-app`. drupal-qa then doesn't push anything. It waits for
Pantheon to create `pr-N` (or to deploy dev), and from there does everything it
normally does: waits for the new code, runs `updatedb` and `config:import`, checks
config and runs Behat. Two caveats:

- **Merges deploy anyway.** Pantheon deploys whatever reaches the default branch,
  so drupal-qa can't stop a deploy. To stop a merge, make drupal-qa's checks
  required in the branch protection rules.
- **`pr-N` naming is assumed.** Pantheon doesn't document how the GitHub App names
  a pull request's environment, and this mode assumes `pr-N` until it has been
  confirmed on a live GitHub App site.

## Writing your own Behat tests

Put `.feature` files in `tests/behat/features/`. They run with the package's smoke
tests and use the steps from the Drupal Extension and Mink, plus these:

- `Given I am logged in as a new user with the "editor" role`. This creates a user
  on the environment through Drush, logs in with a one-time login link, and
  deletes the user after the scenario. The Drupal Extension's own "logged in as a
  user with the role" step can't create users on a remote site from version 5.3
  on.
- `Then I should see the ".selector" element`
- `Then I should not see the ".selector" element`

Every scenario starts logged out. If you want your own step definitions, extend
`DrupalQa\Behat\FeatureContext` and give the project its own `behat.yml`.

## Troubleshooting

**"Pantheon's bot protection challenges requests from CI".** The site is on
Pantheon's next-generation CDN and no bypass token reached the request. Check that
`terminus gcdn:bot-bypass <site>` returns a token when it runs as the account that
owns the machine token.

**"Could not create multidev pr-N".** The site has reached its multidev limit (delete
an unused one), or it has no multidev (set `multidev: false`).

**"Pantheon's master has commits this branch does not".** Someone committed on
Pantheon: from the dashboard in SFTP mode, or through an Autopilot update. Merge
Pantheon's `master` into GitHub first. drupal-qa won't push over those commits.

**"still serves the old file after 15 minutes".** Pantheon's code log can show
your commit while the container still runs the old build. Pushing an empty commit
gives Pantheon a new commit to sync, and that usually clears it:
`git commit --allow-empty -m "chore: re-sync" && git push`.

**A new Pantheon site has both `main` and `master`.** Dev deploys from `master`;
`main` is the untouched starting template. Push `master` to GitHub as your default
branch.

**PHPStan reports a lot on the first run.** It only warns until you add `phpstan`
to `required`. The default is level 1. For a stricter level, give the project a
`phpstan.neon`.

## Upgrading from v1

v1 was `thronedigital/drupal-qa` 1.x, with four workflow files from `DanePete/drupal-qa`.
Its tags stay where they are, so nothing breaks until you move. To move:

1. `composer require --dev thronedigital/drupal-qa:^2`.
2. Delete `pr-checks.yml`, `multidev.yml`, `multidev-cleanup.yml` and
   `deploy-pantheon.yml`, and add the single workflow from [Install](#install).
   Map the old inputs like this:
   - `phpcs_required: true` becomes `required: phpcs`.
   - `phpcs_paths` and `php_version` are detected now.
   - `run_behat: false` becomes `skip: behat`.
3. If v1 put `grumphp.yml.dist`, `CLAUDE.md` or `.github/copilot-instructions.md`
   into the project, v2 no longer manages them. Keep or delete them as you like.

Behat in v1 never reached the multidev. Its requests went to localhost, and its
logged-in scenarios couldn't create users. A project-specific `behat.yml` written
against v1 probably needs its `base_url` removed (CI sets it), and its login steps
switched to `I am logged in as a new user with the "…" role`.

## Releasing

Sites reference the workflow as `@v2`, which is a tag that moves. Every release
tags the exact version, then moves `v2` to the same commit. If `v2` isn't moved,
every site on `@v2` keeps running old code; v1 shipped a fix that never reached
`@v1` this way.

```bash
git tag v2.0.1 && git tag -f v2 v2.0.1
git push origin v2.0.1 && git push -f origin v2
```

Test a change first on a sandbox site by pointing its workflow at `@main`.

## License

MIT
