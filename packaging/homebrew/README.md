# Homebrew templates

Templates, not yet published in any tap:

- `iclear.rb`: formula that builds the command-line tools from a tagged source tarball.
- `iclear-app.rb`: cask for the menu-bar app from a release zip. The name avoids a
  clash with the formula. Casks should point at notarized builds.

To publish, create a tap repository (for example `urrra39/homebrew-tap`), copy the
file in, fill in `sha256` (`shasum -a 256 <file>`), and run `brew audit --strict`.
