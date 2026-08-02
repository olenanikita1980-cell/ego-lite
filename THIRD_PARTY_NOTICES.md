# Third-party notices

## Selkies

The Railway visual-control image redistributes the unmodified Selkies Python
wheel from the official `selkies-project/selkies` build image.

- Project: https://github.com/selkies-project/selkies
- Linux/amd64 build-image manifest digest:
  `sha256:81b15a6889e39b9c0d10f23acfde21ff3ad1c357345f092ee0b071056f04dcfb`
- Parent OCI index digest:
  `sha256:05f7a7e3b62b481c2d8b5d9ae4e85b34df41f8add85b25c1d157235a7b507a40`
- License: Mozilla Public License 2.0
- License text: https://www.mozilla.org/MPL/2.0/

The digest, rather than the mutable `main` tag, is the artifact source of
truth for this integration. The upstream source revision observed while the
integration was prepared was
`877cf202b4955d8477041c7831d4b34ebdb92d16`; the container's signed provenance
must be verified before claiming that this digest was built from that exact
revision.

No Selkies source files are modified in this repository. Changes to the
integration scripts and Ego Lite Linux host remain under this repository's MIT
license. Consumers that redistribute the container should retain this notice
and review all transitive package licenses in the built image.
