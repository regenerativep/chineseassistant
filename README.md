# Chinese Text Reading Assistant

Input chinese text, outputs into a format where you can click on words for their definitions with pinyin displayed below the words.

Pinyin displayed on the chinese text is not necessarily correct. It is choosing one of the definitions of the detected word from the dictionary to draw pinyin from.

## using

Grab a [`cedict_ts.u8`](https://www.mdbg.net/chinese/dictionary?page=cedict) and put it in a `data` folder, then `zig run generate_definitions.zig`. Might want to integrate this with `build.zig` in the future, however this would preferably use caching since the dictionary is large. Maybe could do something like `@embedFile` the dictionary...

`./serve.sh` will run `zig build -Drelease-small`, and then hosts a server with miniserve on the `public` folder with port 8000.

Unsure if non-linux supported; I use `cp` in `build.zig`.
