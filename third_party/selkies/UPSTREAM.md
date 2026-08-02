# Vendored Selkies source

- Upstream: https://github.com/selkies-project/selkies
- Commit: `877cf202b4955d8477041c7831d4b34ebdb92d16`
- License: Mozilla Public License 2.0; see `LICENSE` in this directory.
- Local changes: generated `package-lock.json` files were added for the two
  upstream frontend packages. The Railway Docker build injects the built web
  assets and changes only the Python package version at build time to
  `0.0.0.dev0`; the vendored Python and frontend source is otherwise unchanged.

The source is vendored because the official `py-build:main` image available at
the time of integration predates the integrated HTTP/UI/auth server present at
the commit above, while newer upstream image publication is not currently
passing. Keeping the exact source and frontend lockfiles in this repository
makes the Railway image reproducible and preserves the corresponding source for
the MPL-covered component.
