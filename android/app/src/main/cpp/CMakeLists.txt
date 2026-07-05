# Builds liblibre3bridge.so — the dlopen shim to Abbott's liblibre3extension.so
# for FreeStyle Libre 3 crypto (see libre3bridge.cpp). The Abbott .so is resolved
# at runtime, so this builds without it present.
cmake_minimum_required(VERSION 3.18.1)
project(libre3bridge)

add_library(libre3bridge SHARED libre3bridge.cpp)

find_library(log-lib log)
target_link_libraries(libre3bridge ${log-lib})
