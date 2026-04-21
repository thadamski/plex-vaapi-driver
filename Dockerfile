ARG IHD_TAG=intel-media-26.1.6
ARG GMM_TAG=intel-gmmlib-22.10.0

# ── Builder ───────────────────────────────────────────────────────────────────
FROM alpine:latest AS builder
ARG IHD_TAG
ARG GMM_TAG

RUN apk add --no-cache \
      alpine-sdk \
      cmake \
      git \
      libdrm-dev \
      libpciaccess-dev \
      libva-dev \
      patchelf

# Plex ships musl < 1.2.3, which silently skips RELR (.relr.dyn) sections when
# loading shared libraries. Unrelocated .init_array entries cause a segfault on
# the first constructor call. Both flags are required on every target in this
# build: -z,nopackrelocs suppresses RELR output; -static-libstdc++ and
# -static-libgcc eliminate the C++ runtime .so dependencies, which also carry
# RELR in current Alpine toolchain builds.
ARG LDFLAGS="-Wl,-z,nopackrelocs -static-libstdc++ -static-libgcc"

RUN git clone --depth=1 --branch "${GMM_TAG}" \
        https://github.com/intel/gmmlib /src/gmmlib \
 && cmake -S /src/gmmlib -B /build/gmmlib \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/sdk \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS}" \
        "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS}" \
 && cmake --build /build/gmmlib -j$(nproc) \
 && cmake --install /build/gmmlib

RUN git clone --depth=1 --branch "${IHD_TAG}" \
        https://github.com/intel/media-driver /src/ihd \
 && cmake -S /src/ihd -B /build/ihd \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/sdk \
        -DCMAKE_PREFIX_PATH=/sdk \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_TESTING=OFF \
        -DMEDIA_RUN_TEST_SUITE=OFF \
        "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS}" \
        "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS}" \
 && cmake --build /build/ihd --target iHD_drv_video -j$(nproc)

# Set RPATH so iHD resolves libva + libdrm from Plex's lib directory at
# runtime, and libigdgmm from the /vaapi volume populated by this image.
RUN install -d /out \
 && cp "$(find /build/ihd -name iHD_drv_video.so -print -quit)" /out/ \
 && cp -P /sdk/lib/libigdgmm.so* /out/ \
 && patchelf --set-rpath '/vaapi:/usr/lib/plexmediaserver/lib' /out/iHD_drv_video.so \
 && patchelf --set-rpath '/vaapi:/usr/lib/plexmediaserver/lib' /out/libigdgmm.so.12

# ── Runtime image ─────────────────────────────────────────────────────────────
FROM alpine:latest
COPY --from=builder /out/ /opt/vaapi/
