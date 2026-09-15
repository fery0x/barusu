image := env("IMAGE_FULL", "localhost/barusu:latest")
image_name := "barusu"
filesystem := env("BUILD_FILESYSTEM", "btrfs")

iterate-bootc:
    #!/usr/bin/env bash
    set -xeuo pipefail
    just build
    sudo just load
    sudo just lint
    sudo just rechunk
    sudo env BUILD_BASE_DIR=/tmp just disk-image
    vmbuddy -f /tmp/bootable.img

build: build-ostree

build-ostree:
    mkosi -B --debug-shell --profile=base,base-desktop,bootc-ostree,brew,barusu-bootc-ostree

lint:
    podman run --rm -it --entrypoint=bootc {{ image }} container lint

load:
    #!/usr/bin/env bash
    set -euo pipefail
    archive="$(find mkosi.output -type f -name index.json -printf '%h\n' | sort | tail -n 1)"
    test -n "$archive"
    result="$(podman load -i "$archive")"
    loaded="$(sed -nE 's/^Loaded image(\(s\))?: //p' <<< "$result" | tail -n 1)"
    test -n "$loaded"
    podman tag "$loaded" "{{image}}"

bootc *ARGS:
    podman run \
        --rm --privileged --pid=host \
        -it \
        -v /sys/fs/selinux:/sys/fs/selinux \
        -v /etc/containers:/etc/containers:Z \
        -v /var/lib/containers:/var/lib/containers:Z \
        -v /dev:/dev \
        -v "${BUILD_BASE_DIR:-.}:/data" \
        --security-opt label=type:unconfined_t \
        "{{image}}" bootc {{ARGS}}

disk-image $filesystem=filesystem:
    #!/usr/bin/env bash
    if [ ! -e "${BUILD_BASE_DIR:-.}/bootable.img" ] ; then
        fallocate -l 20G "${BUILD_BASE_DIR:-.}/bootable.img"
    fi
    just bootc install to-disk --generic-image --bootloader grub --via-loopback /data/bootable.img --filesystem "${filesystem}" --wipe

rechunk $image_name=image:
    #!/usr/bin/env bash
    set -xeuo pipefail

    # FIXME: Bandaid fix for
    # https://github.com/zirconium-dev/zirconium/issues/363
    # Do this properly in mkosi at some point
    DATE="$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)"

    CHUNKAH_OUTPUT_DIR="$(mktemp -d)"
    CHUNKAH_CONFIG_FILE="$(mktemp)"

    trap 'rm -f "${CHUNKAH_CONFIG_FILE}"; rm -rf "${CHUNKAH_OUTPUT_DIR}"' EXIT
    podman inspect "${image_name}" > "${CHUNKAH_CONFIG_FILE}"

    podman run --rm "--mount=type=image,src=${image_name},target=/chunkah" \
        -v "${CHUNKAH_CONFIG_FILE}:/chunkah-config.json:ro,Z" \
        -v "${CHUNKAH_OUTPUT_DIR}:/run/out:Z" \
        quay.io/coreos/chunkah:latest build \
        --verbose \
        --compressed \
        --label org.opencontainers.image.created="${DATE}" \
        --max-layers 256 \
        --config /chunkah-config.json \
        --output oci:/run/out/chunked

    CHUNKED_IMAGE="$(podman pull "oci:${CHUNKAH_OUTPUT_DIR}/chunked")"
    podman tag "${CHUNKED_IMAGE}" "${image_name}"

clean:
    mkosi clean
    sudo rm -r mkosi.tools/ mkosi.cache/
