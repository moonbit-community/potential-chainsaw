tool := "wasm-tools"
component-embed := if tool == "wasm-tools" {
    "component embed --encoding utf16 wit"
} else {
    "embed --string-encoding utf16 --wit wit"
}
component-new := if tool == "wasm-tools" {
    "component new"
} else {
    "new"
}

serve target=("debug"): (build target)
    wasmtime serve -S cli=y --env OPENAI_API_KEY target/server.wasm

build target=("debug"):
    @echo 'Building targeting {{ target }}'
    moon build --target wasm --{{ target }}
    {{ tool }} {{ component-embed }} target/wasm/{{ target }}/build/http-server.wasm -o target/server.core.wasm
    {{ tool }} {{ component-new }} target/server.core.wasm -o target/server.wasm

test:
    hurl --test test.hurl

clean:
    @echo 'Cleaning project'
    moon clean
