# Chinese Text Reading Assistant

Input chinese text, outputs into a format where you can click on words for their definitions with pinyin displayed below the words.

Pinyin displayed on the chinese text is not necessarily correct. It is choosing one of the definitions of the (potentially incorrectly) detected word from the dictionary to draw pinyin from.

## using

1. Grab a [`cedict_ts.u8`](https://www.mdbg.net/chinese/dictionary?page=cedict) and put it in a `data` folder.
2. `zig build -Dfetch`. The build should fail, and this command is only for obtaining the `extrapacked` dependency.
3. `zig run generate_definitions.zig --pkg-begin extrapacked ./dep/extrapacked.git/extrapacked.zig --pkg-end`
4. `zig build -Drelease-small -fstage1` (at the moment does not compile with new Zig compiler)

`./serve.sh` will run `zig build -Drelease-small -fstage1`, and then hosts a server with miniserve on the `public` folder with port 8000.

I use `cp` in `build.zig`; might not work on Windows?
