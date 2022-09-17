#!/bin/bash

zig build -Drelease-small && miniserve ./public/ -p 8000

