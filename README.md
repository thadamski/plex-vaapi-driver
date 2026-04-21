# plex-vaapi-driver

[![Release](https://github.com/thadamski/plex-vaapi-driver/actions/workflows/release.yml/badge.svg)](https://github.com/thadamski/plex-vaapi-driver/actions/workflows/release.yml)
[![GitHub release](https://img.shields.io/github/v/release/thadamski/plex-vaapi-driver)](https://github.com/thadamski/plex-vaapi-driver/releases/latest)
[![ghcr.io](https://img.shields.io/badge/ghcr.io-plex--vaapi--driver-blue)](https://github.com/thadamski/plex-vaapi-driver/pkgs/container/plex-vaapi-driver)

Container image providing an Intel iHD VA-API driver that is compatible with Plex Media Server's bundled musl runtime. Enables hardware transcoding on Intel Arc / Xe / i915 GPUs in containerised deployments.

```
ghcr.io/thadamski/plex-vaapi-driver:latest
```

---

## Is this for you?

If you're running Plex Media Server in a container with an Intel iGPU and hardware transcoding silently fails, look for these symptoms:

- `Plex Transcoder` exits immediately with no useful output
- Plex dashboard shows software transcoding despite a working GPU
- `vainfo` works fine on the host but transcoding still fails inside the container
- Debug logs or `dmesg` show a segfault at a low address like `0x4310`

This is the fix.

---

## Root cause

Plex ships its own musl libc as the dynamic linker for its binaries. This build predates musl 1.2.3 (March 2022), which introduced support for [RELR](https://maskray.me/blog/2021-10-31-relative-relocations-and-relr) — a compact relocation encoding (`SHT_RELR` / `.relr.dyn`) that modern toolchains now emit by default.

When Plex's musl loads a shared library with a `.relr.dyn` section, it silently skips those relocations. Entries in `.init_array` retain raw link-time file offsets rather than resolved addresses. The dynamic linker calls one of these values as a function pointer and immediately faults — typically at an address like `0x4310`, which is the file offset of a constructor function, not a valid code address.

Alpine's pre-built `intel-media-driver` package and all of its transitive C++ dependencies carry `.relr.dyn` sections. This image builds both `intel-media-driver` and `intel-gmmlib` from source with:

- **`-Wl,-z,nopackrelocs`** — emits standard `R_X86_64_RELATIVE` relocations instead of RELR
- **`-static-libstdc++ -static-libgcc`** — eliminates the C++ runtime `.so` dependencies, which also carry RELR in current Alpine builds

The iHD driver is patched with an RPATH of `/vaapi:/usr/lib/plexmediaserver/lib` so it resolves `libigdgmm` from the shared volume and `libva` / `libdrm` directly from Plex's own lib directory.

> **On `VADriverVTable`:** Plex's `libva.so.2` is sometimes described as having a patched VA-API struct layout. Disassembly of both Plex's and Alpine's libva shows their `VADriverVTable` and `VADriverContext` layouts are identical — the driver built here is compiled against standard `libva-dev` headers and is fully compatible with Plex's runtime.

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

**Prerequisites:**
- [Intel GPU device plugin](https://github.com/intel/intel-device-plugins-for-kubernetes) running on the node to advertise `gpu.intel.com/i915`
- Pod render group membership: `securityContext.supplementalGroups: [991]`

---

## Image tags

Every release publishes four tags so you can pin at whatever granularity suits your deployment:

| Tag | Example | Updates on |
|-----|---------|------------|
| `latest` | `latest` | Every release |
| `<major>` | `1` | Any `1.x.x` release |
| `<major>.<minor>` | `1.2` | Any `1.2.x` release |
| `<major>.<minor>.<patch>` | `1.2.3` | That release only |

---

## Updating driver versions

Driver versions are defined as `ARG` defaults at the top of the `Dockerfile`.

1. Find the latest releases: [intel/media-driver](https://github.com/intel/media-driver/releases) · [intel/gmmlib](https://github.com/intel/gmmlib/releases)
2. Update `IHD_TAG` and `GMM_TAG` in `Dockerfile`
3. Open a PR with a `feat:` commit — semantic-release handles the rest

---

## Building locally

```bash
docker build -t plex-vaapi-driver .

# Pin specific upstream versions
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
| GPU support | Intel Arc / Xe2 (Arrow Lake) and earlier — Broadwell and newer |
| Tested with | `linuxserver/plex:latest`, Plex Media Server 1.43.x |

---

## Contributing

Contributions welcome — driver version bumps, platform fixes, or documentation improvements. Please use [Conventional Commits](https://www.conventionalcommits.org) so releases are versioned automatically:

- `fix:` — patch release
- `feat:` — minor release
- `feat!:` or `BREAKING CHANGE:` footer — major release
