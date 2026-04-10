<?php

namespace DrupalQa\Tests\Unit;

use Drupal\Tests\UnitTestCase;

/**
 * Verifies that the Drupal test bootstrap is working correctly.
 *
 * If this test fails, PHPUnit is not properly configured to bootstrap Drupal.
 * Check that phpunit.xml has the correct bootstrap path to web/core/tests/bootstrap.php.
 *
 * @group drupal_qa
 */
class DrupalBootstrapTest extends UnitTestCase {

  /**
   * Tests that UnitTestCase can be instantiated.
   */
  public function testDrupalUnitTestCaseWorks(): void {
    $this->assertTrue(TRUE, 'Drupal UnitTestCase bootstrap is working.');
  }

  /**
   * Tests that the Drupal class autoloader is available.
   */
  public function testDrupalAutoloaderAvailable(): void {
    $this->assertTrue(
      class_exists('Drupal\Core\DependencyInjection\ContainerBuilder'),
      'Drupal core classes should be autoloadable.'
    );
  }

  /**
   * Tests that the StringTranslationTrait is usable.
   */
  public function testStringTranslationAvailable(): void {
    $this->assertTrue(
      trait_exists('Drupal\Core\StringTranslation\StringTranslationTrait'),
      'StringTranslationTrait should be autoloadable.'
    );
  }

}
