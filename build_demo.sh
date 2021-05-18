#!/bin/bash

clang++ -Wall ./src/* -I ./include -I ./AudioFile -lLowPass_macOS -L ./lib -std=c++14 -o demo 
