//
//  LowPassAudioUnit.h
//  AUv3Host
//
//  Created by Elias Kokkinis on 18/5/21.
//  Copyright © 2021 Apple. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>

/**
  \brief This class implements a DeNoise Audio Unit.
 */
@interface LowPassAudioUnit : AUAudioUnit

/** \brief The audio sample rate in Hz. */
@property float _audioSampleRate;
/** \brief The number of audio channels. */
@property UInt32 _audioChannelCount;
/** \brief The algorithmic latency of this AU in samples. */
@property int _latencyInSamples;

@end
