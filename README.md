# plex-vaapi-driver

[![Build](https://github.com/thadamski/plex-vaapi-driver/actions/workflows/build.yml/badge.svg)](https://github.com/thadamski/plex-vaapi-driver/actions/workflows/build.yml)

Container image providing an Intel iHD VA-API driver compatible with Plex Media Server's bundled musl runtime on Intel Arc / Xe / i915 hardware.

```
ghcr.io/thadamski/plex-vaapi-driver:latest
```

---

## Background

Plex Media Server ships its own musl libc as the dynamic linker for its binaries. This musl build predates version 1.2.3 (released March 2022), which introduced support for [RELR](https://maskray.me/blog/2021-10-31-relative-relocations-and-relr) — a compact encoding for relative relocations (`SHT_RELR` / `.relr.dyn`) that modern toolchains now emit by default.

When Plex's musl loads a shared library that contains a `.relr.dyn` section, it silently skips those relocations. The affected entries in `.init_array` retain their raw link-time file offsets rather than resolved absolute addresses. The dynamic linker then calls that offset value as a function pointer, immediately faulting.

Alpine's pre-built `intel-media-driver` package — and every one of its transitive C++ dependencies — carries `.relr.dyn` sections. This image builds both `intel-media-driver` and `intel-gmmlib` from source with two required flags:

- **`-Wl,-z,nopackrelocs`** — instructs the linker to emit standard `R_X86_64_RELATIVE` entries instead of RELR
- **`-static-libstdc++ -static-libgcc`** — statically links the C++ runtime, eliminating `libstdc++.so` and `libgcc_s.so` as runtime dependencies (both also carry RELR in current Alpine builds)

The resulting libraries are patched with an RPATH of `/vaapi:/usr/lib/plexmediaserver/lib` so that `iHD_drv_video.so` resolves `libigdgmm` from the shared volume and `libva` / `libdrm` from Plex's own lib directory — with no system libraries involved.

> **Note on `VADriverVTable`:** Plex's `libva.so.2` is often described as having a patched VA-API struct layout. Disassembly of both Plex's and Alpine's libva confirms their `VADriverVTable` and `VADriverContext` layouts are identical. The driver built here is compiled against Alpine's standard `libva-dev` headers and is fully compatible with Plex's runtime.

---

## Usage

Deploy as a Kubernetes init container. It copies the pre-built driver files into a shared `emptyDir` volume before the Plex container starts.

```yaml
initContainers:
  - name: vaapi-driver
    image: ghcr.io/thadamski/plex-vaapi-driver:latest
    command: ["sh", "-c", "cp -aP /opt/vaapi/. /vaapi/"]
    volumeMounts:
      - name: vaapi-driver
        mountPath: /vaapi

containers:
  - name: plex
    env:
      - name: LIBVA_DRIVER_NAME
        value: iHD
      - name: LIBVA_DRIVERS_PATH
        value: /vaapi
    resources:
      limits:
        gpu.intel.com/i915: "1"
    volumeMounts:
      - name: vaapi-driver
        mountPath: /vaapi

volumes:
  - name: vaapi-driver
    emptyDir: {}
```

The Intel GPU device plugin must be running on the node to expose the `gpu.intel.com/i915` resource. Pods accessing `/dev/dri` also require render group membership (typically GID `991`), set via `securityContext.supplementalGroups`.

---

## Updating versions

Driver versions are defined as `ARG` defaults at the top of the `Dockerfile`.

1. Find the latest releases: [intel/media-driver](https://github.com/intel/media-driver/releases) · [intel/gmmlib](https://github.com/intel/gmmlib/releases)
2. Update `IHD_TAG` and `GMM_TAG` in `Dockerfile`
3. Push to `main` — CI rebuilds and publishes both `:latest` and a version-pinned tag

---

## Building locally

```bash
docker build -t plex-vaapi-driver .

# Override versions
docker build \
  --build-arg IHD_TAG=intel-media-26.1.6 \
  --build-arg GMM_TAG=intel-gmmlib-22.10.0 \
  -t plex-vaapi-driver .
```

---

## Compatibility

| Component | Version |
|-----------|---------|
| intel-media-driver | 26.1.6 |
| intel-gmmlib | 22.10.0 |
| Target GPU | Intel Arc / Xe2 (Arrow Lake) — compatible with Broadwell and newer |
| Tested with | Plex Media Server 1.43.x, `linuxserver/plex:latest` |
