#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 APPLE_TEAM_ID APP_BUNDLE_ID OUTPUT_PATH" >&2
  exit 64
fi

team_id=$1
bundle_id=$2
output_path=$3
case "$team_id" in (*[!A-Z0-9]*|'') echo "invalid Apple team ID" >&2; exit 65;; esac
case "$bundle_id" in (*[!A-Za-z0-9.-]*|'') echo "invalid bundle ID" >&2; exit 65;; esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
template="$script_dir/../Config/apple-app-site-association.template.json"
sed -e "s/APPLE_TEAM_ID/$team_id/g" -e "s/APP_BUNDLE_ID/$bundle_id/g" \
  "$template" > "$output_path"
jq -e '.applinks.details | length == 1' "$output_path" >/dev/null
echo "$output_path"
