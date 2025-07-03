fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src/gmod_interface.cpp");
    println!("cargo:rerun-if-changed=src/gmod_interface.hpp");

    cc::Build::new()
        .file("src/gmod_interface.cpp")
        .static_flag(true)
        .cargo_metadata(true)
        .cpp(true)
        .static_crt(true)
        .compile("gmod_interface");
} 