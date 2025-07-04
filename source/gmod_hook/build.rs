fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src/hax.cpp");
    println!("cargo:rerun-if-changed=src/hax.hpp");

    cc::Build::new()
        .file("src/hax.cpp")
        .static_flag(true)
        .cargo_metadata(true)
        .cpp(true)
        .static_crt(true)
        .compile("gmod_hook_cpp");
} 