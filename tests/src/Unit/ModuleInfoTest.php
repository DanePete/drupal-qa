<?php

namespace DrupalQa\Tests\Unit;

use Drupal\Component\Serialization\Yaml;
use PHPUnit\Framework\Attributes\Group;
use PHPUnit\Framework\TestCase;

/**
 * Validates custom module .info.yml files for common issues.
 *
 * @group drupal_qa
 */
#[Group('drupal_qa')]
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
    foreach ($this->infoYmlFiles() as $file) {
      $contents = file_get_contents($file);
      $this->assertNotFalse($contents, sprintf('Could not read %s', $file));
      try {
        $this->assertIsArray(Yaml::decode($contents), sprintf('%s should parse to an array.', $this->relativePath($file)));
      }
      catch (\Exception $e) {
        $this->fail(sprintf('%s contains invalid YAML: %s', $this->relativePath($file), $e->getMessage()));
      }
    }
  }

  /**
   * Tests that all .info.yml files have required keys.
   */
  public function testInfoYmlHasRequiredKeys(): void {
    foreach ($this->infoYmlFiles() as $file) {
      $info = $this->info($file);
      foreach (['name', 'type', 'core_version_requirement'] as $key) {
        $this->assertArrayHasKey($key, $info, sprintf('%s is missing required key "%s".', $this->relativePath($file), $key));
      }
    }
  }

  /**
   * Tests that no module still uses the retired "core" key.
   */
  public function testNoDeprecatedCoreKey(): void {
    foreach ($this->infoYmlFiles() as $file) {
      $this->assertArrayNotHasKey(
        'core',
        $this->info($file),
        sprintf('%s uses the deprecated "core" key. Use "core_version_requirement" instead.', $this->relativePath($file))
      );
    }
  }

  /**
   * Every .info.yml file under the custom modules, submodules included.
   *
   * Skips the test when there are none.
   *
   * @return string[]
   *   Absolute paths.
   */
  protected function infoYmlFiles(): array {
    $files = [];
    if (is_dir($this->customModulesPath)) {
      $directories = new \RecursiveDirectoryIterator($this->customModulesPath, \FilesystemIterator::SKIP_DOTS);
      // A module's own dependencies are not its info files.
      $filter = new \RecursiveCallbackFilterIterator($directories, function (\SplFileInfo $file): bool {
        return !$file->isDir() || !in_array($file->getFilename(), ['node_modules', 'vendor'], TRUE);
      });
      foreach (new \RecursiveIteratorIterator($filter) as $file) {
        if (str_ends_with($file->getFilename(), '.info.yml')) {
          $files[] = $file->getPathname();
        }
      }
    }
    if (!$files) {
      $this->markTestSkipped('No custom modules found.');
    }
    sort($files);
    return $files;
  }

  /**
   * A parsed .info.yml file; an unreadable one fails the test.
   *
   * @return array<string, mixed>
   *   The file's keys.
   */
  protected function info(string $file): array {
    $contents = file_get_contents($file);
    $this->assertNotFalse($contents, sprintf('Could not read %s', $file));
    $info = Yaml::decode($contents);
    $this->assertIsArray($info, sprintf('%s should parse to an array.', $this->relativePath($file)));
    return $info;
  }

  /**
   * A file's path inside the custom modules directory, for messages.
   */
  protected function relativePath(string $file): string {
    return substr($file, strlen($this->customModulesPath) + 1);
  }

}
