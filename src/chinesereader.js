// referenced https://github.com/shritesh/zig-wasm-dom/blob/gh-pages/zigdom.js

const getString = function(ptr, len) {
    const slice = chre.exports.memory.buffer.slice(ptr, ptr + len);
    const textDecoder = new TextDecoder();
    return textDecoder.decode(slice);
};


// https://gist.github.com/joni/3760795/8f0c1a608b7f0c8b3978db68105c5b1d741d0446
function toUTF8Array(str) {
    var utf8 = [];
    for (var i=0; i < str.length; i++) {
        var charcode = str.charCodeAt(i);
        if (charcode < 0x80) utf8.push(charcode);
        else if (charcode < 0x800) {
            utf8.push(0xc0 | (charcode >> 6), 
                      0x80 | (charcode & 0x3f));
        }
        else if (charcode < 0xd800 || charcode >= 0xe000) {
            utf8.push(0xe0 | (charcode >> 12), 
                      0x80 | ((charcode>>6) & 0x3f), 
                      0x80 | (charcode & 0x3f));
        }
        // surrogate pair
        else {
            i++;
            charcode = ((charcode&0x3ff)<<10)|(str.charCodeAt(i)&0x3ff)
            utf8.push(0xf0 | (charcode >>18), 
                      0x80 | ((charcode>>12) & 0x3f), 
                      0x80 | ((charcode>>6) & 0x3f), 
                      0x80 | (charcode & 0x3f));
        }
    }
    return utf8;
}

const launch = function(result) {
    chre.exports = result.instance.exports;
    if (!chre.exports.launch_export()) {
        throw "Launch Error";
    }
};

var output_buffer_id = "output_buffer";
const write_output_buffer = function(ptr, len) {
    var elem = document.getElementById(output_buffer_id);
    elem.innerHTML += getString(ptr, len);
};

const clear_output_buffer = function() {
    var elem = document.getElementById(output_buffer_id);
    elem.innerHTML = "";
}

const getBuffer = function(len) {
    const ptr = chre.exports.getBuffer(len);
    if(ptr == 0) throw new Error("Buffer OOM");
    return new Uint8Array(chre.exports.memory.buffer, ptr, len);
};

const freeBuffer = function(buf) {
    chre.exports.freeBuffer(buf.byteOffset, buf.byteLength);
};

const request_file = function(ptr, len) {
    let name = getString(ptr, len);
    let data = loadFile(name);
    if(data === null) return 0;
    let bytes = toUTF8Array(data);
    let buf = getBuffer(bytes.length);
    for(let i = 0; i < bytes.length; i += 1) {
        buf[i] = bytes[i];
    }
    return buf.byteOffset;
};

var input_buffer_id = "input_buffer";
const read_input_buffer = function() {
    var elem = document.getElementById(input_buffer_id);
    const bytes = toUTF8Array(elem.value); // utf8!
    const arr = getBuffer(bytes.length);
    for(let i = 0; i < bytes.length; i += 1) {
        arr[i] = bytes[i];
    }
    chre.exports.receiveInputBuffer(arr.byteOffset, arr.length);
    freeBuffer(arr);
    return elem.value;
};

var word_buffer = "word_buffer";
const add_word = function(s_ptr, s_len, pinyin_ptr, pinyin_len) {
    let simplified = getString(s_ptr, s_len);
    let pinyin = getString(pinyin_ptr, pinyin_len);
    addWordToBuffer(simplified, pinyin);
};

const add_not_word = function(s_ptr, s_len) {
    let text = getString(s_ptr, s_len);
    if(text === "<br>") {
        let br_elem = document.createElement("br");
        let elem = document.getElementById(word_buffer);
        elem.appendChild(br_elem);
    }
    else {
        let textDiv = document.createElement("div");
        textDiv.setAttribute("class", "word");
        textDiv.innerHTML = text;
        let elem = document.getElementById(word_buffer);
        elem.appendChild(textDiv);
    }
};

function clear_word_buffer() {
    let elem = document.getElementById(word_buffer);
    elem.innerHTML = "";
}

function addWordToBuffer(simplified, pinyin) {
    let simplifiedP = document.createElement("p");
    simplifiedP.setAttribute("class", "word_characters");
    simplifiedP.innerHTML = simplified;
    let pinyinP = document.createElement("p");
    pinyinP.setAttribute("class", "word_pinyin");
    pinyinP.innerHTML = pinyin;
    let wordDiv = document.createElement("div");
    wordDiv.setAttribute("class", "word wordhover");
    wordDiv.appendChild(simplifiedP);
    wordDiv.appendChild(pinyinP);
    wordDiv.addEventListener("click", function() {
        showDefinition(simplified);
    });
    let elem = document.getElementById(word_buffer);
    elem.appendChild(wordDiv);
}

var def_box = "def_box";
function clear_def_box() {
    let box = document.getElementById(def_box);
    box.innerHTML = "";
}
const add_def = function(s_ptr, s_len, t_ptr, t_len, p_ptr, p_len, d_ptr, d_len) {
    let simplified = getString(s_ptr, s_len);
    let traditional = getString(t_ptr, t_len);
    let pinyin = getString(p_ptr, p_len);
    let definition = getString(d_ptr, d_len);

    let simp_elem = document.createElement("p");
    simp_elem.setAttribute("class", "defitem_simp");
    simp_elem.innerHTML = simplified;
    let trad_elem = document.createElement("p");
    trad_elem.setAttribute("class", "defitem_simp");
    trad_elem.innerHTML = traditional;
    let pinyin_elem = document.createElement("p");
    pinyin_elem.setAttribute("class", "defitem_pinyin");
    pinyin_elem.innerHTML = pinyin;
    let def_elem = document.createElement("p");
    def_elem.setAttribute("class", "defitem_def");
    def_elem.innerHTML = definition;
    let defelem = document.createElement("p");
    defelem.setAttribute("class", "defitem");
    defelem.appendChild(simp_elem);
    defelem.appendChild(trad_elem);
    defelem.appendChild(pinyin_elem);
    defelem.appendChild(def_elem);
    let box = document.getElementById(def_box);
    box.appendChild(defelem);
}

var panel_list = ["license", "input", "definition", "debug", "storage"];

function showDefinition(word) {
    const bytes = toUTF8Array(word);
    const arr = getBuffer(bytes.length);
    for(let i = 0; i < bytes.length; i += 1) {
        arr[i] = bytes[i];
    }
    clear_def_box();
    chre.exports.retrieveDefinitions(arr.byteOffset, arr.length);
    freeBuffer(arr);
    selectPanel("definition");
}

var pinyin_enabled = false;

function togglePinyin() {
    pinyin_enabled = !pinyin_enabled;
    setPinyinEnabled(pinyin_enabled);
}
function setPinyinEnabled(on) {
    let style = document.getElementById("word_buffer_style");
    let navelem = document.getElementById("nav_pinyin");
    if(on) {
        style.innerHTML = "";
        navelem.setAttribute("style", "background-color:lightblue;");
    } else {
        style.innerHTML = "#word_buffer .word .word_pinyin { display: none; }";
        navelem.setAttribute("style", "background-color:gray;");
    }
}

function hidePanels() {
    panel_list.forEach((name) => {
        let navelem = document.getElementById("nav_" + name);
        let panelelem = document.getElementById("panel_" + name);
        navelem.setAttribute("style", "background-color:gray;");
        panelelem.setAttribute("style", "display:none;");
    });
}
function selectPanel(name) {
    hidePanels();
    let navelem = document.getElementById("nav_" + name);
    let panelelem = document.getElementById("panel_" + name);
    navelem.setAttribute("style", "background-color:lightblue;");
    //panelelem.setAttribute("style", "display:block;");
    panelelem.setAttribute("style", "");
}

var chre = {
    objects: [],
    imports: {
        buffer: {
            write_output_buffer: write_output_buffer,
            clear_output_buffer: clear_output_buffer,
            add_word: add_word,
            add_not_word: add_not_word,
            add_def: add_def,
            request_file: request_file
        }
    },
    launch: launch,
    exports: undefined
};

function loadReaderWasm() {
    // this is kind of a slow way to do it, but i couldnt get the other way
    // to work on my private server
    fetch(new URL("chinesereader.wasm?v=4", document.location))
        .then(response => response.arrayBuffer())
        .then(bytes => WebAssembly.instantiate(bytes, chre.imports))
        .then(obj => {
            chre.launch(obj);
        });
}

var recent_updates = 0;
var update_delay = 1000;

function updateInput() {
    let save_button = document.getElementById("storage_save");
    save_button.innerHTML = "<p>Save!!!</p>";
    recent_updates += 1;
    setTimeout(() => {
        recent_updates -= 1;
        if(recent_updates === 0) {
            clear_word_buffer();
            read_input_buffer();
        }
    }, update_delay);
}

function updateSaves() {
    // TODO: use indexed db instead of localstorage in future
    let saves_str = localStorage.getItem("save_list");
    if(saves_str === null) saves_str = "";
    let parts = saves_str.split(" ");
    let storage_elem = document.getElementById("save_list");
    storage_elem.innerHTML = "";
    for(let i = 0; i < parts.length; i += 1) {
        let part = parts[i];
        let elem = document.createElement("div");
        elem.setAttribute("class", "save_entry");
        elem.innerHTML = "<p>" + part + "</p>";
        elem.addEventListener("click", () => {
            let inp_elem = document.getElementById("input_buffer");
            inp_elem.value = loadFile(part);
            let save_filename = document.getElementById("storage_filename");
            save_filename.value = part;
            updateInput();
            let save_button = document.getElementById("storage_save");
            save_button.innerHTML = "<p>Save</p>";
            selectPanel("input");
        });
        storage_elem.appendChild(elem);
    }
}

function loadFile(name) {
    return localStorage.getItem("file_" + name);
}
function deleteSave() {
    let filename = document.getElementById("storage_filename").value;
    localStorage.setItem("file_" + filename, null);
    let new_saves_str = "";
    let saves_str = localStorage.getItem("save_list");
    if(saves_str === null) saves_str = "";
    let parts = saves_str.split(" ");
    let first = true;
    for(let i = 0; i < parts.length; i += 1) {
        if(parts[i] !== filename) {
            if(first) {
                new_saves_str = parts[i];
                first = false;
            } else {
                new_saves_str += " " + parts[i];
            }
        }
    }
    localStorage.setItem("save_list", new_saves_str);
    updateSaves();
}
function save() {
    let filename = document.getElementById("storage_filename").value;
    let data = document.getElementById("input_buffer").value;
    localStorage.setItem("file_" + filename, data);

    let saves_str = localStorage.getItem("save_list");
    if(saves_str === null) saves_str = "";
    let parts = saves_str.split(" ");
    let found = false;
    for(let i = 0; i < parts.length; i += 1) {
        if(parts[i] === filename) {
            found = true;
            break;
        }
    }
    if(!found) {
        if(saves_str.length === 0) {
            saves_str = filename;
        } else {
            saves_str += " " + filename;
        }
        localStorage.setItem("save_list", saves_str);
    }
    
    let save_button = document.getElementById("storage_save");
    save_button.innerHTML = "<p>Save</p>";

    updateSaves();
}

window.addEventListener("load", () => {
    loadReaderWasm();
    selectPanel("license");
    setPinyinEnabled(false);
    updateInput();
    updateSaves();
});
