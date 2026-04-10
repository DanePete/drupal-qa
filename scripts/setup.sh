#!/usr/bin/env bash
set -euo pipefail

# drupal-qa setup script
# Generates GitHub Actions workflow files and updates composer.json
# for use with thronedigital/drupal-qa

echo "========================================"
echo "  drupal-qa Setup"
echo "========================================"
echo ""

# Check we're in a Drupal project root
if [ ! -f "composer.json" ]; then
  echo "Error: No composer.json found. Run this from your Drupal project root."
  exit 1
fi

# Gather project info
read -rp "Pantheon site machine name (e.g. my-site): " SITE_NAME
echo ""
echo "  Your site UUID is in the Pantheon dashboard URL:"
echo "  https://dashboard.pantheon.io/workspace/.../cms-site/{SITE-UUID}/environment/..."
echo "  Or run: terminus site:info YOUR_SITE --field=id"
echo ""
read -rp "Pantheon site UUID: " SITE_ID
read -rp "PHP version [8.3]: " PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.3}

read -rp "Should PHPCS failures block PRs? (y/n) [y]: " PHPCS_REQ
PHPCS_REQ=${PHPCS_REQ:-y}
if [[ "$PHPCS_REQ" =~ ^[Yy] ]]; then PHPCS_REQUIRED="true"; else PHPCS_REQUIRED="false"; fi

read -rp "Should PHPStan failures block PRs? (y/n) [n]: " PHPSTAN_REQ
PHPSTAN_REQ=${PHPSTAN_REQ:-n}
if [[ "$PHPSTAN_REQ" =~ ^[Yy] ]]; then PHPSTAN_REQUIRED="true"; else PHPSTAN_REQUIRED="false"; fi

read -rp "Custom theme paths to scan (space-separated) [web/modules/custom/ web/themes/custom/]: " PHPCS_PATHS
PHPCS_PATHS=${PHPCS_PATHS:-"web/modules/custom/ web/themes/custom/"}

read -rp "Run Behat tests on multidev? (y/n) [y]: " RUN_BEHAT
RUN_BEHAT=${RUN_BEHAT:-y}
if [[ "$RUN_BEHAT" =~ ^[Yy] ]]; then BEHAT_ENABLED="true"; else BEHAT_ENABLED="false"; fi

read -rp "Does this site use Drupal Commerce? (y/n) [n]: " HAS_COMMERCE
HAS_COMMERCE=${HAS_COMMERCE:-n}

echo ""
echo "Generating files..."

# Create workflow directory
mkdir -p .github/workflows

# PR Checks
cat > .github/workflows/pr-checks.yml << YAML
name: PR Checks

on:
  pull_request:
    branches: [main, master]
    types: [opened, synchronize, reopened]

jobs:
  checks:
    uses: DanePete/drupal-qa/.github/workflows/pr-checks.yml@v1
    with:
      php_version: '${PHP_VERSION}'
      phpcs_required: ${PHPCS_REQUIRED}
      phpstan_required: ${PHPSTAN_REQUIRED}
      phpcs_paths: '${PHPCS_PATHS}'
    secrets: inherit
YAML
echo "  Created .github/workflows/pr-checks.yml"

# Deploy
cat > .github/workflows/deploy-pantheon.yml << YAML
name: Deploy to Pantheon

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: DanePete/drupal-qa/.github/workflows/deploy-pantheon.yml@v1
    with:
      php_version: '${PHP_VERSION}'
      pantheon_site: ${SITE_NAME}
      pantheon_site_id: ${SITE_ID}
      phpcs_required: ${PHPCS_REQUIRED}
      phpstan_required: ${PHPSTAN_REQUIRED}
      phpcs_paths: '${PHPCS_PATHS}'
    secrets: inherit
YAML
echo "  Created .github/workflows/deploy-pantheon.yml"

# Multidev
cat > .github/workflows/multidev.yml << YAML
name: Multidev Environment

on:
  pull_request:
    branches: [main, master]
    types: [opened, synchronize, reopened]

jobs:
  multidev:
    uses: DanePete/drupal-qa/.github/workflows/multidev.yml@v1
    with:
      php_version: '${PHP_VERSION}'
      pantheon_site: ${SITE_NAME}
      pantheon_site_id: ${SITE_ID}
      run_behat: ${BEHAT_ENABLED}
    secrets: inherit
YAML
echo "  Created .github/workflows/multidev.yml"

# Multidev Cleanup
cat > .github/workflows/multidev-cleanup.yml << YAML
name: Multidev Cleanup

on:
  pull_request:
    branches: [main, master]
    types: [closed]

jobs:
  cleanup:
    uses: DanePete/drupal-qa/.github/workflows/multidev-cleanup.yml@v1
    with:
      pantheon_site: ${SITE_NAME}
    secrets: inherit
YAML
echo "  Created .github/workflows/multidev-cleanup.yml"

# FeatureContext
mkdir -p tests/behat/bootstrap
if [ ! -f tests/behat/bootstrap/FeatureContext.php ]; then
  TRAITS=""
  if [[ "$HAS_COMMERCE" =~ ^[Yy] ]]; then
    TRAITS="use ContentTrait;
  use UserTrait;
  use TaxonomyTrait;"
    TRAIT_IMPORTS="use DrevOps\BehatSteps\Drupal\ContentTrait;
use DrevOps\BehatSteps\Drupal\UserTrait;
use DrevOps\BehatSteps\Drupal\TaxonomyTrait;"
  else
    TRAITS="use ContentTrait;
  use UserTrait;"
    TRAIT_IMPORTS="use DrevOps\BehatSteps\Drupal\ContentTrait;
use DrevOps\BehatSteps\Drupal\UserTrait;"
  fi

  cat > tests/behat/bootstrap/FeatureContext.php << PHP
<?php

use DrupalQa\Behat\FeatureContext as BaseFeatureContext;
${TRAIT_IMPORTS}

/**
 * Project-specific Behat feature context.
 *
 * Extends the drupal-qa base context which provides screenshot capture,
 * element assertions, and wait helpers. Add project-specific step
 * definitions here.
 */
class FeatureContext extends BaseFeatureContext {
  ${TRAITS}
}
PHP
  echo "  Created tests/behat/bootstrap/FeatureContext.php"
else
  echo "  Skipped FeatureContext.php (already exists)"
fi

# Create features directory
mkdir -p tests/behat/features
if [ ! "$(ls -A tests/behat/features 2>/dev/null)" ]; then
  echo "  Created tests/behat/features/ (add your .feature files here)"
fi

echo ""
echo "========================================"
echo "  Next Steps"
echo "========================================"
echo ""
echo "1. Add the package:"
echo "   composer require --dev thronedigital/drupal-qa"
echo ""
echo "2. Add to allowed-packages in composer.json:"
echo '   "extra": { "drupal-scaffold": { "allowed-packages": ["thronedigital/drupal-qa"] } }'
echo ""
echo "3. Set GitHub repo secrets:"
echo "   - PANTHEON_SSH_KEY"
echo "   - PANTHEON_MACHINE_TOKEN"
echo ""
echo "4. Commit and push!"
echo ""
echo "Done."
