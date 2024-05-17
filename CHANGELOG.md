## [Unreleased]

## [0.2.1] - 2024-05-16

### Fixed

- Use `frozen_string_literal`.

## [0.2.0] - 2023-05-05

### Added

- `Progeny::Command#spawn_with_pipes` for easier migration from `posix-spawn`.

## [0.1.0] - 2023-05-03

- Initial release. Forked `posix-spawn` gem.

### Changed

- `Progeny::Command#new` and `Progeny::Command#build` only take actual `Hash`
  objects as the `options` argument. We will not call `#to_hash` on the object
  like `POSIX::Spawn::Child` did.

