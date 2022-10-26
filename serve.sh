#!/bin/bash

zig build -Drelease-small -fstage1 && miniserve ./public/ -p 8000

