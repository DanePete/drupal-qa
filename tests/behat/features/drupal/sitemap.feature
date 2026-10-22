@smoke @drupal-qa @sitemap
Feature: XML sitemap
  Search engines can read the sitemap.

  Scenario: The sitemap is served
    When I go to "/sitemap.xml"
    Then I should get a 200 HTTP response
    And the response is a sitemap
