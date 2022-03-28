# Chinese Text Reading Assistant

Input chinese text, outputs into a format where you can click on words for their definitions with pinyin below the words. (pinyin not necessarily correct)

## using

Grab a `cedict_ts.u8` and put it in a `data` folder, then `zig run generate_definitions.zig`.

I use `./serve.sh` which runs `build.sh` and then hosts a server on the `public` folder with port 8000 with the `http-server` from NPM.

View `build.sh` for commands used for building; I don't believe I use the `build.zig`.


