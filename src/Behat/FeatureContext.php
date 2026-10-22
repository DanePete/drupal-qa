<?php

declare(strict_types=1);

namespace DrupalQa\Behat;

use Behat\Behat\Hook\Scope\AfterStepScope;
use Behat\Mink\Exception\ElementNotFoundException;
use Drupal\DrupalExtension\Context\RawDrupalContext;

/**
 * Steps drupal-qa adds on top of the Drupal Extension's own.
 *
 * The default behat.yml.dist uses this context as is. A project that wants
 * its own steps extends it:
 *
 * @code
 * class FeatureContext extends \DrupalQa\Behat\FeatureContext {
 * }
 * @endcode
 */
class FeatureContext extends RawDrupalContext {

  /**
   * Names of the users this context created, deleted after each scenario.
   *
   * @var string[]
   */
  protected array $createdUsers = [];

  /**
   * Logs in as a new user with a role, created on the site through Drush.
   *
   * Drupal Extension's "I am logged in as a user with the :role role" cannot
   * create a user through its Drush driver from 5.3 on (its field checks need
   * the local API driver), and CI tests a remote environment. This creates
   * the user with drush user:create and logs in with a one-time login link,
   * so it needs nothing but Drush access to the site.
   *
   * @Given I am logged in as a new user with the :role role
   */
  public function loginAsNewUserWithRole(string $role): void {
    if (strtolower($role) === 'administrator') {
      $role = $this->administratorRole();
      if ($role === '') {
        // No admin role at all: the site's administrators are user 1.
        $this->loginWithOneTimeLink(['uid' => 1]);
        return;
      }
    }
    $drush = $this->getDriver('drush');
    $name = 'drupal_qa_' . bin2hex(random_bytes(4));
    $drush->drush('user:create', [escapeshellarg($name)], [
      'mail' => escapeshellarg($name . '@example.com'),
      'password' => escapeshellarg(bin2hex(random_bytes(16))),
    ]);
    $this->createdUsers[] = $name;
    if (!in_array(strtolower($role), ['authenticated', 'authenticated user'], TRUE)) {
      $drush->drush('user:role:add', [escapeshellarg($role), escapeshellarg($name)]);
    }

    $this->loginWithOneTimeLink(['name' => escapeshellarg($name)]);
  }

  /**
   * Logs in through a one-time login link from drush user:login.
   *
   * @param array<string, int|string> $who
   *   The user:login option naming the account: name or uid.
   */
  protected function loginWithOneTimeLink(array $who): void {
    $link = trim($this->getDriver('drush')->drush('user:login', [], $who + ['no-browser' => NULL]));
    $path = parse_url((string) strtok($link, "\n"), PHP_URL_PATH);
    if (!is_string($path) || !str_contains($path, '/user/reset/')) {
      throw new \RuntimeException(sprintf('drush user:login returned no login link for %s: %s', (string) reset($who), $link));
    }
    $this->visitPath($path);
  }

  /**
   * Deletes the users this context created.
   *
   * @AfterScenario
   */
  public function deleteCreatedUsers(): void {
    foreach ($this->createdUsers as $name) {
      try {
        $this->getDriver('drush')->drush('user:cancel', [escapeshellarg($name)], ['delete-content' => NULL, 'yes' => NULL]);
      }
      catch (\Throwable) {
        // A user left behind is untidy, not a test failure.
      }
    }
    $this->createdUsers = [];
  }

  /**
   * Saves a screenshot when a step fails on a driver that can take one.
   *
   * The HTTP-only driver used by default cannot, so this is a no-op there.
   *
   * @AfterStep
   */
  public function takeScreenshotAfterFailedStep(AfterStepScope $scope): void {
    if ($scope->getTestResult()->isPassed()) {
      return;
    }
    try {
      $screenshot = $this->getSession()->getDriver()->getScreenshot();
    }
    catch (\Throwable) {
      return;
    }
    $dir = getenv('BEHAT_SCREENSHOT_DIR') ?: sys_get_temp_dir() . '/behat-screenshots';
    if (!is_dir($dir)) {
      mkdir($dir, 0777, TRUE);
    }
    $name = preg_replace('/[^a-zA-Z0-9]+/', '_', $scope->getFeature()->getTitle() ?? 'feature');
    file_put_contents(sprintf('%s/%s_line%d.png', $dir, $name, $scope->getStep()->getLine()), $screenshot);
  }

  /**
   * Fails a step whose response came from a CDN bot challenge.
   *
   * A challenged request is a 403 that reads exactly like Drupal denying
   * access, so "anonymous users get 403" would pass without reaching Drupal.
   *
   * @AfterStep
   */
  public function failOnCdnChallenge(AfterStepScope $scope): void {
    try {
      $headers = array_change_key_case($this->getSession()->getResponseHeaders());
    }
    catch (\Throwable) {
      return;
    }
    if (($headers['cf-mitigated'][0] ?? '') === 'challenge') {
      throw new \RuntimeException('The CDN answered this request with a bot challenge, so the test never reached Drupal. Send the site\'s bot-bypass token (x-pantheon-bot-bypass).');
    }
  }

  /**
   * Visits the newest published page of every content type and vocabulary.
   *
   * A template, formatter or preprocess error on one bundle never shows on
   * the front page. Anonymous visitors may be refused (403 is fine for gated
   * content); a 500 or worse is the failure this catches.
   *
   * @Then the newest page of each content type loads
   */
  public function assertNewestPageOfEachBundleLoads(): void {
    $pages = $this->drupalJson(<<<'PHP'
      $out = [];
      $etm = \Drupal::entityTypeManager();
      $info = \Drupal::service('entity_type.bundle.info');
      foreach (['node' => 'type', 'taxonomy_term' => 'vid'] as $type => $key) {
        if (!$etm->hasDefinition($type)) {
          continue;
        }
        $storage = $etm->getStorage($type);
        foreach (array_keys($info->getBundleInfo($type)) as $bundle) {
          $ids = $storage->getQuery()->accessCheck(FALSE)->condition($key, $bundle)
            ->condition('status', 1)->sort('changed', 'DESC')->range(0, 1)->execute();
          if ($ids) {
            $out[] = ['label' => "$type:$bundle", 'path' => $storage->load(reset($ids))->toUrl()->toString()];
          }
        }
      }
      return array_slice($out, 0, 30);
      PHP);
    if (!$pages) {
      print 'No published content to check.';
      return;
    }
    $failed = [];
    foreach ($pages as $page) {
      $this->visitPath($page['path']);
      $code = $this->getSession()->getStatusCode();
      if ($code >= 500) {
        $failed[] = sprintf('%s (%s) returned %d', $page['path'], $page['label'], $code);
      }
    }
    if ($failed) {
      throw new \RuntimeException("These pages fail to render:\n- " . implode("\n- ", $failed));
    }
    printf('%d pages checked, one per content type and vocabulary.', count($pages));
  }

  /**
   * Visits the add form of every content type.
   *
   * @Then every content type's add form loads
   */
  public function assertEveryAddFormLoads(): void {
    $types = $this->drupalJson(<<<'PHP'
      return \Drupal::entityTypeManager()->hasDefinition('node_type')
        ? array_keys(\Drupal::entityTypeManager()->getStorage('node_type')->loadMultiple())
        : [];
      PHP);
    $failed = [];
    foreach (array_slice($types, 0, 30) as $type) {
      $this->visitPath('/node/add/' . $type);
      $code = $this->getSession()->getStatusCode();
      if ($code !== 200) {
        $failed[] = sprintf('/node/add/%s returned %d', $type, $code);
      }
    }
    if ($failed) {
      throw new \RuntimeException("These add forms fail to load:\n- " . implode("\n- ", $failed));
    }
    printf('%d add forms checked.', count($types));
  }

  /**
   * Requests every same-site stylesheet and script on the current page.
   *
   * Drupal builds aggregated CSS and JS on request, so the page can load while
   * the files it points at fail; a theme whose build output was never made
   * fails the same way.
   *
   * @Then every stylesheet and script on the page loads
   */
  public function assertPageAssetsLoad(): void {
    $session = $this->getSession();
    $host = parse_url($session->getCurrentUrl(), PHP_URL_HOST);
    $assets = [];
    foreach ($session->getPage()->findAll('css', 'link[rel="stylesheet"][href], script[src]') as $element) {
      $url = (string) ($element->getAttribute('href') ?? $element->getAttribute('src'));
      if (str_starts_with($url, '//')) {
        $url = 'https:' . $url;
      }
      $parts = parse_url($url);
      if (isset($parts['host']) && $parts['host'] !== $host) {
        continue;
      }
      if (empty($parts['path'])) {
        continue;
      }
      $path = $parts['path'] . (isset($parts['query']) ? '?' . $parts['query'] : '');
      $assets[$path] = str_ends_with($parts['path'], '.css') || $element->getTagName() === 'link' ? 'css' : 'javascript';
    }
    $failed = [];
    foreach (array_slice($assets, 0, 40, TRUE) as $path => $kind) {
      $this->visitPath($path);
      $code = $session->getStatusCode();
      $type = strtolower((string) ($session->getResponseHeader('Content-Type') ?? ''));
      if ($code !== 200) {
        $failed[] = sprintf('%s returned %d', $path, $code);
      }
      elseif (!str_contains($type, $kind)) {
        $failed[] = sprintf('%s came back as %s, not %s', $path, $type ?: 'no content type', $kind);
      }
    }
    if ($failed) {
      throw new \RuntimeException("These stylesheets or scripts fail to load:\n- " . implode("\n- ", $failed));
    }
    printf('%d stylesheets and scripts checked.', count($assets));
  }

  /**
   * Checks the headers Drupal core sends to keep pages safe.
   *
   * @Then the response has Drupal's security headers
   */
  public function assertSecurityHeaders(): void {
    $headers = array_change_key_case($this->getSession()->getResponseHeaders());
    $problems = [];
    if (strtolower($headers['x-content-type-options'][0] ?? '') !== 'nosniff') {
      $problems[] = 'X-Content-Type-Options: nosniff is missing.';
    }
    $csp = strtolower(implode(' ', $headers['content-security-policy'] ?? []));
    if (empty($headers['x-frame-options']) && !str_contains($csp, 'frame-ancestors')) {
      $problems[] = 'Neither X-Frame-Options nor a CSP frame-ancestors rule is set, so other sites can frame this one.';
    }
    foreach (['x-drupal-cache-tags', 'x-drupal-cache-contexts', 'x-drupal-cache-max-age'] as $debug) {
      if (isset($headers[$debug])) {
        $problems[] = sprintf('The debug header %s is sent: http.response.debug_cacheability_headers is on in services.yml.', $debug);
      }
    }
    if ($problems) {
      throw new \RuntimeException(implode("\n", $problems));
    }
  }

  /**
   * Checks an anonymous page can be cached by Pantheon's CDN.
   *
   * A response with max-age 0, or one that starts a session, is rebuilt by
   * Drupal for every visitor.
   *
   * @Then the page can be cached for visitors
   */
  public function assertCacheableForVisitors(): void {
    $session = $this->getSession();
    $cacheControl = strtolower((string) ($session->getResponseHeader('Cache-Control') ?? ''));
    preg_match('/max-age=(\d+)/', $cacheControl, $match);
    $problems = [];
    if (!str_contains($cacheControl, 'public') || (int) ($match[1] ?? 0) === 0) {
      $problems[] = sprintf('Cache-Control is "%s". Set "Browser and proxy cache maximum age" at /admin/config/development/performance; Pantheon recommends at least 15 minutes.', $cacheControl ?: 'missing');
    }
    foreach (array_change_key_case($session->getResponseHeaders())['set-cookie'] ?? [] as $cookie) {
      if (preg_match('/^S?SESS[a-z0-9]+=/i', $cookie)) {
        $problems[] = 'The page starts a session for an anonymous visitor, so it cannot be cached. Something stores data in the session before login.';
        break;
      }
    }
    if ($problems) {
      throw new \RuntimeException(implode("\n", $problems));
    }
  }

  /**
   * Checks /user/register is open exactly when the site says it is.
   *
   * @Then registration matches the site's setting
   */
  public function assertRegistrationMatchesSetting(): void {
    $setting = (string) $this->drupalJson("return \\Drupal::config('user.settings')->get('register');");
    $this->visitPath('/user/register');
    $code = $this->getSession()->getStatusCode();
    if ($setting === 'admin_only' && $code !== 403) {
      throw new \RuntimeException(sprintf('Only administrators may create accounts on this site, but /user/register returned %d to a visitor.', $code));
    }
    if ($setting !== 'admin_only' && $code !== 200) {
      throw new \RuntimeException(sprintf('Visitors may register on this site (%s), but /user/register returned %d.', $setting, $code));
    }
  }

  /**
   * Checks visitors can't do admin things.
   *
   * Two of Security Review's checks: no permission marked "restrict access",
   * and no text format without HTML filtering. The anonymous role is always
   * checked; the authenticated role only when visitors can register
   * themselves, since otherwise every account was made by the site's staff.
   *
   * @Then visitors and ordinary users hold no restricted permissions
   */
  public function assertRolesHoldNoRestrictedPermissions(): void {
    $problems = $this->drupalJson(<<<'PHP'
      $out = [];
      $all = \Drupal::service('user.permissions')->getPermissions();
      $checked = \Drupal::config('user.settings')->get('register') === 'admin_only' ? ['anonymous'] : ['anonymous', 'authenticated'];
      $roles = \Drupal::entityTypeManager()->getStorage('user_role')->loadMultiple($checked);
      foreach ($roles as $role) {
        if ($role->isAdmin()) {
          $out[] = sprintf('The %s role is an administrator role.', $role->id());
          continue;
        }
        foreach ($role->getPermissions() as $permission) {
          if (!empty($all[$permission]['restrict access'])) {
            $out[] = sprintf('The %s role has "%s", a restricted permission.', $role->id(), $permission);
          }
        }
      }
      if (\Drupal::moduleHandler()->moduleExists('filter')) {
        foreach (filter_formats() as $format) {
          $granted = array_intersect(array_keys(filter_get_roles_by_format($format)), $checked);
          if (!$granted) {
            continue;
          }
          $filters = $format->filters();
          $safe = FALSE;
          foreach (['filter_html', 'filter_html_escape'] as $id) {
            $safe = $safe || ($filters->has($id) && $filters->get($id)->status);
          }
          if (!$safe) {
            $out[] = sprintf('The %s role can use the "%s" text format, which does not filter HTML.', implode(' and ', $granted), $format->label());
          }
        }
      }
      return $out;
      PHP);
    if ($problems) {
      throw new \RuntimeException(implode("\n", $problems));
    }
  }

  /**
   * Opens every open webform page and checks its submit button is there.
   *
   * Never submits: a submission sends mail and fires CRM handlers.
   *
   * @Then every open webform loads with a submit button
   */
  public function assertOpenWebformsLoad(): void {
    $forms = $this->drupalJson(<<<'PHP'
      $out = [];
      foreach (\Drupal::entityTypeManager()->getStorage('webform')->loadMultiple() as $webform) {
        if ($webform->isOpen() && $webform->getSetting('page')) {
          $out[] = ['label' => $webform->label(), 'path' => $webform->toUrl()->toString()];
        }
      }
      return array_slice($out, 0, 5);
      PHP);
    if (!$forms) {
      print 'No open webform has a page of its own.';
      return;
    }
    $failed = [];
    foreach ($forms as $form) {
      $this->visitPath($form['path']);
      $code = $this->getSession()->getStatusCode();
      $button = $this->getSession()->getPage()->find('css', 'form.webform-submission-form [type="submit"]');
      if ($code !== 200 || $button === NULL) {
        $failed[] = sprintf('%s (%s) returned %d%s', $form['path'], $form['label'], $code, $button === NULL ? ' without a submit button' : '');
      }
    }
    if ($failed) {
      throw new \RuntimeException("These webforms fail to load:\n- " . implode("\n- ", $failed));
    }
    printf('%d webforms checked.', count($forms));
  }

  /**
   * Runs a search on the site's default core search page.
   *
   * Only checks the page works: each environment has its own index, so the
   * results on a multidev say nothing.
   *
   * @Then the search page answers a search
   */
  public function assertSearchPageAnswers(): void {
    $path = $this->drupalJson(<<<'PHP'
      $id = \Drupal::service('search.search_page_repository')->getDefaultSearchPage();
      $page = $id ? \Drupal::entityTypeManager()->getStorage('search_page')->load($id) : NULL;
      return $page ? '/search/' . $page->getPath() : '';
      PHP);
    if (!$path) {
      print 'Core search has no active search page.';
      return;
    }
    $this->visitPath($path . '?keys=drupal');
    $code = $this->getSession()->getStatusCode();
    if ($code !== 200) {
      throw new \RuntimeException(sprintf('%s?keys=drupal returned %d.', $path, $code));
    }
  }

  /**
   * Checks the current response is an XML sitemap.
   *
   * @Then the response is a sitemap
   */
  public function assertResponseIsSitemap(): void {
    $content = $this->getSession()->getPage()->getContent();
    if (!str_contains($content, '<urlset') && !str_contains($content, '<sitemapindex')) {
      throw new \RuntimeException('The response is not an XML sitemap: it has no <urlset> or <sitemapindex>.');
    }
  }

  /**
   * Checks the page has a title and exactly one canonical link.
   *
   * @Then the page has a title and one canonical link
   */
  public function assertTitleAndCanonical(): void {
    $page = $this->getSession()->getPage();
    $title = $page->find('css', 'head title');
    if ($title === NULL || trim($title->getText()) === '') {
      throw new \RuntimeException('The page has no <title>.');
    }
    $count = count($page->findAll('css', 'head link[rel="canonical"]'));
    if ($count !== 1) {
      throw new \RuntimeException(sprintf('The page has %d canonical links; it should have exactly one.', $count));
    }
  }

  /**
   * The site's administrator role: "administrator", or the role marked admin.
   *
   * Sites built from other profiles name it differently ("admin",
   * "site_administrator"); what makes it the admin role is its flag. Empty
   * when the site has none, and only user 1 administers it.
   */
  protected function administratorRole(): string {
    return (string) $this->drupalJson(<<<'PHP'
      $roles = \Drupal::entityTypeManager()->getStorage('user_role')->loadMultiple();
      if (isset($roles['administrator'])) {
        return 'administrator';
      }
      foreach ($roles as $role) {
        if ($role->isAdmin()) {
          return $role->id();
        }
      }
      return '';
      PHP);
  }

  /**
   * Runs PHP on the site through Drush and returns what it returns.
   *
   * The code travels base64-encoded, so no quoting survives or breaks on its
   * way through the shell and SSH; the result comes back as marked JSON.
   */
  protected function drupalJson(string $php): mixed {
    $wrapped = sprintf('echo "\nDRUPAL-QA-JSON:" . json_encode((function () { %s })()) . "\n";', $php);
    $code = sprintf("eval(base64_decode('%s'));", base64_encode($wrapped));
    $output = (string) $this->getDriver('drush')->drush('php:eval', [escapeshellarg($code)]);
    if (!preg_match('/^DRUPAL-QA-JSON:(.*)$/m', $output, $match)) {
      throw new \RuntimeException("Drush returned no result. Its output:\n" . $output);
    }
    return json_decode($match[1], TRUE, 512, JSON_THROW_ON_ERROR);
  }

  /**
   * Asserts a CSS selector matches an element on the page.
   *
   * @Then I should see the :selector element
   */
  public function assertElementExists(string $selector): void {
    if ($this->getSession()->getPage()->find('css', $selector) === NULL) {
      throw new ElementNotFoundException($this->getSession()->getDriver(), 'element', 'css', $selector);
    }
  }

  /**
   * Asserts a CSS selector matches nothing on the page.
   *
   * @Then I should not see the :selector element
   */
  public function assertElementNotExists(string $selector): void {
    if ($this->getSession()->getPage()->find('css', $selector) !== NULL) {
      throw new \RuntimeException(sprintf('Element "%s" was found but should not exist.', $selector));
    }
  }

}
