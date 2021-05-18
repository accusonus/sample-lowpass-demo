//
//  demo.cpp
//  lowpass-demo
//
//  Created by Elias Kokkinis on 18/5/21.
//

#include <iostream>

#include "AudioFile.h"
#include "LowPass.hpp"

typedef AudioFile<float> AudioFileFloat;

// A simple function to create an AudioFile with the same properties
void copyAudioFileProperties(AudioFileFloat& srcFile, AudioFileFloat& dstFile)
{
    dstFile.setNumChannels(srcFile.getNumChannels());
    dstFile.setBitDepth(srcFile.getBitDepth());
    dstFile.setSampleRate(srcFile.getSampleRate());
    dstFile.setAudioBufferSize(srcFile.getNumChannels(),
                               srcFile.getNumSamplesPerChannel());
}

int main(int argc, const char * argv[]) {
    // Argument parsing
    if (argc != 4)
    {
        std::cout << "Error! Usage: <input file> <output file> <parameter (0.0 to 1.0)>"
                  << std::endl;

        return -1;
    }

    const std::string inputFilename(argv[1]);
    const std::string outputFilename(argv[2]);
    const float param = std::stof(argv[3]);
    
    // Input/output files
    AudioFileFloat inputFile;
    inputFile.load(inputFilename);

    AudioFileFloat outputFile;
    copyAudioFileProperties(inputFile, outputFile);
    
    const int blockSize = 512; // Block size of the audio engine
    const int numBlocks = inputFile.getNumSamplesPerChannel() / blockSize;

    LowPass filter;
    filter.setup(inputFile.getSampleRate(), blockSize, inputFile.getNumChannels());
    filter.setUserParameterValue(param);
    
    // Interface for the AudioFile class
    std::vector<float*> block(inputFile.getNumChannels());
   
    for (int k = 0; k < numBlocks; ++k) {
        for (int c = 0; c < inputFile.getNumChannels(); ++c) {
            block[c] = &inputFile.samples[c][k*blockSize];
        }
        
        filter.process(block.data(), inputFile.getNumChannels(), blockSize);
    }
    
    // The input data are processed in place and copied to the output file
    outputFile.samples = inputFile.samples;
    outputFile.save(outputFilename);
    
    return 0;
}
