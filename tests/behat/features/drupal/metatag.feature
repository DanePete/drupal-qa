@smoke @drupal-qa @metatag
Feature: Meta tags
  Pages tell search engines their title and their one true address.

  Scenario: The front page has a title and one canonical link
    When I go to the homepage
    Then the page has a title and one canonical link
