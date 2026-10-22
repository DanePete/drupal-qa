# Adding your own tests

drupal-qa's tests check what every Drupal site needs: pages load, admin is closed to
visitors, config imports. They can't know what **your** site promises: that the quote
form is on the quote page, that a product shows its price, that a custom module adds up
an order correctly. That part is yours, and drupal-qa runs it with everything else.

![Where each kind of test and config goes in a project](images/extend-layout.png)

| You want to check | Write | It runs |
|---|---|---|
| A page, a form, a link, some words, as a visitor or a logged-in user | A Behat scenario in `tests/behat/features/` | On the pull request's multidev, after the deploy |
| Your own PHP: a service, a calculation, a plugin | A PHPUnit test in your module's `tests/src/Unit` or `tests/src/Kernel` | In GitHub, before the deploy |
| Stricter rules for the whole project | `required:` in the workflow, or your own `phpstan.neon` | Every run |

Contents:

- [Behat: test what the site promises](#behat-test-what-the-site-promises)
  - [Steps you can use](#steps-you-can-use)
  - [Logged-in scenarios](#logged-in-scenarios)
  - [Tags](#tags)
  - [Your own step definitions](#your-own-step-definitions)
- [PHPUnit: test your own code](#phpunit-test-your-own-code)
- [Stricter checks](#stricter-checks)
- [Running it all locally with ddev](#running-it-all-locally-with-ddev)

## Behat: test what the site promises

Put a `.feature` file in `tests/behat/features/`. Any name works; every file there
runs, on every pull request and after every merge, against the real environment over
HTTP. The setup wizard writes the first one for you, from a phrase on your home page:

```gherkin
Feature: Acme Site basics
  What this site promises every visitor.

  Scenario: The home page says what we do
    When I go to the homepage
    Then I should get a 200 HTTP response
    And I should see "Welcome to Acme"
```

A scenario is a page visit and what must be true about it. Write it the way you'd
describe it to a colleague:

```gherkin
Feature: Quotes
  Visitors can ask for a quote. That's where new business starts.

  Scenario: The quote page is ready
    When I go to "/quote"
    Then I should get a 200 HTTP response
    And I should see the heading "Request a quote"
    And I should see the button "Request a quote"
    And I should see the "form.quote-request" element

  Scenario: The footer links to the quote page
    When I go to the homepage
    Then I should see the link "Get a quote"
```

Push it to the pull request. If a step fails, Behat shows ⚠️ on the pull request (or
blocks, with `required: behat`), and the Behat job's log names the scenario, the step
and the page:

```text
--- Failed steps:

001 Scenario: The quote page is ready # tests/behat/features/quotes.feature:4
      And I should see the button "Request a quote" # tests/behat/features/quotes.feature:8
        The button 'Request a quote' was not found on the page https://pr-7-acme-site.pantheonsite.io/quote (Exception)
```

A few things hold for every scenario:

- **The environment is a copy of live.** A new multidev gets live's database and files
  (dev's when live isn't initialized), so test content that's really there.
- **There's no JavaScript.** Requests go over plain HTTP, so `@javascript` scenarios
  can't run, and anything a page draws with JavaScript isn't there to see.
- **Don't submit forms that do something.** A webform submission sends mail and a
  checkout reaches a payment gateway, from a copy of live. drupal-qa's own tests never
  submit; check that the form and its button are there instead.
- **Every step must exist.** Behat runs with `--strict`, so a misspelled step fails the
  run instead of being skipped.

### Steps you can use

These come with drupal-qa and the Drupal Extension. `vendor/bin/behat -dl` lists every
one (with a config; see [running it locally](#running-it-all-locally-with-ddev)).

**Going somewhere**

| Step | Notes |
|---|---|
| `When I go to "/path"` | Any path on the site |
| `When I go to the homepage` | |
| `When I click "Link text"` | Follows a link on the current page |
| `When I reload the page` | |

**What must be true**

| Step | Notes |
|---|---|
| `Then I should get a 200 HTTP response` | Any status: `403`, `404`, `301` |
| `Then I should see "text"` / `Then I should not see "text"` | Anywhere on the page |
| `Then I should see the heading "text"` | An `h1` to `h6` with that text |
| `Then I should see the link "text"` | |
| `Then I should see the button "label"` | |
| `Then I should see the ".css-selector" element` | drupal-qa's; also `should not see` |
| `Then I should see "text" in the ".css-selector" element` | |
| `Then I should see 3 ".css-selector" elements` | An exact count |
| `Then I should be on "/path"` | After a redirect, say |
| `Then the response should contain "<meta name=..."` | Raw HTML, including the `<head>` |

**drupal-qa's own checks**, the steps its bundled scenarios use, are yours too:

| Step | Checks |
|---|---|
| `Then every stylesheet and script on the page loads` | Each same-site CSS and JS file the current page links to answers 200 |
| `Then the response has Drupal's security headers` | `X-Content-Type-Options`, protection from framing, no cache debug headers |
| `Then the page can be cached for visitors` | Not `max-age=0`, no session started |
| `Then the page has a title and one canonical link` | |
| `Then the response is a sitemap` | The current response is XML sitemap markup |
| `Then the newest page of each content type loads` | `@api`; no 500 on any bundle's newest page |
| `Then every content type's add form loads` | `@api`; log in as an administrator first |
| `Then every open webform loads with a submit button` | `@api`; log in as an administrator first. Never submits |
| `Then the search page answers a search` | `@api` |
| `Then registration matches the site's setting` | `@api` |
| `Then visitors and ordinary users hold no restricted permissions` | `@api` |

So, to check that a landing page's assets and caching are right, not just the front
page's:

```gherkin
  Scenario: The pricing page is fast for visitors
    When I go to "/pricing"
    Then I should get a 200 HTTP response
    And every stylesheet and script on the page loads
    And the page can be cached for visitors
```

### Logged-in scenarios

Tag the scenario (or the whole feature) `@api` and log in as a new user with a role:

```gherkin
@api
Feature: Editors

  Scenario: An editor can add a news article
    Given I am logged in as a new user with the "editor" role
    When I go to "/node/add/article"
    Then I should get a 200 HTTP response
    And I should see the button "Save"
```

drupal-qa creates the user on the environment through Drush, logs in with a one-time
login link, and deletes the user when the scenario ends. `@api` scenarios reach the
environment through Drush over SSH, with the `PANTHEON_SSH_KEY` secret.

Use **`I am logged in as a new user with the "…" role`**, not the Drupal Extension's
`I am logged in as a user with the "…" role`: that one can't create a user through
Drush, which is how CI reaches the site. Steps that create content, such as
`Given a "page" with the title "…"`, aren't set up to work in CI either; test the
content the environment already has.

The `administrator` role works on any site: drupal-qa uses whichever role is marked as
the admin role, whatever it's called, and falls back to user 1 when there's none.

### Tags

| Tag | Effect |
|---|---|
| `@api` | The scenario uses Drush: logging in, or drupal-qa's site-wide checks |
| `@wip` | Never runs. For a scenario you're still writing |
| `@webform` | Runs only where the Webform module is enabled |
| `@search` | Runs only where core Search is enabled |
| `@sitemap` | Runs only where Simple XML Sitemap or XML sitemap is enabled |
| `@metatag` | Runs only where Metatag is enabled |

The module tags apply to your scenarios too: a feature tagged `@webform` is skipped on a
site without Webform, instead of failing there.

### Your own step definitions

When a check is too fiddly for the built-in steps, write a step of your own in PHP.
That takes a `behat.yml` of your own, so start from the package's:

```bash
cp vendor/thronedigital/drupal-qa/config/behat.yml.dist behat.yml
```

CI uses the first of `behat.yml`, `behat.yaml`, `behat.yml.dist` and `behat.yaml.dist`
it finds in the project root, in place of the package's. It still adds the
environment's URL and Drush alias on top, so leave `base_url` out.

Write a context class in `tests/behat/bootstrap/`, which the config already autoloads.
Extend drupal-qa's `FeatureContext`, so its steps and the user clean-up come along:

```php
<?php

// tests/behat/bootstrap/AcmeContext.php

use DrupalQa\Behat\FeatureContext;

/**
 * Acme's own steps, on top of drupal-qa's.
 */
class AcmeContext extends FeatureContext {

  /**
   * Checks the quote form is on the page with its submit button.
   *
   * @Then the quote form is ready
   */
  public function assertQuoteFormReady(): void {
    $this->assertSession()->elementExists('css', 'form.quote-request');
    $this->assertSession()->buttonExists('Request a quote');
  }

}
```

Then, in `behat.yml`, put your class **in place of** `DrupalQa\Behat\FeatureContext`
in each suite's `contexts`:

```yaml
      contexts:
        - AcmeContext
        - Drupal\DrupalExtension\Context\DrupalContext
        - Drupal\DrupalExtension\Context\MinkContext
        - Drupal\DrupalExtension\Context\MessageContext
```

Don't list both. A class that extends `FeatureContext` brings its steps with it, and
with both listed every scenario fails on `Step "…" is already defined`.

A context that extends `FeatureContext` also gets the helpers drupal-qa's own steps are
built from:

| Helper | Does |
|---|---|
| `drupalJson(string $php): mixed` | Runs PHP on the site through Drush and returns whatever it `return`s, decoded from JSON |
| `statusOf(string $path): int` | Visits a path and returns its HTTP status code |
| `failOn(array $problems, string $heading = '')` | Fails the step listing every problem, or does nothing if there are none |
| `drush(): DrushDriver` | The Drupal Extension's Drush driver, for any other Drush command |

So a step that checks every recent event page, not just one:

```php
  /**
   * Visits the ten newest published events; none may fail.
   *
   * @Then the newest events load
   */
  public function assertNewestEventsLoad(): void {
    $ids = $this->drupalJson('return array_values(\Drupal::entityQuery("node")
      ->accessCheck(FALSE)->condition("type", "event")->condition("status", 1)
      ->sort("created", "DESC")->range(0, 10)->execute());');
    $problems = [];
    foreach ($ids as $id) {
      $status = $this->statusOf("/node/$id");
      if ($status >= 500) {
        $problems[] = "/node/$id answered $status";
      }
    }
    $this->failOn($problems, 'Event pages that failed');
  }
```

A scenario using it needs `@api`, since `drupalJson()` goes through Drush.

Keep the suite called `default`: CI runs `--suite=default`, and every suite when
Commerce is installed. New features can go anywhere the suite's `paths` point, which
already includes `tests/behat/features`.

## PHPUnit: test your own code

Put tests in a custom module's `tests/src/Unit` or `tests/src/Kernel`, in files ending
`Test.php`. They're found without any configuration, and PHPUnit **blocks** by default:
a failing test fails the run and stops the deploy.

```php
<?php

// web/modules/custom/acme_quotes/tests/src/Unit/QuoteTotalTest.php

namespace Drupal\Tests\acme_quotes\Unit;

use Drupal\acme_quotes\QuoteTotal;
use Drupal\Tests\UnitTestCase;

/**
 * @coversDefaultClass \Drupal\acme_quotes\QuoteTotal
 * @group acme_quotes
 */
class QuoteTotalTest extends UnitTestCase {

  /**
   * Adds tax to the subtotal, rounded to the cent.
   */
  public function testAddsTax(): void {
    $total = new QuoteTotal(0.07875);
    $this->assertSame('107.88', $total->withTax('100.00'));
  }

}
```

- **Kernel tests** (`KernelTestBase`) get a MariaDB database in CI.
- **Functional tests** (`BrowserTestBase`) don't run: they need a web server CI doesn't
  start. Behat covers the same ground against the real environment.
- **Only `web/modules/custom/*`** is searched. Tests anywhere else, or a docroot that
  isn't `web/`, need a `phpunit.xml` of your own: copy
  `vendor/thronedigital/drupal-qa/config/phpunit.xml.dist` to the project root and add
  a `<testsuite>`. Keep its `drupal-qa` suite to keep drupal-qa's own tests.

CI uses your `phpunit.xml` or `phpunit.xml.dist` if there is one. It fails the run if
PHPUnit runs no tests at all, or if `drupal/core-dev` isn't installed.

## Stricter checks

**Make a check block.** List it under `required` in `.github/workflows/drupal-qa.yml`:

```yaml
    with:
      pantheon_site: acme-site
      required: phpcs phpstan behat
```

A sensible order: start with everything warning, fix what it finds, then require the
checks that stay green. To grey out the merge button as well, make the jobs required
status checks in the branch's protection rules on GitHub.

**Raise PHPStan's level.** Add a `phpstan.neon` to the project root. With one, CI runs
PHPStan with your file alone, so it must name the paths:

```neon
includes:
  - vendor/thronedigital/drupal-qa/config/phpstan.neon.dist

parameters:
  level: 3
  paths:
    - web/modules/custom
    - web/themes/custom
```

CI looks for `phpstan.neon`, `phpstan.neon.dist` and `phpstan.dist.neon`.

**PHPCS** always uses the Drupal standard, reports errors but not warnings, and skips
line length. A `phpcs.xml` doesn't change it; `skip: phpcs` turns it off.

## Running it all locally with ddev

The same checks, before you push. Run them from the project root.

**PHPCS**, as CI runs it:

```bash
ddev exec vendor/bin/phpcs --standard=Drupal --extensions=php,module,inc,install,theme \
  --exclude=Drupal.Files.LineLength --warning-severity=0 web/modules/custom
```

**PHPStan**, with the package's config (or just `analyse` if you have your own):

```bash
ddev exec vendor/bin/phpstan analyse \
  -c vendor/thronedigital/drupal-qa/config/phpstan.neon.dist web/modules/custom
```

**PHPUnit.** The package's config has to sit in the project root, where CI puts it.
Copy it once (and commit it, or add it to `.gitignore`), then point Kernel tests at
ddev's database for the run:

```bash
cp vendor/thronedigital/drupal-qa/config/phpunit.xml.dist phpunit.xml.dist
ddev exec SIMPLETEST_DB=mysql://db:db@db/db vendor/bin/phpunit --testsuite unit,kernel
```

**Behat**, against your ddev site. Save this as `behat.local.yml`, and keep it out of
git:

```yaml
# behat.local.yml: Behat against this ddev site.
imports:
  - behat.yml    # or vendor/thronedigital/drupal-qa/config/behat.yml.dist
default:
  extensions:
    Drupal\MinkExtension:
      base_url: 'https://acme-site.ddev.site'    # ddev describe shows yours
    Drupal\DrupalExtension:
      drush:
        alias: '@self'
```

```bash
ddev exec vendor/bin/behat --config=behat.local.yml --suite=default --tags='~@wip'
ddev exec vendor/bin/behat --config=behat.local.yml --suite=default tests/behat/features/quotes.feature
ddev exec vendor/bin/behat --config=behat.local.yml -dl     # every step you can use
```

`@api` scenarios create and delete users on your local site, the same way they do on
a multidev.
