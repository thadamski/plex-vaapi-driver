# plex-vaapi-driver

Builds and publishes `ghcr.io/thadamski/plex-vaapi-driver` — a RELR-free Intel iHD VA-API driver for Plex Media Server.

## What this repo does

Plex ships musl < 1.2.3, which does not process RELR (`.relr.dyn`) sections. Alpine's modern toolchain emits RELR by default. This repo builds `intel-media-driver` and `intel-gmmlib` from source without RELR so Plex's musl can load them.

## Critical invariants

**Do not remove `-Wl,-z,nopackrelocs`** from `LDFLAGS` in the Dockerfile. That flag is the entire reason this image exists.

**Do not remove `-static-libstdc++ -static-libgcc`** from `LDFLAGS`. Alpine's `libstdc++.so` and `libgcc_s.so` also carry RELR — removing the static link reintroduces the crash through the C++ runtime dependencies.

## Updating driver versions

Change `ARG IHD_TAG` and `ARG GMM_TAG` at the top of `Dockerfile` and push to `main`. The workflow rebuilds automatically and pushes `:latest` plus a version-pinned tag.

Tag format:
- `intel/media-driver` → `intel-media-X.Y.Z`
- `intel/gmmlib` → `intel-gmmlib-X.Y.Z`

## Consumer

This image is used as a Kubernetes init container that copies the driver files into a shared volume before the Plex container starts. See the usage snippet in README.md.

## Testing a new build

After rolling the Plex pod with a new image version, confirm hardware transcoding is active by starting a transcode in Plex and checking that the Plex dashboard shows "hw" next to the stream, or inspect `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Logs/` for VA-API initialisation messages.
