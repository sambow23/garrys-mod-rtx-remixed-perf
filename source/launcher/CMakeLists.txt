cmake_minimum_required(VERSION 3.10)
project(GameLauncher)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add the manifest file
set(APP_MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/app.manifest)

# Add executable with the manifest
add_executable(GameLauncher WIN32 
    main.cpp
    ${APP_MANIFEST}
)

# Set the manifest as a resource
if(MSVC)
    target_sources(GameLauncher PRIVATE ${APP_MANIFEST})
endif()

set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT GameLauncher)