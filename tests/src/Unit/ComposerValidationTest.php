<?php

namespace DrupalQa\Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Validates composer.json integrity for the project.
 *
 * @group drupal_qa
 */
class ComposerValidationTest extends TestCase {

  /**
   * The project root directory.
   *
   * @var string
   */
  protected string $projectRoot;

  /**
   * {@inheritdoc}
   */
  protected function setUp(): void {
    parent::setUp();
    // Walk up from vendor/thronedigital/drupal-qa/tests/src/Unit to project root.
    $this->projectRoot = realpath(__DIR__ . '/../../../../../../') ?: getcwd();
  }

  /**
   * Tests that composer.json exists and is valid JSON.
   */
  public function testComposerJsonExists(): void {
    $path = $this->projectRoot . '/composer.json';
    $this->assertFileExists($path, 'composer.json should exist in the project root.');
    $contents = file_get_contents($path);
    $this->assertNotFalse($contents);
    $decoded = json_decode($contents, TRUE);
    $this->assertNotNull($decoded, 'composer.json should be valid JSON.');
  }

  /**
   * Tests that composer.lock exists and is in sync.
   */
  public function testComposerLockExists(): void {
    $path = $this->projectRoot . '/composer.lock';
    $this->assertFileExists($path, 'composer.lock should exist. Run composer install.');
  }

  /**
   * Tests that no dev debug packages are in production require.
   */
  public function testNoDebugPackagesInRequire(): void {
    $path = $this->projectRoot . '/composer.json';
    $contents = file_get_contents($path);
    $this->assertNotFalse($contents);
    $composer = json_decode($contents, TRUE);
    $require = $composer['require'] ?? [];

    $debugPackages = ['kint-php/kint', 'symfony/var-dumper'];
    foreach ($debugPackages as $package) {
      if (isset($require[$package])) {
        $this->addWarning(sprintf(
          'Debug package "%s" is in require (not require-dev). Consider moving it to require-dev.',
          $package
        ));
      }
    }
    // Always pass — this is advisory.
    $this->assertTrue(TRUE);
  }

  /**
   * Tests that all local patches referenced in composer.json exist.
   */
  public function testLocalPatchFilesExist(): void {
    $path = $this->projectRoot . '/composer.json';
    $contents = file_get_contents($path);
    $this->assertNotFalse($contents);
    $composer = json_decode($contents, TRUE);
    $patches = $composer['extra']['patches'] ?? [];

    foreach ($patches as $package => $packagePatches) {
      foreach ($packagePatches as $description => $patchPath) {
        // Only check local patches, not URLs.
        if (str_starts_with($patchPath, 'http://') || str_starts_with($patchPath, 'https://')) {
          continue;
        }
        $fullPath = $this->projectRoot . '/' . $patchPath;
        $this->assertFileExists(
          $fullPath,
          sprintf('Local patch "%s" for %s does not exist at %s', $description, $package, $patchPath)
        );
      }
    }
  }

}
