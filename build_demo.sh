#!/bin/bash

clang++ -Wall ./src/* -I ./include -I ./AudioFile -lLowPass -L ./lib -std=c++14 -o demo 
