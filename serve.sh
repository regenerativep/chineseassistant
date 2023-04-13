#!/bin/bash

# zig build -Doptimize=ReleaseSmall && miniserve ./public/ -p 8000
zig build && miniserve ./public/ -p 8000

