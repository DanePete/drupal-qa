<?php

namespace DrupalQa\Behat;

use Behat\Behat\Context\Context;
use Behat\Behat\Hook\Scope\AfterStepScope;
use Behat\Mink\Exception\ElementNotFoundException;
use Drupal\DrupalExtension\Context\RawDrupalContext;

/**
 * Base Behat feature context for Drupal QA.
 *
 * Projects should extend this class in their own FeatureContext to inherit
 * screenshot capture, element assertions, and wait helpers. Additional
 * step definitions can be added via drevops/behat-steps traits.
 *
 * Example:
 * @code
 * use DrupalQa\Behat\FeatureContext as BaseFeatureContext;
 * use DrevOps\BehatSteps\Drupal\ContentTrait;
 *
 * class FeatureContext extends BaseFeatureContext {
 *   use ContentTrait;
 * }
 * @endcode
 */
class FeatureContext extends RawDrupalContext implements Context {

  /**
   * Store values between steps.
   *
   * @var array
   */
  protected array $store = [];

  /**
   * Take a screenshot after a failed step.
   *
   * @AfterStep
   */
  public function takeScreenshotAfterFailedStep(AfterStepScope $scope): void {
    if ($scope->getTestResult()->getResultCode() !== 99) {
      return;
    }
    $driver = $this->getSession()->getDriver();
    if (!method_exists($driver, 'getScreenshot')) {
      return;
    }
    $filename = sprintf(
      'fail_%s_%s_%d.png',
      date('Ymd_His'),
      preg_replace('/[^a-zA-Z0-9]/', '_', $scope->getFeature()->getTitle()),
      $scope->getStep()->getLine()
    );
    $dir = getenv('BEHAT_SCREENSHOT_DIR') ?: '/tmp/behat-screenshots';
    if (!is_dir($dir)) {
      mkdir($dir, 0777, TRUE);
    }
    file_put_contents($dir . '/' . $filename, $driver->getScreenshot());
  }

  /**
   * Assert that a CSS element exists on the page.
   *
   * @Then I should see the :selector element
   */
  public function iShouldSeeTheElement(string $selector): void {
    $element = $this->getSession()->getPage()->find('css', $selector);
    if ($element === NULL) {
      throw new ElementNotFoundException(
        $this->getSession()->getDriver(),
        'element',
        'css',
        $selector
      );
    }
  }

  /**
   * Assert that a CSS element does not exist on the page.
   *
   * @Then I should not see the :selector element
   */
  public function iShouldNotSeeTheElement(string $selector): void {
    $element = $this->getSession()->getPage()->find('css', $selector);
    if ($element !== NULL) {
      throw new \RuntimeException(
        sprintf('Element "%s" was found but should not exist.', $selector)
      );
    }
  }

  /**
   * Store a value for use in later steps.
   *
   * @Given I store the value :value as :key
   */
  public function iStoreTheValueAs(string $value, string $key): void {
    $this->store[$key] = $value;
  }

  /**
   * Retrieve a stored value.
   */
  protected function getStoredValue(string $key): string {
    if (!isset($this->store[$key])) {
      throw new \RuntimeException(sprintf('No stored value found for key "%s".', $key));
    }
    return $this->store[$key];
  }

  /**
   * Wait for a number of seconds.
   *
   * @Given I wait :seconds seconds
   */
  public function iWaitSeconds(int $seconds): void {
    $this->getSession()->wait($seconds * 1000);
  }

  /**
   * Assert the current HTTP response code.
   *
   * @Then the response status code should be :code
   */
  public function theResponseStatusCodeShouldBe(int $code): void {
    $actual = $this->getSession()->getStatusCode();
    if ($actual !== $code) {
      throw new \RuntimeException(
        sprintf('Expected status code %d but got %d.', $code, $actual)
      );
    }
  }

}
