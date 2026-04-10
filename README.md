# drupal-qa

Reusable CI/QA toolchain for Drupal projects. One `composer require` gives you PHPUnit, PHPCS, PHPStan, Behat, and GrumPHP with sensible defaults, generic smoke tests, and reusable GitHub Actions workflows for Pantheon.

## Installation

```bash
composer require --dev thronedigital/drupal-qa
```

Add the package to your `allowed-packages` in `composer.json` so the scaffold plugin copies config files:

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

Located in `scaffold/github/workflows/`. These use `workflow_call` so your project references them with ~10 lines each.

## Adding Project-Specific Tests

### PHPUnit

Create tests in your custom modules — they're auto-discovered:

```
web/modules/custom/my_module/tests/src/Unit/MyServiceTest.php
```

```php
<?php

namespace Drupal\Tests\my_module\Unit;

use Drupal\Tests\UnitTestCase;

class MyServiceTest extends UnitTestCase {

  public function testMyThing(): void {
    // Your project-specific test.
    $this->assertTrue(TRUE);
  }

}
```

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
    uses: thronedigital/drupal-qa/.github/workflows/pr-checks.yml@v1
    with:
      phpcs_required: false    # set true when codebase is clean
      phpstan_required: false  # set true when codebase is clean
    secrets: inherit
```

### 2. Deploy to Pantheon

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    uses: thronedigital/drupal-qa/.github/workflows/deploy-pantheon.yml@v1
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
    uses: thronedigital/drupal-qa/.github/workflows/multidev.yml@v1
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
    uses: thronedigital/drupal-qa/.github/workflows/multidev-cleanup.yml@v1
    with:
      pantheon_site: my-site-name
    secrets: inherit
```

### Required Secrets

Set these in your repo's Settings > Secrets:

- `PANTHEON_SSH_KEY` — private key authorized on Pantheon
- `PANTHEON_MACHINE_TOKEN` — Pantheon machine token for Terminus

## Workflow Inputs

### pr-checks.yml

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `php_version` | string | `8.3` | PHP version |
| `phpcs_required` | boolean | `true` | Block PR on PHPCS failures |
| `phpstan_required` | boolean | `false` | Block PR on PHPStan failures |
| `phpcs_paths` | string | `web/modules/custom/ web/themes/custom/` | Paths to scan |
| `yamllint_enabled` | boolean | `true` | Lint config/ YAML files |

### deploy-pantheon.yml

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `pantheon_site` | string | required | Site machine name |
| `pantheon_site_id` | string | required | Site UUID |
| `phpcs_required` | boolean | `true` | Block deploy on PHPCS failures |
| `phpstan_required` | boolean | `false` | Block deploy on PHPStan failures |

### multidev.yml

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `pantheon_site` | string | required | Site machine name |
| `pantheon_site_id` | string | required | Site UUID |
| `run_behat` | boolean | `true` | Run Behat tests against multidev |
| `behat_tags` | string | `smoke` | Behat tag filter |
| `source_env` | string | `live` | Environment to clone from |

## Customizing Configs

If you need to override a scaffolded config, copy it and remove the `.dist` extension. For example, to customize PHPStan:

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
