//
//  LowPassAudioUnit.m
//  AUv3Host iOS
//
//  Created by Elias Kokkinis on 18/5/21.
//  Copyright © 2021 Apple. All rights reserved.
//

#import "LowPassAudioUnit.h"
#import <AVFoundation/AVFoundation.h>

#import "LowPass.hpp"
#import "Buffer.hpp"
#import "AudioUnitHelperTypes.h"

#import <vector>

// Define parameter addresses.
const AudioUnitParameterID myBypassAddress = 100;
const AUValue bypassMin = 0;
const AUValue bypassMax = 1;

const AudioUnitParameterID myOriginalEnabledAddress = 150;
const AUValue originalEnabledMin = 0;
const AUValue originalEnabledMax = 1;

const AudioUnitParameterID myTrueBypassAdress = 200;
const AUValue trueBypassMin = 0;
const AUValue trueBypassMax = 1;

// Define parameter addresses.
const AudioUnitParameterID lowPassParameter = 0;
const float defaultMasterLowPassParameter = 0.4;

@interface LowPassAudioUnit ()

@property (nonatomic, readwrite) AUParameterTree *parameterTree;
@property AUAudioUnitBus *inputBus;
@property AUAudioUnitBus *outputBus;
@property AUAudioUnitBusArray *inputBusArray;
@property AUAudioUnitBusArray *outputBusArray;

@end

@implementation LowPassAudioUnit {
    Buffer _buffer;
    LowPass *_engine;
    
    float _masterLowPassParameter;
    BOOL _originalEnabledParameter;
    
    BOOL isLearningCompleted;
    RenderingState state;
}

@synthesize parameterTree = _parameterTree;
@synthesize _audioSampleRate, _audioChannelCount, _latencyInSamples;

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription options:(AudioComponentInstantiationOptions)options error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    
    if (self == nil) {
        return nil;
    }
    
    NSLog(@"->LowPass initWithComponentDescription");

    state = kOnlineRendering;
    isLearningCompleted = false;

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(swithToOfflineRendering) name:@"previewEngineSwithToOfflineRenderingNotification" object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(switchToOnlineRendering) name:@"previewEngineSwitchToOnlineRenderingNotification" object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(switchToLearningRendering) name:@"previewEngineSwitchToLearningRenderingNotification" object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(resetForLearning) name:@"previewEngineResetForLearningNotification" object:nil];

    // initialize Buffer
    _buffer = Buffer();
    _buffer.maxFrames = 0;
    _buffer.pcmBuffer = nullptr;
    _buffer.mutableAudioBufferList = nullptr;
    
    // Initialize a default format for the busses.
    AVAudioFormat *defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];

    // Create parameter objects.
    AUParameter *bypass = [AUParameterTree createParameterWithIdentifier:@"bypass" name:@"Bypass" address:myBypassAddress min:bypassMin max:bypassMax unit:kAudioUnitParameterUnit_Boolean unitName:nil flags:0 valueStrings:nil dependentParameters:nil];
    
    AUParameter *originalEnabled = [AUParameterTree createParameterWithIdentifier:@"originalEnabled" name:@"OriginalEnabled" address:myOriginalEnabledAddress min:originalEnabledMin max:originalEnabledMax unit:kAudioUnitParameterUnit_Boolean unitName:nil flags:0 valueStrings:nil dependentParameters:nil];

    
    AUParameter *trueBypass = [AUParameterTree createParameterWithIdentifier:@"trueBypass" name:@"TrueBypass" address:myTrueBypassAdress min:trueBypassMin max:trueBypassMax unit:kAudioUnitParameterUnit_Boolean unitName:nil flags:0 valueStrings:nil dependentParameters:nil];

    AUParameter *param = [AUParameterTree createParameterWithIdentifier:@"processingAmount" name:@"Processing Amount" address:lowPassParameter min:0.0 max:1.0 unit:kAudioUnitParameterUnit_Percent unitName:nil flags:0 valueStrings:nil dependentParameters:nil];
    
    // Initialize the parameter values.
    bypass.value = true;
    originalEnabled.value = false;
    trueBypass.value = true;
    param.value = defaultMasterLowPassParameter;
    _masterLowPassParameter = defaultMasterLowPassParameter;
    
    // Create the parameter tree.
    _parameterTree = [AUParameterTree createTreeWithChildren:@[ bypass, originalEnabled, trueBypass, param]];

    // Create the input and output busses (AUAudioUnitBus).
    _inputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormat error:nil];
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormat error:nil];
    
    // Create the input and output bus arrays (AUAudioUnitBusArray).
    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeInput busses:@[_inputBus]];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput busses:@[_outputBus]];

    // A function to provide string representations of parameter values.
    _parameterTree.implementorStringFromValueCallback = ^(AUParameter *param, const AUValue *__nullable valuePtr) {
        AUValue value = valuePtr == nil ? param.value : *valuePtr;
        
        switch (param.address) {
            case myBypassAddress:
                return [NSString stringWithFormat:@"%f", value];
            case myOriginalEnabledAddress:
                return [NSString stringWithFormat:@"%f", value];
            case myTrueBypassAdress:
                return [NSString stringWithFormat:@"%f", value];
            case lowPassParameter:
                return [NSString stringWithFormat:@"%.f", value];
            default:
                return @"?";
        }
    };
    
    __block Buffer *buffer = &_buffer;

    _parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        switch (param.address) {
            case myBypassAddress:
                buffer->bypass = value;
                break;
            case myOriginalEnabledAddress:
                self->_originalEnabledParameter = value;
                break;
            case myTrueBypassAdress:
                buffer->trueBypass = value;
                break;
            case lowPassParameter:
                self->_masterLowPassParameter = value;
                break;
            default:
                break;
        }
    };

    self.maximumFramesToRender = 512;
    int channels = _audioChannelCount ? _audioChannelCount : 2;
    float sampleRate = _audioSampleRate ? _audioSampleRate : 44100.0;

    _engine = new LowPass();
    _engine->setup(sampleRate, self.maximumFramesToRender, channels);
    _engine->setUserParameterValue(_masterLowPassParameter);

    return self;
}

#pragma mark - Notifications handlers

- (void)swithToOfflineRendering {
    state = kOfflineRendering;
}

- (void)switchToOnlineRendering {
    state = kOnlineRendering;
}

- (void)switchToLearningRendering {
    isLearningCompleted = false;
    state = kLearningRendering;
}

- (void)resetForLearning {
    NSLog(@"->DeNoise resetForLearning");
    isLearningCompleted = false;
}

#pragma mark - AUAudioUnit Overrides

// If an audio unit has input, an audio unit's audio input connection points.
// Subclassers must override this property getter and should return the same object every time.
// See sample code.
- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

// An audio unit's audio output connection points.
// Subclassers must override this property getter and should return the same object every time.
// See sample code.
- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
   
    //NSLog(@"->DeNoise allocateRenderResources");
    //NSLog(@"audioChannelCount: %u audioSampleRate: %f",(unsigned int)_audioChannelCount,_audioSampleRate);

    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    
    
    float sampleRate = _audioSampleRate ? _audioSampleRate : 44100.0;
    int channels = _audioChannelCount ? _audioChannelCount : 2;

    _engine->setup(sampleRate, self.maximumFramesToRender, channels);
    _engine->setUserParameterValue(_masterLowPassParameter);

    // Validate that the bus formats are compatible.
    // Allocate your resources.
    if (self.outputBus.format.channelCount != _inputBus.format.channelCount) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_FailedInitialization userInfo:nil];
            NSLog(@"kAudioUnitErr_FailedInitialization at %d", __LINE__);
        }
        self.renderResourcesAllocated = NO;
        return NO;
    }
    
    // Allocate your resources.
    _buffer.maxFrames = self.maximumFramesToRender;
    _buffer.pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_inputBus.format frameCapacity: self.maximumFramesToRender];
    _buffer.originalAudioBufferList = _buffer.pcmBuffer.audioBufferList;
    _buffer.mutableAudioBufferList = _buffer.pcmBuffer.mutableAudioBufferList;

    _latencyInSamples = _engine->getLatencySamples();


    return YES;
}

// Deallocate resources allocated in allocateRenderResourcesAndReturnError:
// Subclassers should call the superclass implementation.
- (void)deallocateRenderResources {
    // Deallocate your resources.

    [super deallocateRenderResources];

}

#pragma mark - AUAudioUnit (AUAudioUnitImplementation)

// Block which subclassers must provide to implement rendering.
- (AUInternalRenderBlock)internalRenderBlock {
    // Capture in locals to avoid Obj-C member lookups. If "self" is captured in render, we're doing it wrong. See sample code.
    NSLog(@"->DeNoise internalRenderBlock");

    __block Buffer* buffer = &_buffer;
    __block LowPass* engine = _engine;
    __block UInt32& audioChannelCount = _audioChannelCount;

    __block float& internalMasterLowPassParameter = _masterLowPassParameter;
    __block float lastUpdatedInternalMasterLowPassParameter = _masterLowPassParameter;
    
    __block bool& originalEnabled = _originalEnabledParameter;
    
    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, NSInteger outputBusNumber, AudioBufferList *outputData, const AURenderEvent *realtimeEventListHead, AURenderPullInputBlock pullInputBlock) {
        // Do event handling and signal processing here.
        
        AudioUnitRenderActionFlags pullFlags = 0;
        buffer->prepareInputBufferList();
        AUAudioUnitStatus err = pullInputBlock(&pullFlags, timestamp, frameCount, 0, buffer->mutableAudioBufferList);
        
        if (err != 0) {
            NSLog(@"AudioUnitRenderActionFlags");
            return err;
        }
        

        AudioBufferList *inAudioBufferList = buffer->mutableAudioBufferList;
        AudioBufferList *outAudioBufferList = outputData;
        
        // If passed null output buffer pointers, process in-place in the input buffer.
        if (outAudioBufferList->mBuffers[0].mData == nullptr) {
            for (UInt32 i = 0; i < outAudioBufferList->mNumberBuffers; ++i) {
                outAudioBufferList->mBuffers[i].mData = inAudioBufferList->mBuffers[i].mData;
            }
        }
        
        UInt32 dataSize = inAudioBufferList->mBuffers[0].mDataByteSize;
        
        //int channels = inAudioBufferList->mNumberBuffers;
        audioChannelCount = 2;
        std::vector<float*> arrayOfPointers(audioChannelCount);

        //Update engine parameter if needed
        bool isBypassed = buffer->bypass == true || originalEnabled == true;
        if (isBypassed) {//Bypass or Original
            engine->setUserParameterValue(0.0);
            lastUpdatedInternalMasterLowPassParameter = 0.0;
        } else {
            if (internalMasterLowPassParameter != lastUpdatedInternalMasterLowPassParameter) {
                engine->setUserParameterValue(internalMasterLowPassParameter);
                lastUpdatedInternalMasterLowPassParameter = internalMasterLowPassParameter;
            }
        }
        
        for (int j = 0; j < audioChannelCount; j++) {
            arrayOfPointers[j] = (float*)inAudioBufferList->mBuffers[j].mData;
        }
        
        engine->process(arrayOfPointers.data(), audioChannelCount, frameCount);
        
        // Swap nans with 0s.
        for (int iChannel = 0; iChannel < audioChannelCount; iChannel++)
        {
            for (int iSample = 0; iSample < frameCount; iSample++)
            {
                if (isnan(arrayOfPointers[iChannel][iSample]))
                {
                    arrayOfPointers[iChannel][iSample] = 0.f;
                }
            }
        }
        
        for (int j = 0; j < audioChannelCount; j++) {
            float* output = (float*)outAudioBufferList->mBuffers[j].mData;
            float* processedData = (float *)arrayOfPointers[j];

            for (int i = 0; i < dataSize / sizeof(float) ; i++) {

                output[i] = processedData[i];
                
            }
        }
        return noErr;
    };
}

@end

