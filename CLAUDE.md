# Recordy

## Specs
- There is no `spec/` folder. Behaviour is specified as Gherkin in comments above the Swift Testing tests in `Tests/RecordyTests/`.
- Write them in the style of https://cucumber.io/docs/gherkin/reference:
  - A `Feature` comment with a description above each test struct, with `Background` and `Rule` where they help.
  - A `// Scenario: <name>` comment block above each `@Test`, one `When` per scenario, then Given, When, Then with `And` and `But`.
  - The `@Test` display name is the scenario name.
  - Steps are declarative and describe behaviour, not UI clicks or code.
  - Scenarios that cannot be unit-tested go in a comment at the end of the struct, tagged `@manual` or `@ui`.
- This overrides the general rule of not writing comments.

## Tests
- Run `swift test`. CI runs the same command on every pull request.
