#!/usr/bin/env bash
set -euo pipefail

OUTPUT="architecture.pdf"

if ! command -v pandoc &>/dev/null; then
  echo "pandoc is not installed. Install it from https://pandoc.org/installing.html"
  exit 1
fi

pandoc architecture.md \
  --from markdown \
  --to pdf \
  --output "$OUTPUT" \
  --pdf-engine=xelatex \
  --variable mainfont="DejaVu Sans" \
  --variable monofont="DejaVu Sans Mono" \
  --highlight-style tango

echo "Generated: $(pwd)/$OUTPUT"
