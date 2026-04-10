# drupal-qa

Reusable CI/QA toolchain for Drupal projects. One `composer require` gives you PHPUnit, PHPCS, PHPStan, Behat, and GrumPHP with sensible defaults, generic smoke tests, and reusable GitHub Actions workflows for Pantheon.

## Prerequisites

- A Drupal 10+ project using Composer
- A Pantheon hosting account (for deploy/multidev workflows)
- A GitHub repository
- PHP 8.2+

## Quick Setup

### Option A: Interactive Setup Script

Run this from your Drupal project root — it handles everything:

```bash
bash <(curl -s https://raw.githubusercontent.com/DanePete/drupal-qa/main/scripts/setup.sh)
```

The script will:

1. Ask for your Pantheon site name, UUID, and preferences
2. Generate all 4 workflow files
3. Create a FeatureContext extending the base
4. Add `thronedigital/drupal-qa` to `allowed-packages` in your `composer.json`
5. Run `composer require --dev thronedigital/drupal-qa`

The only manual step left is adding GitHub secrets (see [Required Secrets](#required-secrets)).

### Option B: AI Prompt

Copy this prompt into Claude, ChatGPT, or any AI assistant:

```text
I'm setting up a Drupal project that deploys to Pantheon. I need you to generate
the GitHub Actions workflow files and composer.json changes to use the
thronedigital/drupal-qa package.

Here's my project info:
- Pantheon site machine name: [YOUR_SITE_NAME]
- Pantheon site UUID: [found in dashboard URL: dashboard.pantheon.io/workspace/.../cms-site/{UUID}/... or via `terminus site:info SITE --field=id`]
- PHP version: [8.3]
- PHPCS should block PRs: [yes/no]
- PHPStan should block PRs: [yes/no]
- Custom theme paths to scan: [e.g. web/themes/custom/]
- Has Drupal Commerce: [yes/no]
- Run Behat tests on multidev: [yes/no]

Generate the following files:

1. `.github/workflows/pr-checks.yml` — calls DanePete/drupal-qa pr-checks workflow
2. `.github/workflows/deploy-pantheon.yml` — calls DanePete/drupal-qa deploy workflow
3. `.github/workflows/multidev.yml` — calls DanePete/drupal-qa multidev workflow
4. `.github/workflows/multidev-cleanup.yml` — calls DanePete/drupal-qa cleanup workflow
5. `tests/behat/bootstrap/FeatureContext.php` — extends DrupalQa base context
6. Show me the composer.json changes needed (add thronedigital/drupal-qa to
   require-dev and allowed-packages)

Reference the workflow inputs documented at:
https://github.com/DanePete/drupal-qa#workflow-inputs
```

### Option C: Manual Setup

See [Installation](#installation) and [GitHub Actions Setup](#github-actions-setup) below.

## Installation

```bash
composer require --dev thronedigital/drupal-qa
```

Add the package to your `allowed-packages` in `composer.json`:

```json
{
  "extra": {
    "drupal-scaffold": {
      "allowed-packages": [
        "thronedigital/drupal-qa"
      ]
    }
  }
}
```

Run `composer install` — the following files will be scaffolded to your project root:

- `phpunit.xml.dist` — PHPUnit config with auto-discovery of custom module tests
- `phpstan.neon.dist` — PHPStan level 1, scans `web/modules/custom/` and `web/themes/`
- `grumphp.yml.dist` — pre-commit hooks (debug function blacklist, PHPCS, PHPStan)
- `behat.yml.dist` — Behat config with `BEHAT_BASE_URL` env var support

Add the scaffolded `.dist` files to your `.gitignore` — they're regenerated on every `composer install`:

```text
/behat.yml.dist
/grumphp.yml.dist
/phpstan.neon.dist
/phpunit.xml.dist
```

## What's Included

### Dev Dependencies

All pulled in automatically:

- `drupal/coder` — PHPCS Drupal coding standards
- `phpstan/phpstan` + `mglaman/phpstan-drupal` — static analysis
- `phpunit/phpunit` — unit and kernel testing
- `phpro/grumphp` — pre-commit hooks
- `behat/behat` + `drupal/drupal-extension` — behavioral testing
- `drevops/behat-steps` — 40+ reusable Behat step definition traits
- `drevops/behat-screenshot` — automatic screenshots on Behat failures

### Generic Smoke Tests

**PHPUnit** (run automatically via `drupal-qa` test suite):

- `ComposerValidationTest` — validates composer.json, checks local patches exist
- `ModuleInfoTest` — validates all custom module .info.yml files
- `DrupalBootstrapTest` — confirms PHPUnit can bootstrap Drupal

**Behat** (tagged `@drupal-qa`):

- `authentication.feature` — login page, admin access denied, authenticated profile
- `access_control.feature` — admin routes blocked for anonymous
- `content_pages.feature` — homepage loads, 404 works
- `cart.feature` (commerce) — cart page, empty cart message
- `catalog.feature` (commerce) — product listing loads

### Reusable GitHub Actions Workflows

Located in `.github/workflows/`. These use `workflow_call` so your project references them with ~10 lines each.

## GitHub Actions Setup

### 1. PR Checks

Create `.github/workflows/pr-checks.yml`:

```yaml
name: PR Checks
on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]
jobs:
  checks:
    uses: DanePete/drupal-qa/.github/workflows/pr-checks.yml@v1
    with:
      phpcs_required: false    # set true when codebase is clean
      phpstan_required: false  # set true when codebase is clean
    secrets: inherit
```

### 2. Deploy to Pantheon

Create `.github/workflows/deploy-pantheon.yml`:

```yaml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    uses: DanePete/drupal-qa/.github/workflows/deploy-pantheon.yml@v1
    with:
      pantheon_site: my-site-name
      pantheon_site_id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    secrets: inherit
```

### 3. Multidev Per PR

Create `.github/workflows/multidev.yml`:

```yaml
name: Multidev
on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]
jobs:
  multidev:
    uses: DanePete/drupal-qa/.github/workflows/multidev.yml@v1
    with:
      pantheon_site: my-site-name
      pantheon_site_id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    secrets: inherit
```

### 4. Multidev Cleanup

Create `.github/workflows/multidev-cleanup.yml`:

```yaml
name: Multidev Cleanup
on:
  pull_request:
    branches: [main]
    types: [closed]
jobs:
  cleanup:
    uses: DanePete/drupal-qa/.github/workflows/multidev-cleanup.yml@v1
    with:
      pantheon_site: my-site-name
    secrets: inherit
```

### Required Secrets

Set these in your GitHub repo under **Settings > Secrets and variables > Actions**:

| Secret | Where to get it |
| ------ | --------------- |
| `PANTHEON_SSH_KEY` | Generate a keypair (`ssh-keygen -t ed25519`), add the public key to Pantheon dashboard > Account > SSH Keys, paste the private key as the secret |
| `PANTHEON_MACHINE_TOKEN` | Pantheon dashboard > Account > Machine Tokens > Create Token |

### Finding Your Pantheon Site UUID

Your site UUID is in the Pantheon dashboard URL:

```text
https://dashboard.pantheon.io/workspace/.../cms-site/{SITE-UUID}/environment/...
```

Or via Terminus:

```bash
terminus site:info my-site-name --field=id
```

## Gradual Adoption

When you first install this on an existing project, you'll likely have PHPCS and PHPStan violations. The `phpcs_required` and `phpstan_required` flags let you adopt gradually:

```yaml
# Day 1: report violations but don't block anything
phpcs_required: false
phpstan_required: false

# After cleaning up PHPCS violations: start enforcing
phpcs_required: true
phpstan_required: false

# After cleaning up PHPStan violations: full enforcement
phpcs_required: true
phpstan_required: true
```

When set to `false`, violations show as warnings in the PR checks but won't block the merge.

To change these, just edit the value in your `.github/workflows/pr-checks.yml` (and `deploy-pantheon.yml` if you have one) and commit. It's one line.

**AI prompt to clean up violations:**

```text
Run `./vendor/bin/phpcs --standard=Drupal --extensions=php,module,inc,install,theme
web/modules/custom/` and fix every violation. Group fixes into logical commits
(one per module or one per violation type). Don't change any logic — only
formatting, spacing, docblocks, and naming conventions.
```

```text
Run `./vendor/bin/phpstan analyse --configuration=phpstan.neon --no-progress` and
fix every error. For each fix, explain what was wrong and why the fix is correct.
Don't suppress errors with @phpstan-ignore unless there's genuinely no other option.
```

## Workflow Inputs

### pr-checks.yml

| Input | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `php_version` | string | `8.3` | PHP version |
| `phpcs_required` | boolean | `true` | Block PR on PHPCS failures |
| `phpstan_required` | boolean | `false` | Block PR on PHPStan failures |
| `phpcs_paths` | string | `web/modules/custom/ web/themes/custom/` | Paths to scan |
| `yamllint_enabled` | boolean | `true` | Lint config/ YAML files |

### deploy-pantheon.yml

| Input | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `php_version` | string | `8.3` | PHP version |
| `pantheon_site` | string | required | Site machine name |
| `pantheon_site_id` | string | required | Site UUID |
| `phpcs_required` | boolean | `true` | Block deploy on PHPCS failures |
| `phpstan_required` | boolean | `false` | Block deploy on PHPStan failures |
| `phpcs_paths` | string | `web/modules/custom/ web/themes/custom/` | Paths to scan |
| `yamllint_enabled` | boolean | `true` | Lint config/ YAML files |

### multidev.yml

| Input | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `php_version` | string | `8.3` | PHP version |
| `pantheon_site` | string | required | Site machine name |
| `pantheon_site_id` | string | required | Site UUID |
| `run_behat` | boolean | `true` | Run Behat tests against multidev |
| `behat_tags` | string | `smoke` | Behat tag filter |
| `source_env` | string | `live` | Environment to clone from |

### multidev-cleanup.yml

| Input | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `pantheon_site` | string | required | Site machine name |

## Adding Project-Specific Tests

### PHPUnit

Create tests in your custom modules — they're auto-discovered:

```text
web/modules/custom/my_module/tests/src/Unit/MyServiceTest.php
```

```php
<?php

namespace Drupal\Tests\my_module\Unit\Service;

use Drupal\my_module\Service\PriceCalculator;
use Drupal\Tests\UnitTestCase;
use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Config\ImmutableConfig;

/**
 * @coversDefaultClass \Drupal\my_module\Service\PriceCalculator
 * @group my_module
 */
class PriceCalculatorTest extends UnitTestCase {

  /**
   * The service under test.
   */
  protected PriceCalculator $calculator;

  /**
   * {@inheritdoc}
   */
  protected function setUp(): void {
    parent::setUp();

    // Mock the config factory to return a tax rate.
    $config = $this->createMock(ImmutableConfig::class);
    $config->method('get')
      ->with('tax_rate')
      ->willReturn(0.08);

    $configFactory = $this->createMock(ConfigFactoryInterface::class);
    $configFactory->method('get')
      ->with('my_module.settings')
      ->willReturn($config);

    $this->calculator = new PriceCalculator($configFactory);
  }

  /**
   * Tests price calculation with tax.
   */
  public function testCalculateWithTax(): void {
    $result = $this->calculator->calculateTotal(100.00);
    $this->assertEquals(108.00, $result);
  }

  /**
   * Tests that zero price returns zero.
   */
  public function testZeroPriceReturnsZero(): void {
    $this->assertEquals(0.00, $this->calculator->calculateTotal(0));
  }

  /**
   * Tests that negative prices throw an exception.
   */
  public function testNegativePriceThrowsException(): void {
    $this->expectException(\InvalidArgumentException::class);
    $this->calculator->calculateTotal(-50.00);
  }

}
```

No config changes needed. The wildcard in `phpunit.xml.dist` picks it up.

### Using AI to Generate Unit Tests

These prompts work well with Claude, ChatGPT, or any AI assistant that can read your codebase.

**Find what to test:**

```text
Look at my custom modules in web/modules/custom/. For each module, identify
services, plugins, and utility classes that have testable business logic.
Rank them by complexity and tell me which ones would benefit most from
unit tests. Skip simple CRUD or pass-through services.
```

**Generate tests for a specific service:**

```text
Read web/modules/custom/my_module/src/Service/MyService.php and generate
PHPUnit unit tests for it. The test should:
- Extend Drupal\Tests\UnitTestCase
- Live at web/modules/custom/my_module/tests/src/Unit/Service/MyServiceTest.php
- Mock all injected dependencies
- Test each public method including edge cases
- Follow Drupal coding standards
```

**Generate tests for all services in a module:**

```text
Read all files in web/modules/custom/my_module/src/ and generate unit tests
for every service and plugin that has logic worth testing. Put each test in
the correct namespace under web/modules/custom/my_module/tests/src/Unit/.
Mock dependencies using PHPUnit mock builder or Prophecy. Skip tests for
classes that are just wiring (empty constructors, single-line delegation).
```

**Generate tests based on existing patterns:**

```text
Look at the existing unit tests in web/modules/custom/ to understand the
testing patterns and style used in this project. Then find custom modules
that don't have tests yet and generate tests that follow the same patterns.
```

**Generate Behat features from manual QA steps:**

```text
I manually test this site by doing the following:
1. Log in as an admin
2. Go to /admin/commerce/orders and verify the page loads
3. Create a test order and verify it appears in the list
4. Log out and verify I can't access /admin

Convert these manual steps into Behat .feature files using Gherkin syntax.
Use step definitions from drupal/drupal-extension and drevops/behat-steps.
Put the files in tests/behat/features/.
```

**Audit existing test coverage:**

```text
Compare the custom modules in web/modules/custom/ against the test files
in each module's tests/ directory. Give me a coverage report showing:
- Modules with no tests at all
- Services/plugins that exist but have no corresponding test
- Test files that exist but may be outdated (testing methods that no longer exist)
```

### Behat

Add `.feature` files in `tests/behat/features/` — they run alongside the package features.

Create a `FeatureContext` that extends the base:

```php
<?php

use DrupalQa\Behat\FeatureContext as BaseFeatureContext;
use DrevOps\BehatSteps\Drupal\ContentTrait;
use DrevOps\BehatSteps\Drupal\UserTrait;

class FeatureContext extends BaseFeatureContext {
  use ContentTrait;
  use UserTrait;
}
```

#### Available drevops/behat-steps Traits

These traits from `drevops/behat-steps` can be added to your FeatureContext with `use`:

**Drupal-specific:**
`ContentTrait`, `UserTrait`, `TaxonomyTrait`, `MediaTrait`, `FileTrait`, `MenuTrait`, `ParagraphsTrait`, `BlockTrait`, `EckTrait`, `EmailTrait`, `QueueTrait`, `SearchApiTrait`, `WebformTrait`, `WatchdogTrait`, `ModuleTrait`, `BigPipeTrait`, `OverrideTrait`

**Generic (no Drupal dependency):**
`CookieTrait`, `DateTrait`, `ElementTrait`, `FieldTrait`, `FileDownloadTrait`, `IframeTrait`, `JavascriptTrait`, `KeyboardTrait`, `LinkTrait`, `PathTrait`, `ResponseTrait`, `WaitTrait`

Full docs: [drevops/behat-steps](https://github.com/drevops/behat-steps)

### Commerce Behat Suite

The `behat.yml.dist` includes a separate `commerce` suite that loads features from `vendor/thronedigital/drupal-qa/tests/behat/features/commerce/`. This runs automatically if the suite is included.

To skip commerce tests, override `behat.yml.dist` with your own `behat.yml` that only includes the `default` suite, or run Behat with a suite filter:

```bash
./vendor/bin/behat --suite=default
```

## Customizing Configs

**AI prompt to tailor configs to your project:**

```text
Look at my project structure — custom modules in web/modules/custom/, themes
in web/themes/. Read the scaffolded phpstan.neon.dist, phpunit.xml.dist,
grumphp.yml.dist, and behat.yml.dist. Create customized versions (without
.dist) that are tuned to this specific project. For example:
- Add any extra theme paths to PHPCS scanning
- Add region_map entries to behat.yml that match my actual theme regions
- Adjust PHPStan ignored errors if needed for my specific contrib modules
```

If you need to override a scaffolded config, copy it and remove the `.dist` extension:

```bash
cp phpstan.neon.dist phpstan.neon
```

Then edit `phpstan.neon`. The `.dist` file won't overwrite your customized version.

To prevent a specific file from being scaffolded:

```json
{
  "extra": {
    "drupal-scaffold": {
      "file-mapping": {
        "[project-root]/grumphp.yml.dist": false
      }
    }
  }
}
```

## Optional Extras

After the base setup, you can add deeper code quality checks with a second script:

```bash
bash <(curl -s https://raw.githubusercontent.com/DanePete/drupal-qa/main/scripts/setup-extras.sh)
```

Pick and choose from:

| Extra | What it does |
| ----- | ------------ |
| PHPStan strict (level 5+) | Catches hallucinated methods, wrong types, bad Drupal API usage |
| Security scanning | OWASP checks for SQL injection, XSS, command injection in custom code |
| Unused code detection | Finds dead code, unused imports, unreachable methods |
| Composer normalize | Enforces consistent composer.json formatting |
| Rector dry-run | Detects deprecated Drupal API usage and suggests automated fixes |

Extras run in a separate `pr-extras.yml` workflow so they **never block your main PR checks**. They report issues as warnings only.

## Upgrading

To get the latest configs and tests:

```bash
composer update thronedigital/drupal-qa
```

Scaffolded `.dist` files will be refreshed. Your custom overrides (files without `.dist`) won't be touched.

## Debugging CI Failures

**AI prompt when a workflow fails:**

```text
My GitHub Actions PR check failed. Here's the error output:

[paste the failed step output here]

Tell me what went wrong, how to fix it, and whether this is a real issue
or a config problem with drupal-qa.
```

**AI prompt to add missing Behat steps:**

```text
My Behat test failed with "step not defined" errors. Here are the undefined steps:

[paste the undefined step errors here]

Tell me which drevops/behat-steps trait I need to add to my FeatureContext,
or write a custom step definition if no existing trait covers it.
```

## Troubleshooting

**GrumPHP conflicts with existing config:**
If your project already has a `grumphp.yml`, it takes precedence over `grumphp.yml.dist`. Either update your existing config or delete it to use the scaffolded defaults.

**PHPCS/PHPStan failing on first install:**
Set `phpcs_required: false` and `phpstan_required: false` in your workflow files to unblock CI while you clean up existing violations. See [Gradual Adoption](#gradual-adoption).

**Scaffolded files not appearing:**
Make sure `thronedigital/drupal-qa` is in your `allowed-packages`:

```json
"extra": {
  "drupal-scaffold": {
    "allowed-packages": ["thronedigital/drupal-qa"]
  }
}
```

Then run `composer install` again.

**Behat commerce tests failing (no Commerce installed):**
Run only the default suite: `./vendor/bin/behat --suite=default`

## License

MIT
