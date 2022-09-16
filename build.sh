#!/bin/bash

zig build-lib -target wasm32-freestanding -OReleaseSmall --strip src/main.zig -dynamic && mv main.wasm public/chinesereader.wasm && cp src/chinesereader.js public/.

