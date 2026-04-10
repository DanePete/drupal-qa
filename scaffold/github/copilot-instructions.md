# Copilot Instructions

This is a Drupal 10+ project deploying to Pantheon.

## Coding Standards

- Follow Drupal coding standards (drupal.org/docs/develop/standards).
- Use dependency injection — never use `\Drupal::service()` or `\Drupal::` static calls in classes that support constructor injection.
- PHPDoc blocks are required on all public methods with correct `@param` and `@return` tags.
- No debug code: `ksm()`, `kint()`, `dpm()`, `var_dump()`, `print_r()`, `phpinfo()`, `die()`, `exit()`.

## Security

- All user input must be sanitized. Never trust `$_GET`, `$_POST`, or `$_REQUEST` directly.
- Use parameterized queries — no raw SQL with string concatenation.
- Twig output must use `{{ variable }}` not `{{ variable|raw }}` unless there is an explicit reason.
- All routes must have access controls (`_permission`, `_role`, or `_custom_access`).
- Never hardcode credentials, API keys, or secrets. Use Drupal's Key module or environment variables.

## Performance

- Do not load full entities inside loops. Use entity queries to get IDs, then load in bulk.
- Use caching (`\Drupal::cache()` or cache tags/contexts) for expensive operations.
- Avoid N+1 query patterns — watch for database queries inside `foreach` loops.

## Architecture

- New services must be registered in the module's `*.services.yml`.
- New or changed config must have corresponding config schema YAML.
- Event subscribers are preferred over hook implementations for new code.
- Plugins should use annotations or attributes correctly with all required properties.
