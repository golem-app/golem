#!/bin/sh

set -eu

resource_root="${SRCROOT}/../../packages/inferno/build/apple-resources/${PLATFORM_NAME}"
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

if [ ! -d "${resource_root}" ]; then
  echo "error: Inferno Apple resources were not produced for ${PLATFORM_NAME}." >&2
  exit 1
fi

/bin/mkdir -p "${destination}"
staged=0
for bundle in "${resource_root}"/*.bundle; do
  [ -d "${bundle}" ] || continue
  /usr/bin/ditto "${bundle}" "${destination}/$(basename "${bundle}")"
  staged=$((staged + 1))
done

# The hook recreates the directory before it populates it, so an empty one
# is a carrier build that produced nothing, not a platform without MLX.
if [ "${staged}" -eq 0 ]; then
  echo "error: Inferno Apple resources for ${PLATFORM_NAME} hold no bundle." >&2
  exit 1
fi
