//
//  LowPass.hpp
//  lowpass-demo
//
//  Created by Elias Kokkinis on 18/5/21.
//

#pragma once

#include <memory>

class ParametricEQ;

class LowPass
{
public:
    
    /** \brief The default class constructor.

     Note that you have to call loadFXConfig() to setup a signal chain.
     Otherwise, no processing will take place.
     */
    LowPass();

    ~LowPass();
    
    /** \brief Set up the LowPas engine.
     
     Allocates internal buffers and initializes various objects.
     The user should call this method **prior*** to any calls to the
     process() or loadFXConfig() methods.
     
     @param sampleRate The sample rate of the input audio signal in Hz.
     @param maxBlockSize The maximum length of the input buffer in samples.
     @param numChannels The number of channels of the input buffer.
     */
    void setup(double sampleRate, int maxBlockSize, int numChannels);
    
    /** \brief Process an input signal in-place.

     The process() method expects an array of float pointers. Each pointer
     corresponds to an input channel.
     
     @param inputBuffer The channel array of the input buffer data which will
     be processed **in-place**.
     @param numChannels The number of channels of the input buffer.
     @param numSamples The total number of samples of the input buffer.
     */
    void process(float** inputBuffer, int numChannels, int numSamples);
    
    /** \brief Set the effect parameter value.

     This method maps a normalized value between 0.0 to 1.0 to the internal
     parameters of the MultiFXProcessor and changes the properties of the
     current effect.
     
     @param parameterValue The normalized value of the user parameter.
     */
    void setUserParameterValue(float parameterValue);

    /** \brief Returns the algorithmic latency of the complete signal chain
    in samples.
     */
    int getLatencySamples();
    
    /** \brief Set bypass value

     Use this method to bypass processing but keep the algorithmic latency
     consistent, so any latency compensation inside an audio engine
     remains effective.

     */
    void setBypass(bool shouldBypass);
    
private:
    std::unique_ptr<ParametricEQ> eq;
    
};
