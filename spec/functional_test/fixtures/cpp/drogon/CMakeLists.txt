cmake_minimum_required(VERSION 3.5)
project(drogon_sample CXX)

set(CMAKE_CXX_STANDARD 17)

find_package(Drogon CONFIG REQUIRED)

add_executable(drogon_sample main.cpp controllers/UsersController.cpp)
target_link_libraries(drogon_sample PRIVATE Drogon::Drogon)
