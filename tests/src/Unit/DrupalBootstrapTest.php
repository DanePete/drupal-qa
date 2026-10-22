<?php

namespace DrupalQa\Tests\Unit;

use Drupal\Tests\UnitTestCase;
use PHPUnit\Framework\Attributes\Group;

/**
 * Verifies that the Drupal test bootstrap is working correctly.
 *
 * If this test fails, PHPUnit is not set up to bootstrap Drupal: check that
 * phpunit.xml points its bootstrap at web/core/tests/bootstrap.php.
 *
 * @group drupal_qa
 */
#[Group('drupal_qa')]
class DrupalBootstrapTest extends UnitTestCase {

  /**
   * Tests that UnitTestCase found the Drupal root.
   */
  public function testDrupalUnitTestCaseWorks(): void {
    $this->assertFileExists($this->root . '/core/lib/Drupal.php', 'UnitTestCase should find the Drupal root.');
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
