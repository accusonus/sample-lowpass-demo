#!/bin/bash

clang++ -Wall ./src/* -I ../AccusonusLibrary/include -I ./AudioFile -lLowPass_macOS -L ../AccusonusLibrary/lib -std=c++14 -o demo 
