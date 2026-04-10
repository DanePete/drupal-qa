<?php

namespace DrupalQa\Tests\Unit;

use PHPUnit\Framework\TestCase;
use Symfony\Component\Yaml\Yaml;

/**
 * Validates custom module .info.yml files for common issues.
 *
 * @group drupal_qa
 */
class ModuleInfoTest extends TestCase {

  /**
   * The custom modules directory.
   *
   * @var string
   */
  protected string $customModulesPath;

  /**
   * {@inheritdoc}
   */
  protected function setUp(): void {
    parent::setUp();
    $projectRoot = realpath(__DIR__ . '/../../../../../../') ?: getcwd();
    $this->customModulesPath = $projectRoot . '/web/modules/custom';
  }

  /**
   * Tests that all .info.yml files are valid YAML.
   */
  public function testInfoYmlFilesAreValidYaml(): void {
    $files = $this->getInfoYmlFiles();
    if (empty($files)) {
      $this->markTestSkipped('No custom modules found.');
    }

    foreach ($files as $file) {
      $contents = file_get_contents($file);
      $this->assertNotFalse($contents, sprintf('Could not read %s', $file));
      try {
        $parsed = Yaml::parse($contents);
        $this->assertIsArray($parsed, sprintf('%s should parse to an array.', basename($file)));
      }
      catch (\Exception $e) {
        $this->fail(sprintf('%s contains invalid YAML: %s', basename($file), $e->getMessage()));
      }
    }
  }

  /**
   * Tests that all .info.yml files have required keys.
   */
  public function testInfoYmlHasRequiredKeys(): void {
    $files = $this->getInfoYmlFiles();
    if (empty($files)) {
      $this->markTestSkipped('No custom modules found.');
    }

    $requiredKeys = ['name', 'type', 'core_version_requirement'];

    foreach ($files as $file) {
      $contents = file_get_contents($file);
      $this->assertNotFalse($contents);
      $info = Yaml::parse($contents);
      foreach ($requiredKeys as $key) {
        $this->assertArrayHasKey(
          $key,
          $info,
          sprintf('%s is missing required key "%s".', basename($file), $key)
        );
      }
    }
  }

  /**
   * Tests that no modules use deprecated 'core' key instead of 'core_version_requirement'.
   */
  public function testNoDeprecatedCoreKey(): void {
    $files = $this->getInfoYmlFiles();
    if (empty($files)) {
      $this->markTestSkipped('No custom modules found.');
    }

    foreach ($files as $file) {
      $contents = file_get_contents($file);
      $this->assertNotFalse($contents);
      $info = Yaml::parse($contents);
      $this->assertArrayNotHasKey(
        'core',
        $info,
        sprintf('%s uses deprecated "core" key. Use "core_version_requirement" instead.', basename($file))
      );
    }
  }

  /**
   * Find all .info.yml files in custom modules.
   *
   * @return array
   *   Array of file paths.
   */
  protected function getInfoYmlFiles(): array {
    if (!is_dir($this->customModulesPath)) {
      return [];
    }
    $files = glob($this->customModulesPath . '/*/*.info.yml');
    return $files ?: [];
  }

}
