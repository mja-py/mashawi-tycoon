#!/bin/bash
# Lists GLB models under assets/models that no script or data table references.
# A model dir/name.glb counts as used when "dir/name", "name" or (for people) the
# part after "character-" appears as a quoted string anywhere in scripts/.
# Usage: tools/unused_assets.sh          (list)
#        tools/unused_assets.sh --delete (delete them and their .import files)
cd "$(dirname "$0")/.." || exit 1
strings=$(grep -rhoE '"[A-Za-z0-9_./-]+"' scripts | tr -d '"' | sort -u)
unused=()
for f in $(find assets/models -name '*.glb' | sort); do
  dir=$(basename "$(dirname "$f")"); name=$(basename "$f" .glb); short=${name#character-}
  if ! printf '%s\n' "$strings" | grep -qxE "$dir/$name|$name|$short"; then unused+=("$f"); fi
done
printf '%s\n' "${unused[@]}"
echo "unused: ${#unused[@]}" >&2
if [ "$1" = "--delete" ]; then
  for f in "${unused[@]}"; do rm -f "$f" "$f.import"; done
  echo "deleted" >&2
fi
