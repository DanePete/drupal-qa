# Drupal Project — Claude Code Instructions

This project uses `thronedigital/drupal-qa` for CI/QA tooling and deploys to Pantheon.

## Core Rules

- All CLI commands must be prefixed with `ddev` when running locally (e.g., `ddev drush cr`, `ddev composer require`)
- Never push directly to main — always create a branch and open a PR
- Never hack core or contrib modules — use patches via `composer-patches`
- Use `declare(strict_types=1);` in all new PHP files
- No debug code in commits: `ksm()`, `kint()`, `dpm()`, `var_dump()`, `print_r()`, `die()`, `exit()`, `phpinfo()`

## Project Structure

```
web/modules/custom/     — custom modules (project code lives here)
web/modules/contrib/    — contrib modules (never edit directly)
web/themes/             — custom and contrib themes
config/                 — Drupal config sync (YAML, managed by drush)
tests/behat/features/   — project-specific Behat features
tests/behat/bootstrap/  — FeatureContext (extends drupal-qa base)
.github/workflows/      — CI workflows (call reusable workflows from DanePete/drupal-qa)
```

## Dependency Injection

- Never use `\Drupal::service()`, `\Drupal::entityTypeManager()`, or any `\Drupal::` static calls in classes that have constructors
- `\Drupal::` calls are ONLY acceptable in:
  - `.module` files (procedural hooks)
  - `.install` files
  - Settings files
- Always inject services via constructor and declare them in `*.services.yml`

## Security

- Sanitize all user input: use `Xss::filter()`, `Html::escape()`, `check_markup()`
- Use parameterized queries — never concatenate user input into SQL
- Twig: use `{{ variable }}` not `{{ variable|raw }}` unless there is a documented reason
- All routes must have access controls: `_permission`, `_role`, or `_custom_access`
- Use Form API validation (`validateForm()`) — never trust `$form_state->getValue()` without checking it
- Never hardcode credentials, API keys, or secrets — use Key module or environment variables
- Use `\Drupal\Component\Utility\UrlHelper::isValid()` for URL validation

## Config Management

- Export config: `ddev drush cex` (commit the YAML files in `config/`)
- Import config: `ddev drush cim`
- Never manually edit files in `config/` — always make changes through the UI or code, then export
- After changing config, always export and include the YAML changes in your commit

## Common Drush Commands

```bash
ddev drush cr              # clear cache
ddev drush cex             # export config
ddev drush cim             # import config
ddev drush updb            # run database updates
ddev drush en module_name  # enable a module
ddev drush pmu module_name # uninstall a module
ddev drush uli             # generate a login link
ddev drush ws              # show recent watchdog log entries
```

## Testing

### PHPUnit

- Config: `phpunit.xml` or `phpunit.xml.dist`
- Tests auto-discovered from: `web/modules/custom/*/tests/src/Unit/` and `*/tests/src/Kernel/`
- Base class: `Drupal\Tests\UnitTestCase`
- Run all: `ddev exec ./vendor/bin/phpunit`
- Run one module: `ddev exec ./vendor/bin/phpunit --group=module_name`
- Run one file: `ddev exec ./vendor/bin/phpunit web/modules/custom/my_module/tests/src/Unit/MyTest.php`

When writing tests:
- Extend `Drupal\Tests\UnitTestCase`
- Place at `web/modules/custom/{module}/tests/src/Unit/{mirrors src path}/`
- Namespace: `Drupal\Tests\{module}\Unit\{...}`
- Mock all injected dependencies with `$this->createMock()`
- Include `@coversDefaultClass` and `@group` annotations
- Test happy path, edge cases (zero, null, empty), and exception handling

### Behat

- Config: `behat.yml` or `behat.yml.dist`
- Features: `tests/behat/features/`
- Base context: `DrupalQa\Behat\FeatureContext`
- Available traits: ContentTrait, UserTrait, TaxonomyTrait, MediaTrait, WaitTrait, ElementTrait (from `drevops/behat-steps`)
- Run all: `ddev exec ./vendor/bin/behat`
- Run smoke: `ddev exec ./vendor/bin/behat --tags=smoke`

### Code Quality

```bash
# PHPCS — check coding standards
ddev exec ./vendor/bin/phpcs --standard=Drupal --extensions=php,module,inc,install,theme web/modules/custom/

# PHPCS — auto-fix what it can
ddev exec ./vendor/bin/phpcbf --standard=Drupal --extensions=php,module,inc,install,theme web/modules/custom/

# PHPStan — static analysis
ddev exec ./vendor/bin/phpstan analyse --configuration=phpstan.neon --memory-limit=-1
```

## Code Style

- Follow Drupal coding standards (PSR-12 with Drupal-specific conventions)
- Use `TRUE`, `FALSE`, `NULL` (uppercase) in Drupal code
- Use type hints on all function parameters and return types
- PHPDoc blocks on all public methods with `@param` and `@return`
- Comments explain WHY, not WHAT — the code should be readable on its own
- Group `use` statements: PHP core, Symfony, Drupal core, contrib, custom

## Performance

- Never load full entities inside loops — use entity queries for IDs, then `loadMultiple()`
- Use cache tags and cache contexts for render arrays
- Avoid N+1 queries — watch for database calls inside `foreach`
- Use Batch API for operations on large datasets
- Use `#lazy_builder` for expensive render elements

## CI/CD

- PR checks: PHPCS, PHPStan, YAML lint, composer audit, PHPUnit
- Multidev environments created on Pantheon for each PR
- Behat smoke tests run against multidev
- Deploy to Pantheon dev on merge to main
- Post-deploy: `drush updatedb`, `drush config:import`, `drush cache:rebuild`
- `phpcs_required` and `phpstan_required` flags control whether violations block PRs
- If code is already deployed, just run the drush commands — don't redeploy

## Creating New Modules

```bash
# Minimum required files for a new module:
web/modules/custom/my_module/
├── my_module.info.yml          # name, type, core_version_requirement
├── my_module.module            # hook implementations (if needed)
├── my_module.services.yml      # service definitions
├── src/
│   └── Service/                # service classes
└── tests/
    └── src/
        └── Unit/               # unit tests
```

Always include:
- `core_version_requirement: ^10 || ^11` in `.info.yml`
- `type: module` in `.info.yml`
- Services registered in `*.services.yml` with proper dependency injection
- At least one unit test for any service with business logic
