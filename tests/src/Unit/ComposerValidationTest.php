<?php

namespace DrupalQa\Tests\Unit;

use PHPUnit\Framework\Attributes\Group;
use PHPUnit\Framework\TestCase;

/**
 * Validates composer.json integrity for the project.
 *
 * @group drupal_qa
 */
#[Group('drupal_qa')]
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
    // From vendor/thronedigital/drupal-qa/tests/src/Unit up to the project.
    $this->projectRoot = realpath(__DIR__ . '/../../../../../../') ?: getcwd();
  }

  /**
   * Tests that composer.json exists and is valid JSON.
   */
  public function testComposerJsonExists(): void {
    $this->assertFileExists($this->projectRoot . '/composer.json', 'composer.json should exist in the project root.');
    $this->assertNotNull($this->composerJson(), 'composer.json should be valid JSON.');
  }

  /**
   * Tests that composer.lock exists.
   */
  public function testComposerLockExists(): void {
    $path = $this->projectRoot . '/composer.lock';
    $this->assertFileExists($path, 'composer.lock should exist. Run composer install.');
  }

  /**
   * Tests that no dev debug packages are in production require.
   */
  public function testNoDebugPackagesInRequire(): void {
    $composer = $this->composerJson();
    $this->assertIsArray($composer, 'composer.json should be valid JSON.');
    $require = $composer['require'] ?? [];

    $debugPackages = ['kint-php/kint', 'symfony/var-dumper'];
    foreach ($debugPackages as $package) {
      if (isset($require[$package])) {
        $message = sprintf(
          'Debug package "%s" is in require (not require-dev). Consider moving it to require-dev.',
          $package
        );
        // Advisory, so it must not change the result. addWarning() is gone
        // from PHPUnit 10 (an Error), and a PHPUnit warning of any kind fails
        // a run under failOnWarning, so the note goes to stderr instead.
        fwrite(STDERR, 'drupal-qa: ' . $message . PHP_EOL);
      }
    }
  }

  /**
   * Tests that all local patches referenced in composer.json exist.
   */
  public function testLocalPatchFilesExist(): void {
    $composer = $this->composerJson();
    $this->assertIsArray($composer, 'composer.json should be valid JSON.');
    $patches = $composer['extra']['patches'] ?? [];

    foreach ($patches as $package => $packagePatches) {
      foreach ($packagePatches as $key => $patch) {
        // composer-patches 1 maps a description to a path; 2 also takes an
        // object with a description and a url.
        $path = (string) (is_array($patch) ? ($patch['url'] ?? '') : $patch);
        $description = (string) (is_array($patch) ? ($patch['description'] ?? $key) : $key);
        // Only check local patches, not URLs.
        if ($path === '' || preg_match('#^https?://#', $path)) {
          continue;
        }
        $this->assertFileExists(
          $this->projectRoot . '/' . $path,
          sprintf('Local patch "%s" for %s does not exist at %s', $description, $package, $path)
        );
      }
    }
  }

  /**
   * The project's composer.json, decoded.
   *
   * @return array<string, mixed>|null
   *   NULL when the file is missing or isn't valid JSON.
   */
  protected function composerJson(): ?array {
    $contents = @file_get_contents($this->projectRoot . '/composer.json');
    $decoded = $contents === FALSE ? NULL : json_decode($contents, TRUE);
    return is_array($decoded) ? $decoded : NULL;
  }

}
