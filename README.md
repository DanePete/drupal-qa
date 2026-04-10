# drupal-qa

Reusable CI/QA toolchain for Drupal 10+ projects. One `composer require` gives you automated testing, code quality checks, AI-powered PR reviews, and GitHub Actions workflows for Pantheon — with sensible defaults that work out of the box.

## Table of Contents

- [What You Get](#what-you-get)
- [Quick Setup](#quick-setup)
- [Gradual Adoption](#gradual-adoption)
- [AI PR Reviews](#ai-pr-reviews)
- [Using AI to Generate Tests](#using-ai-to-generate-tests)
- [Debugging CI Failures](#debugging-ci-failures)

**Reference:**

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [What's Included](#whats-included)
- [GitHub Actions Setup](#github-actions-setup)
- [Workflow Inputs](#workflow-inputs)
- [Adding Project-Specific Tests](#adding-project-specific-tests)
- [Customizing Configs](#customizing-configs)
- [Optional Extras](#optional-extras)
- [Opinionated Defaults](#opinionated-defaults)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)

## What You Get

- **Automated PR checks** — PHPCS, PHPStan, YAML lint, security audit, PHPUnit on every pull request
- **Secret scanning** — Gitleaks scans every PR for accidentally committed API keys, passwords, tokens, and credentials before they reach production
- **Preview environments** — Pantheon multidev created automatically for each PR
- **Smoke tests** — Behat tests verify login, access control, homepage, and commerce flows
- **Pre-commit hooks** — GrumPHP catches debug code and coding violations before you push
- **AI PR reviews** — GitHub Copilot reviews every PR for Drupal-specific issues (optional)
- **AI coding instructions** — CLAUDE.md scaffolded with Drupal best practices for Claude Code, Cursor, etc.
- **Ready-to-use AI prompts** — generate unit tests, fix violations, debug CI failures

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
4. Add `.dist` files to `.gitignore`
5. Add `thronedigital/drupal-qa` to `allowed-packages` in your `composer.json`
6. Run `composer require --dev thronedigital/drupal-qa`

The only manual step left is adding GitHub secrets (see [Required Secrets](#required-secrets)).

### Option B: AI Prompt

Copy this prompt into an AI coding tool that can read your codebase (Claude Code, Cursor, Copilot, Windsurf, etc.):

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
7. Add the scaffolded .dist files to .gitignore (behat.yml.dist, grumphp.yml.dist,
   phpstan.neon.dist, phpunit.xml.dist)

Reference the workflow inputs documented at:
https://github.com/DanePete/drupal-qa#workflow-inputs
```

### Option C: Manual Setup

See [Installation](#installation) and [GitHub Actions Setup](#github-actions-setup) below.

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

## AI PR Reviews

The package scaffolds a `.github/copilot-instructions.md` that tells GitHub Copilot how to review PRs for this project:

- Deprecated Drupal API usage
- Security issues (XSS, SQL injection, missing access checks)
- `\Drupal::` static calls that should use dependency injection
- Debug code left behind (ksm, kint, var_dump)
- Performance issues (entity loads in loops, missing caching)
- Missing config schema, missing services.yml entries
- Hardcoded credentials or API keys

This is **optional** and requires a GitHub Copilot Business or Enterprise subscription. To enable: go to your repo's **Settings > Copilot > Code review** and turn it on. Then assign `@copilot` as a reviewer on any PR, or set up a ruleset to do it automatically. The instructions file works automatically once Copilot code review is enabled — no extra setup needed.

It also scaffolds a `CLAUDE.md` with Drupal-specific instructions for Claude Code — dependency injection rules, security checklist, testing patterns, config management, drush commands, and code style guidelines. Any AI tool that reads `CLAUDE.md` will know how to work with Drupal projects correctly.

## Using AI to Generate Tests

These prompts work with any AI coding tool that can read your codebase (Claude Code, Cursor, Copilot, Windsurf, etc.).

**Find what to test:**

```text
Look at my custom modules in web/modules/custom/. For each module, identify
services, plugins, and utility classes that have testable business logic.
Rank them by complexity and tell me which ones would benefit most from
unit tests. Skip simple CRUD or pass-through services.
```

**Generate tests for a single file:**

```text
Read web/modules/custom/my_module/src/Service/PriceCalculator.php. Write a
PHPUnit unit test for this file. Mock all constructor dependencies. Test
every public method with normal input, edge cases, and expected failures.
Put the test at web/modules/custom/my_module/tests/src/Unit/Service/PriceCalculatorTest.php.
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

**Generate tests for a single module:**

```text
Read everything in web/modules/custom/my_module/. Understand what the module
does, then write unit tests for every service and plugin that has real logic.
Put tests in web/modules/custom/my_module/tests/src/Unit/ with the correct
namespaces. Skip anything that's just glue code with no logic to test.
```

**Generate tests for all modules:**

```text
Read all custom modules in web/modules/custom/. For each module, generate
unit tests for every service and plugin that has logic worth testing. Put
each test in the correct namespace under that module's tests/src/Unit/.
Mock dependencies using PHPUnit mock builder or Prophecy. Skip classes
that are just wiring (empty constructors, single-line delegation).
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

**Write Kernel tests for database-dependent code:**

```text
Read web/modules/custom/my_module/src/Service/OrderLookupService.php. This
service queries the database so it needs a Kernel test, not a Unit test.
Write a KernelTestBase test that:
- Extends Drupal\Tests\my_module\Kernel\MyModuleKernelTestBase (or Drupal\KernelTests\KernelTestBase)
- Lives at web/modules/custom/my_module/tests/src/Kernel/Service/OrderLookupServiceTest.php
- Enables required modules in $modules
- Creates test entities in setUp()
- Tests the actual queries return correct results
```

**Test Drupal plugins (blocks, conditions, field formatters):**

```text
Read web/modules/custom/my_module/src/Plugin/. For each plugin, write a
unit test that:
- Verifies the plugin annotation/attribute has all required properties
- Tests the build/evaluate/viewElements method with mocked dependencies
- Tests access control if the plugin has it
- Tests configuration form defaults
Put tests at web/modules/custom/my_module/tests/src/Unit/Plugin/
```

**Test event subscribers:**

```text
Read web/modules/custom/my_module/src/EventSubscriber/. For each subscriber:
- Test that getSubscribedEvents() returns the correct event mappings
- Test each handler method with a mocked event object
- Test that the subscriber modifies the event correctly
- Test edge cases (empty data, missing fields, etc.)
```

**Test form validation logic:**

```text
Read the custom forms in web/modules/custom/my_module/src/Form/. For each
form that has validation logic in validateForm(), write tests that:
- Submit valid data and verify no errors
- Submit invalid data and verify the correct error messages
- Test boundary values and edge cases
- Mock any services the form injects
```

**Test access control:**

```text
Read all custom routes in web/modules/custom/my_module/my_module.routing.yml
and the corresponding access check classes. Write tests that verify:
- Anonymous users are denied where expected
- Authenticated users with correct permissions are allowed
- Users without the right role/permission are denied
- Custom access checkers return the correct AccessResult
```

**Test migration plugins:**

```text
Read web/modules/custom/my_module/src/Plugin/migrate/. For each process
plugin, write a unit test that:
- Tests transform() with normal input
- Tests transform() with empty/null input
- Tests transform() with malformed input
- Verifies MigrateSkipRowException is thrown when appropriate
```

**Generate tests for REST/API endpoints:**

```text
Read the custom REST resources or controllers in web/modules/custom/my_module/.
Write tests that verify:
- Correct response codes (200, 403, 404, 422)
- Response body structure matches expected schema
- Authentication/authorization is enforced
- Invalid input returns proper error responses
```

**Test cron and queue workers:**

```text
Read web/modules/custom/my_module/src/Plugin/QueueWorker/. For each worker:
- Test processItem() with valid data
- Test processItem() with invalid data (should it throw or skip?)
- Test that RequeueException is thrown when appropriate
- Mock any external services the worker calls
Also check hook_cron implementations in my_module.module and test them.
```

**Security-focused test generation:**

```text
Read all custom modules in web/modules/custom/. For each module, write tests
focused specifically on security:
- Test that all forms sanitize input properly
- Test that SQL queries use parameterized placeholders (no string concat)
- Test that routes return 403 for unauthorized users
- Test that any user-facing output is escaped
- Test that file upload handlers validate extensions and MIME types
```

**Audit existing test coverage:**

```text
Compare the custom modules in web/modules/custom/ against the test files
in each module's tests/ directory. Give me a coverage report showing:
- Modules with no tests at all
- Services/plugins that exist but have no corresponding test
- Test files that exist but may be outdated (testing methods that no longer exist)
```

## Debugging CI Failures

**AI prompt when a workflow fails:**

```text
My GitHub Actions PR check failed. Here's the error output:

[paste the failed step output here]

Tell me what went wrong, how to fix it, and whether this is a real issue
in my code or a config problem with drupal-qa. If it's a drupal-qa problem,
I'll report it at https://github.com/DanePete/drupal-qa/issues
```

**AI prompt to add missing Behat steps:**

```text
My Behat test failed with "step not defined" errors. Here are the undefined steps:

[paste the undefined step errors here]

Tell me which drevops/behat-steps trait I need to add to my FeatureContext,
or write a custom step definition if no existing trait covers it.
```

---

## Reference

Everything below is reference material for manual setup, customization, and troubleshooting.

## Prerequisites

- A Drupal 10+ project using Composer
- A Pantheon hosting account (for deploy/multidev workflows)
- A GitHub repository
- PHP 8.2+

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
- `.github/copilot-instructions.md` — Drupal-specific AI review instructions
- `CLAUDE.md` — Drupal coding instructions for Claude Code

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
 * Tests the PriceCalculator service.
 *
 * @coversDefaultClass \Drupal\my_module\Service\PriceCalculator
 *   ^ Tells PHPUnit which class this test covers (used for coverage reports).
 * @group my_module
 *   ^ Groups this test so you can run just your module's tests:
 *   ./vendor/bin/phpunit --group=my_module
 */
class PriceCalculatorTest extends UnitTestCase {

  /**
   * The service under test.
   */
  protected PriceCalculator $calculator;

  /**
   * Runs before every test method.
   *
   * This is where you set up mocks for the service's dependencies.
   * The real PriceCalculator takes a ConfigFactoryInterface in its
   * constructor (dependency injection). In the test, we create fake
   * versions of those dependencies so we can control their behavior.
   */
  protected function setUp(): void {
    parent::setUp();

    // Create a fake config object that returns 0.08 for 'tax_rate'.
    // In production this would read from Drupal's config system
    // (admin/config), but in the test we hardcode the value so the
    // test doesn't need a database or a running Drupal site.
    $config = $this->createMock(ImmutableConfig::class);
    $config->method('get')
      ->with('tax_rate')
      ->willReturn(0.08);

    // Create a fake config factory that returns our fake config
    // when asked for 'my_module.settings'.
    $configFactory = $this->createMock(ConfigFactoryInterface::class);
    $configFactory->method('get')
      ->with('my_module.settings')
      ->willReturn($config);

    // Now create the real service, injecting our fakes.
    // This is the thing we're actually testing.
    $this->calculator = new PriceCalculator($configFactory);
  }

  /**
   * Tests that $100 with 8% tax = $108.
   *
   * This is the most basic "happy path" test — does the math work?
   */
  public function testCalculateWithTax(): void {
    $result = $this->calculator->calculateTotal(100.00);
    $this->assertEquals(108.00, $result);
  }

  /**
   * Tests that zero in = zero out.
   *
   * Edge case: make sure we don't get weird floating point issues
   * or divide-by-zero errors on a $0 price.
   */
  public function testZeroPriceReturnsZero(): void {
    $this->assertEquals(0.00, $this->calculator->calculateTotal(0));
  }

  /**
   * Tests that negative prices are rejected.
   *
   * The service should throw an exception rather than silently
   * calculate tax on a negative number. This test EXPECTS the
   * exception — if it doesn't throw, the test fails.
   */
  public function testNegativePriceThrowsException(): void {
    $this->expectException(\InvalidArgumentException::class);
    $this->calculator->calculateTotal(-50.00);
  }

}
```

**Key concepts in this example:**

- **Mocking** (`createMock`) — creates fake versions of dependencies so your test doesn't need a database, config system, or running Drupal site. The test runs in milliseconds. [PHPUnit mocking docs](https://docs.phpunit.de/en/9.6/test-doubles.html)
- **`setUp()`** — runs before every test method. Set up your mocks and create the service here. [PHPUnit fixtures docs](https://docs.phpunit.de/en/9.6/fixtures.html)
- **`UnitTestCase`** — Drupal's base class for unit tests. Provides helpers like `getStringTranslationStub()` and `getContainerWithCacheDisabled()`. [Drupal UnitTestCase docs](https://www.drupal.org/docs/automated-testing/phpunit-in-drupal/unit-testing-more-complicated-drupal-classes)
- **`@coversDefaultClass`** — tells PHPUnit which class this test covers, used for code coverage reports. [PHPUnit annotations docs](https://docs.phpunit.de/en/9.6/annotations.html#coversdefaultclass)
- **`@group`** — lets you run just one module's tests: `./vendor/bin/phpunit --group=my_module`
- **Happy path test** — does the basic case work?
- **Edge case test** — what about zero, null, empty values?
- **Exception test** (`expectException`) — does bad input get rejected? If the exception doesn't throw, the test fails. [PHPUnit exception testing docs](https://docs.phpunit.de/en/9.6/writing-tests-for-phpunit.html#testing-exceptions)

**Further reading:**

- [Drupal PHPUnit overview](https://www.drupal.org/docs/automated-testing/phpunit-in-drupal) — types of tests, directory structure, naming conventions
- [PHPUnit file structure and namespaces in Drupal](https://www.drupal.org/docs/automated-testing/phpunit-in-drupal/phpunit-file-structure-namespace-and-required-metadata) — where test files go, required metadata
- [Running Drupal tests](https://www.drupal.org/docs/automated-testing/phpunit-in-drupal/running-phpunit-tests) — how to run tests locally
- [Drupal testing best practices](https://www.drupal.org/docs/develop/automated-testing) — when to use Unit vs Kernel vs Functional tests

No config changes needed. The wildcard in `phpunit.xml.dist` picks it up.

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
| PHPCBF autofix | Shows what coding standard violations can be auto-fixed — run locally with `./vendor/bin/phpcbf` |
| Rector dry-run | Detects deprecated Drupal API usage and suggests automated fixes |

Extras run in a separate `pr-extras.yml` workflow so they **never block your main PR checks**. They report issues as warnings only.

## Opinionated Defaults

This package makes choices so you don't have to. Here's what we chose and why:

**PHPStan level 1 by default.** Most existing Drupal projects can't pass level 5 without weeks of cleanup. Level 1 gives you real value (undefined variables, unknown classes) without drowning you in noise. The setup script lets you pick a higher level, and the AI prompts help you level up incrementally.

**PHPCS and PHPStan don't block PRs by default on deploy.** PHPStan uses `continue-on-error` and PHPCS can be toggled with `phpcs_required: false`. The goal is to let teams adopt gradually — see violations, fix them over time, then flip the switch when ready.

**Behat over Nightwatch.** Behat with `drupal/drupal-extension` speaks Drupal natively — it knows about roles, users, regions, and content types. Nightwatch is a better general-purpose browser testing tool, but for Drupal-specific smoke tests, Behat gets you further with less code.

**GrumPHP pre-commit hooks.** Catching debug code and PHPCS violations before they're pushed saves everyone time. Some teams find pre-commit hooks annoying — if that's you, disable the scaffold: `"[project-root]/grumphp.yml.dist": false`.

**Pantheon-first.** The workflows are built for Pantheon (multidev, Terminus, git push deploy). If you're on Acquia or another host, you'll need to swap the deploy workflows. The QA tooling (PHPCS, PHPStan, PHPUnit, Behat, GrumPHP, secret scanning) works on any Drupal project regardless of hosting.

**Secret scanning doesn't block.** Gitleaks runs as `continue-on-error: true` so it warns but doesn't fail the build. A false positive shouldn't prevent a deploy. If you want it to block, remove `continue-on-error` from the workflow.

**`CLAUDE.md` and Copilot instructions are scaffolded.** Every project gets AI-aware coding instructions out of the box. If your team doesn't use AI tools, these files are harmless — they just sit there. If anyone starts using Claude Code or Copilot, the project is already configured correctly.

**`TRUE`, `FALSE`, `NULL` uppercase.** This is the Drupal coding standard, not a personal preference. The PHPCS config enforces it.

## Upgrading

To get the latest configs and tests:

```bash
composer update thronedigital/drupal-qa
```

Scaffolded `.dist` files will be refreshed. Your custom overrides (files without `.dist`) won't be touched.

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
