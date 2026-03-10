cmake_minimum_required(VERSION 3.14)
project(mrcal-smoketest CXX)

# Caller must set CMAKE_PREFIX_PATH to the extracted mrcal package directory.
find_package(mrcal REQUIRED)

add_executable(smoketest smoketest.cpp)
target_link_libraries(smoketest PRIVATE mrcal::mrcal)
