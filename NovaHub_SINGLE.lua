name: Build Nova Hub

on:
  push:
    paths:
      - "NovaHub_1911_part*.lua"
      - ".github/workflows/build-nova.yml"
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Combine Parts
        run: |
          cat \
            NovaHub_1911_part1.lua \
            NovaHub_1911_part2.lua \
            NovaHub_1911_part3.lua \
            NovaHub_1911_part4.lua \
            NovaHub_1911_part5.lua \
            NovaHub_1911_part6.lua \
            NovaHub_1911_part7.lua \
            NovaHub_1911_part8.lua \
            > NovaHub_SINGLE.lua

      - name: Commit Single File
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add NovaHub_SINGLE.lua
          git diff --cached --quiet || git commit -m "Build single Nova Hub file"
          git push
