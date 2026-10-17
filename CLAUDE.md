# Recordy

## Specs
- Behaviour is specified in `spec/*.feature`, a single flat folder. No images, videos or other files there.
- Write them in the style of https://cucumber.io/docs/gherkin/reference:
  - One `Feature` per file, with a free-text description of the value it gives.
  - Group related scenarios with `Rule`, and share setup with `Background`.
  - Each `Scenario` has one `When` and follows Given, When, Then. Use `And` or `But` for further steps.
  - Merge scenarios that differ only by values into a `Scenario Outline` with an `Examples` table.
  - Steps are declarative and describe behaviour, not UI clicks or code.
  - Use `@tags` to mark scenarios that need manual or UI verification.
- Scenarios are not run by a Gherkin runner. Each one is covered by a Swift Testing test whose display name follows Given, when, then.

## Tests
- Run `swift test`. CI runs the same command on every pull request.
