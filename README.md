# Chinese Text Reading Assistant

Input chinese text, outputs into a format where you can click on words for their definitions with pinyin displayed below the words.

Pinyin displayed underneath the chinese text is not necessarily always correct. It is choosing one of the definitions of the detected word from the dictionary to draw pinyin from, and may select the wrong one given the context (because it does not take the context into account).

## using

1. Grab a [`cedict_ts.u8`](https://www.mdbg.net/chinese/dictionary?page=cedict) and put it in a `data` folder.
2. `zig build -Dgen_def=true run` to generate definitions using the `cedict_ts.u8`.
4. `zig build -Doptimize=ReleaseSmall` generates the `chineseassistant.wasm`.

`./serve.sh` will run `zig build -Doptimize=ReleaseSmall`, and then hosts a server with miniserve on the `public` folder with port 8000.

I use `cp` in `build.zig`; might not work on Windows?
