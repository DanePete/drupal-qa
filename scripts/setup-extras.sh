#!/usr/bin/env bash
set -euo pipefail

# drupal-qa extras setup
# Optional add-ons for deeper code quality checks

echo "========================================"
echo "  drupal-qa Extras"
echo "========================================"
echo ""
echo "These are optional add-ons you can enable on top of the base drupal-qa setup."
echo "Each one adds a step to your PR checks workflow."
echo ""

# Check we're in a Drupal project root
if [ ! -f "composer.json" ]; then
  echo "Error: No composer.json found. Run this from your Drupal project root."
  exit 1
fi

if [ ! -f ".github/workflows/pr-checks.yml" ]; then
  echo "Error: No .github/workflows/pr-checks.yml found. Run the main setup script first."
  exit 1
fi

EXTRAS_SELECTED=()

echo "Select which extras to enable:"
echo ""

# PHPStan higher level
read -rp "1. Bump PHPStan to level 5 (the sweet spot — catches wrong method calls, bad types, most real bugs)? (y/n) [n]: " OPT_PHPSTAN_STRICT
OPT_PHPSTAN_STRICT=${OPT_PHPSTAN_STRICT:-n}
if [[ "$OPT_PHPSTAN_STRICT" =~ ^[Yy] ]]; then
  EXTRAS_SELECTED+=("phpstan-strict")
fi

# Security audit
read -rp "2. Security scanning (OWASP checks — SQL injection, XSS, command injection)? (y/n) [n]: " OPT_SECURITY
OPT_SECURITY=${OPT_SECURITY:-n}
if [[ "$OPT_SECURITY" =~ ^[Yy] ]]; then
  EXTRAS_SELECTED+=("security")
fi

# Unused code detection
read -rp "3. Unused code detection (dead code, unused imports, unreachable methods)? (y/n) [n]: " OPT_UNUSED
OPT_UNUSED=${OPT_UNUSED:-n}
if [[ "$OPT_UNUSED" =~ ^[Yy] ]]; then
  EXTRAS_SELECTED+=("unused-code")
fi

# Composer normalize
read -rp "4. Composer normalize (consistent composer.json formatting)? (y/n) [n]: " OPT_NORMALIZE
OPT_NORMALIZE=${OPT_NORMALIZE:-n}
if [[ "$OPT_NORMALIZE" =~ ^[Yy] ]]; then
  EXTRAS_SELECTED+=("composer-normalize")
fi

# PHPCBF autofix
read -rp "5. PHPCBF autofix (automatically fix coding standard violations in PRs)? (y/n) [n]: " OPT_PHPCBF
OPT_PHPCBF=${OPT_PHPCBF:-n}
if [[ "$OPT_PHPCBF" =~ ^[Yy] ]]; then
  EXTRAS_SELECTED+=("phpcbf")
fi

# Rector (automated refactoring / deprecation fixes)
read -rp "6. Rector dry-run (detect deprecated code and suggest automated fixes)? (y/n) [n]: " OPT_RECTOR
OPT_RECTOR=${OPT_RECTOR:-n}
if [[ "$OPT_RECTOR" =~ ^[Yy] ]]; then
  EXTRAS_SELECTED+=("rector")
fi

if [ ${#EXTRAS_SELECTED[@]} -eq 0 ]; then
  echo ""
  echo "No extras selected. Nothing to do."
  exit 0
fi

echo ""
echo "Installing extras..."
echo ""

# Install packages
for extra in "${EXTRAS_SELECTED[@]}"; do
  case "$extra" in
    phpstan-strict)
      echo "  Setting up PHPStan strict mode..."
      if [ -f "phpstan.neon" ]; then
        sed -i.bak 's/level: 1/level: 5/' phpstan.neon && rm -f phpstan.neon.bak
        echo "    Updated phpstan.neon to level 5"
      elif [ -f "phpstan.neon.dist" ]; then
        cp phpstan.neon.dist phpstan.neon
        sed -i.bak 's/level: 1/level: 5/' phpstan.neon && rm -f phpstan.neon.bak
        echo "    Created phpstan.neon at level 5"
      fi
      ;;
    security)
      echo "  Installing security scanning..."
      composer require --dev pheromone/phpcs-security-audit --no-interaction --quiet 2>/dev/null || \
        echo "    Note: pheromone/phpcs-security-audit may need manual install"
      echo "    Added PHPCS security audit sniffs"
      ;;
    unused-code)
      echo "  Installing unused code detection..."
      composer require --dev phpstan/phpstan-strict-rules --no-interaction --quiet 2>/dev/null || \
        echo "    Note: phpstan/phpstan-strict-rules may need manual install"
      echo "    Added PHPStan strict rules (catches unused code patterns)"
      ;;
    phpcbf)
      echo "  PHPCBF autofix enabled (already installed via drupal/coder)"
      ;;
    composer-normalize)
      echo "  Installing composer normalize..."
      composer require --dev ergebnis/composer-normalize --no-interaction --quiet 2>/dev/null || \
        echo "    Note: ergebnis/composer-normalize may need manual install"
      echo "    Run with: composer normalize --dry-run"
      ;;
    rector)
      echo "  Installing Rector..."
      composer require --dev palantirnet/drupal-rector --no-interaction --quiet 2>/dev/null || \
        echo "    Note: palantirnet/drupal-rector may need manual install"
      if [ ! -f "rector.php" ]; then
        cat > rector.php << 'PHP'
<?php

declare(strict_types=1);

use DrupalRector\Set\Drupal10SetList;
use Rector\Config\RectorConfig;

return RectorConfig::configure()
  ->withPaths([
    __DIR__ . '/web/modules/custom',
    __DIR__ . '/web/themes/custom',
  ])
  ->withSets([
    Drupal10SetList::DRUPAL_10,
  ]);
PHP
        echo "    Created rector.php config"
      fi
      echo "    Run with: vendor/bin/rector process --dry-run"
      ;;
  esac
done

# Generate the extras workflow
echo ""
echo "Generating extras workflow..."

cat > .github/workflows/pr-extras.yml << 'YAML'
name: PR Extras

on:
  pull_request:
    branches: [main, master]
    types: [opened, synchronize, reopened]

concurrency:
  group: pr-extras-${{ github.head_ref || github.ref }}
  cancel-in-progress: true

jobs:
  extras:
    name: Extra Checks
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.3'
          extensions: mbstring, xml, curl, gd, zip, pdo, pdo_mysql, bcmath, soap
          tools: composer:v2
          coverage: none

      - name: Get Composer cache directory
        id: composer-cache
        run: echo "dir=$(composer config cache-files-dir)" >> $GITHUB_OUTPUT

      - name: Cache Composer dependencies
        uses: actions/cache@v4
        with:
          path: ${{ steps.composer-cache.outputs.dir }}
          key: ${{ runner.os }}-composer-${{ hashFiles('**/composer.lock') }}
          restore-keys: ${{ runner.os }}-composer-

      - name: Install dependencies
        run: composer install --no-interaction --no-progress --prefer-dist
YAML

# Append selected steps
for extra in "${EXTRAS_SELECTED[@]}"; do
  case "$extra" in
    phpstan-strict)
      cat >> .github/workflows/pr-extras.yml << 'YAML'

      - name: PHPStan Strict Analysis
        run: |
          ./vendor/bin/phpstan analyse \
            --configuration=phpstan.neon \
            --memory-limit=-1 \
            --no-progress
        continue-on-error: true
YAML
      echo "  Added PHPStan strict step"
      ;;
    security)
      cat >> .github/workflows/pr-extras.yml << 'YAML'

      - name: Security Audit - Code Scanning
        run: |
          ./vendor/bin/phpcs \
            --standard=Security \
            --extensions=php,module,inc,install \
            --ignore=*/vendor/*,*/web/core/*,*/web/modules/contrib/*,*/web/themes/contrib/* \
            web/modules/custom/ || true
        continue-on-error: true
YAML
      echo "  Added security scanning step"
      ;;
    phpcbf)
      cat >> .github/workflows/pr-extras.yml << 'YAML'

      - name: PHPCBF Autofix
        run: |
          ./vendor/bin/phpcbf \
            --standard=Drupal \
            --extensions=php,module,inc,install,theme \
            --ignore=*/web/modules/contrib/*,*/web/themes/contrib/* \
            web/modules/custom/ web/themes/custom/ || true
          if [ -n "$(git diff --name-only)" ]; then
            echo "::warning::PHPCBF fixed coding standard violations. Run locally: ./vendor/bin/phpcbf --standard=Drupal web/modules/custom/"
            git diff --stat
          fi
        continue-on-error: true
YAML
      echo "  Added PHPCBF autofix step"
      ;;
    unused-code)
      cat >> .github/workflows/pr-extras.yml << 'YAML'

      - name: Unused Code Detection
        run: |
          ./vendor/bin/phpstan analyse \
            --configuration=phpstan.neon \
            --memory-limit=-1 \
            --no-progress \
            --error-format=table 2>&1 | grep -i "unused\|never read\|dead code\|unreachable" || echo "No unused code detected"
        continue-on-error: true
YAML
      echo "  Added unused code detection step"
      ;;
    composer-normalize)
      cat >> .github/workflows/pr-extras.yml << 'YAML'

      - name: Composer Normalize Check
        run: composer normalize --dry-run --diff
        continue-on-error: true
YAML
      echo "  Added composer normalize step"
      ;;
    rector)
      cat >> .github/workflows/pr-extras.yml << 'YAML'

      - name: Rector Deprecation Check
        run: |
          ./vendor/bin/rector process --dry-run --no-progress-bar 2>&1 || true
        continue-on-error: true
YAML
      echo "  Added Rector deprecation check step"
      ;;
  esac
done

echo ""
echo "  Created .github/workflows/pr-extras.yml"

echo ""
echo "========================================"
echo "  Done!"
echo "========================================"
echo ""
echo "Extras run as a separate workflow (pr-extras.yml) so they don't"
echo "block your main PR checks. All extra steps use continue-on-error"
echo "so they report issues without failing the build."
echo ""
echo "Commit and push to try it out!"
