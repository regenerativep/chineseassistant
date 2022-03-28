#!/bin/bash

zig build-lib -target wasm32-freestanding -OReleaseSmall src/main.zig -dynamic && mv main.wasm public/chinesereader.wasm && cp src/chinesereader.js public/.

