// Build tool only: generates the Swift bindings from the compiled library (core/build-ios.sh).
// It is not part of LimeCore's FFI surface.
fn main() {
    uniffi::uniffi_bindgen_main()
}
