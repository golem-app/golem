#!/bin/sh

set -eu

resource_root="${SRCROOT}/../../packages/inferno/build/apple-resources/${PLATFORM_NAME}"
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

if [ ! -d "${resource_root}" ]; then
  echo "error: Inferno Apple resources were not produced for ${PLATFORM_NAME}." >&2
  exit 1
fi

/bin/mkdir -p "${destination}"
for bundle in "${resource_root}"/*.bundle; do
  [ -d "${bundle}" ] || continue
  /usr/bin/ditto "${bundle}" "${destination}/$(basename "${bundle}")"
done
