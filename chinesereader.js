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

var input_buffer_id = "input_buffer";
const read_input_buffer = function() {
    var elem = document.getElementById(input_buffer_id);
    const bytes = toUTF8Array(elem.value); // utf8!
    const arr = new Uint8Array(chre.exports.memory.buffer, 0, bytes.length);
    for(let i = 0; i < bytes.length; i += 1) {
        arr[i] = bytes[i];
    }
    chre.exports.receiveInputBuffer(arr.byteOffset, arr.length);
    return elem.value;
};

var word_buffer = "word_buffer";
const add_word = function(s_ptr, s_len, pinyin_ptr, pinyin_len) {
    let simplified = getString(s_ptr, s_len);
    //console.log("got simplified: " + simplified);
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
        textDiv.setAttribute("class", "word"); // do something else maybe?
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
    if(!panelEnabled("pinyin")) {
        pinyinP.setAttribute("style", "display:none;");
    }
    pinyinP.innerHTML = pinyin;
    let wordDiv = document.createElement("div");
    wordDiv.setAttribute("class", "word");
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
const add_def = function(s_ptr, s_len, p_ptr, p_len, d_ptr, d_len) {
    let simplified = getString(s_ptr, s_len);
    let pinyin = getString(p_ptr, p_len);
    let definition = getString(d_ptr, d_len);

    let simp_elem = document.createElement("p");
    simp_elem.setAttribute("class", "defitem_simp");
    simp_elem.innerHTML = simplified;
    let pinyin_elem = document.createElement("p");
    pinyin_elem.setAttribute("class", "defitem_pinyin");
    pinyin_elem.innerHTML = pinyin;
    let def_elem = document.createElement("p");
    def_elem.setAttribute("class", "defitem_def");
    def_elem.innerHTML = definition;
    let defelem = document.createElement("p");
    defelem.setAttribute("class", "defitem");
    defelem.appendChild(simp_elem);
    defelem.appendChild(pinyin_elem);
    defelem.appendChild(def_elem);
    let box = document.getElementById(def_box);
    box.appendChild(defelem);
}
function showDefinition(word) {
    const bytes = toUTF8Array(word);
    const arr = new Uint8Array(chre.exports.memory.buffer, 0, bytes.length);
    for(let i = 0; i < bytes.length; i += 1) {
        arr[i] = bytes[i];
    }
    clear_def_box();
    chre.exports.retrieveDefinitions(arr.byteOffset, arr.length);
    if(!panelEnabled("definition")) {
        togglePanel("definition");
    }
}

var enabled_panels = {};
function panelEnabled(name) {
    return typeof enabled_panels[name] !== "undefined" && !!enabled_panels[name];
}

function setPinyinEnabled(on) {
    let attr;
    if(on) {
        attr = "";
    } else {
        attr = "display:none;";
    }
    let elems = document.getElementsByClassName("word_pinyin");
    for(let i = 0; i < elems.length; i += 1) {
        let elem = elems[i];
        elem.setAttribute("style", attr);
    }
}

function togglePanel(name) {
    let navelem = document.getElementById("nav_" + name);
    let panelelem = document.getElementById("panel_" + name);
    if(panelEnabled(name)) {
        navelem.setAttribute("style", "background-color:red;");
        if(name === "pinyin") {
            setPinyinEnabled(false);
        } else {
            panelelem.setAttribute("style", "display:none;");
        }
        enabled_panels[name] = false;
    }
    else {
        navelem.setAttribute("style", "");
        if(name === "pinyin") {
            setPinyinEnabled(true);
        } else {
            panelelem.setAttribute("style", "display:block;");
        }
        enabled_panels[name] = true;
    }
}


var chre = {
    objects: [],
    imports: {
        buffer: {
            write_output_buffer: write_output_buffer,
            clear_output_buffer: clear_output_buffer,
            add_word: add_word,
            add_not_word: add_not_word,
            add_def: add_def
        }
    },
    launch: launch,
    exports: undefined
};

function loadReaderWasm() {
    WebAssembly.instantiateStreaming(fetch("chinesereader.wasm?v=2"), chre.imports)
        .then(cr => {
            //console.log(cr.instance.exports.add(5, 10));
            chre.launch(cr);
        });
}
window.addEventListener("load", () => {
    loadReaderWasm();
    document.getElementById("input_button").addEventListener("click", () => {
        clear_word_buffer();
        read_input_buffer();
    });
    let panels = ["input", "definition", "debug", "pinyin", "license"];
    panels.forEach((name) => {
        document.getElementById("nav_" + name).addEventListener("click", () => {
            togglePanel(name);
        });
        togglePanel(name);
    });
    document.getElementById("nav_none").addEventListener("click", () => {
        panels.forEach((name) => {
            if(panelEnabled(name)) {
                togglePanel(name);
            }
        });
    });
});
