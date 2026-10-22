@smoke @drupal-qa @content
Feature: Pages load
  Pages load, send the right headers, and can be cached.

  Scenario: The front page loads
    When I go to the homepage
    Then I should get a 200 HTTP response

  Scenario: A missing page returns 404
    When I go to "/drupal-qa-page-that-does-not-exist"
    Then I should get a 404 HTTP response

  Scenario: The front page's stylesheets and scripts load
    When I go to the homepage
    Then every stylesheet and script on the page loads

  Scenario: Pages send Drupal's security headers
    When I go to the homepage
    Then the response has Drupal's security headers

  Scenario: Visitors get a page Pantheon can cache
    When I go to the homepage
    Then the page can be cached for visitors

  @api
  Scenario: The newest page of each content type loads
    Then the newest page of each content type loads
