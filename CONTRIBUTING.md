# Contributing

Contributions are welcome. One thing has to happen before a pull request can be
merged, and it is worth understanding why.

## Sign the CLA

Hora is dual licensed: AGPL-3.0 for everyone, and a commercial license for
schools and organisations that need different terms. That model only works while
one person holds the rights to all of the code.

So every contributor signs the [Contributor License Agreement](licensing/CLA.md).
You keep the copyright to your work. You grant a license wide enough that your
code can ship in both the AGPL build and a commercially licensed one.

Signing is one line added to [licensing/contributors.md](licensing/contributors.md)
in the same pull request as your first contribution. Contributors under 18 need a
parent or guardian to co-sign, which the CLA explains.

Without that line the pull request cannot be merged, however good the code is.

## Before you open a pull request

- Run the tests: `python -m pytest tests/ -v` for the backend,
  `flutter test` in `flutter_app/`
- Build the web target if you touched anything under `flutter_app/lib/services/`:
  `flutter build web`
- Keep `database_service.dart` and `database_service_web.dart` in sync. They are
  two halves of one conditional import, and the web half is not type checked
  until a web build runs. A signature that exists in one and not the other breaks
  CI and nothing else catches it.
- New source files carry the two line SPDX header used everywhere else in the
  repository.
- Do not add code copied from a project under a license incompatible with the
  AGPL, and say in the pull request if a contribution includes third party work.

## Reporting something

Bugs and feature requests go in the issue tracker. Security problems do not. For
those, write privately to the address in the repository profile rather than
opening an issue.
