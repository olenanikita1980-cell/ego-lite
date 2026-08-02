# Third-party notices

## Selkies

The Railway visual-control image builds and redistributes Selkies from the
vendored upstream source in `third_party/selkies`.

- Project: https://github.com/selkies-project/selkies
- Source revision: `877cf202b4955d8477041c7831d4b34ebdb92d16`
- License: Mozilla Public License 2.0
- Vendored license text: `third_party/selkies/LICENSE`

The vendored commit, frontend lockfiles, Railway Dockerfile, and resulting
Railway image digest are the artifact source of truth for this integration.
The container builds the upstream dashboard and Python package from those
files; no mutable Selkies image tag is consumed.

No Selkies source files are locally modified. The Docker build injects the
built upstream web assets and changes the Python package version at build time
only. Changes to the integration scripts and Ego Lite Linux host remain under
this repository's MIT license. Consumers that redistribute the container
should retain this notice, make the corresponding MPL-covered source
available, and review all transitive package licenses in the built image.
