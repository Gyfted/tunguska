// SPDX-License-Identifier: GPL-2.0-or-later
#include "game_audio.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
static void check(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
int main(){try{
    using namespace tunguska;
    memory ram;
    ram.memref(BR_AUDIO_HEAD)=25;ram.memref(BR_AUDIO_TAIL)=2;
    ram.memref(BR_AUDIO_QUEUE+25)=BR_SOUND_SHOT;ram.memref(BR_AUDIO_QUEUE+26)=-364;
    ram.memref(BR_AUDIO_QUEUE)=BR_SOUND_CELL;ram.memref(BR_AUDIO_QUEUE+1)=364;
    check(drainGameSounds(ram)==((1u<<BR_SOUND_SHOT)|(1u<<BR_SOUND_CELL)),"wraparound/invalid sound IDs");
    check(drainGameSounds(ram)==0 && ram.memref(BR_AUDIO_HEAD).to_int()==2,"effects replayed");
    for(int bad:{-364,-1,27,364}) {
        ram.memref(BR_AUDIO_HEAD)=bad;check(drainGameSounds(ram)==0,"invalid head");
        ram.memref(BR_AUDIO_TAIL)=bad;check(drainGameSounds(ram)==0,"invalid tail");
    }
    GameAudioMixer mixer;
    std::vector<float> output(GameAudioMixer::sampleRate*2);
    for(int id=1;id<=BR_SOUND_COUNT;++id) {
        const auto& sample=mixer.sample(id);
        check(sample.size()>100 && sample.size()<GameAudioMixer::sampleRate,"unbounded effect duration");
        check(sample.front()==0 && sample.back()==0,"effect envelope does not end at silence");
        double energy=0;for(float x:sample){check(std::isfinite(x)&&std::abs(x)<=.3f,"unsafe sample");energy+=x*x;}
        check(energy>0.01,"silent effect");
        mixer.silence();mixer.enqueue(1u<<id);mixer.render(output.data(),output.size());
        check(std::equal(sample.begin(),sample.end(),output.begin()),"rendered PCM differs");
        check(std::all_of(output.begin()+sample.size(),output.end(),[](float x){return x==0;}),"voice continued after effect ended");
    }
    for(int i=0;i<100;++i) {
        mixer.enqueue(0xffffffffu);mixer.render(output.data(),256);
        for(int j=0;j<256;++j)check(std::isfinite(output[j]) && std::abs(output[j])<=.85f,"voice flood escaped mixer bounds");
    }
    mixer.enqueue(GameAudioMixer::effectMask);mixer.silence();mixer.render(output.data(),output.size());
    check(std::all_of(output.begin(),output.end(),[](float x){return x==0;}),"mute retained pending or active audio");
    std::cout<<"PASS sound ring bounds/wrap/invalid IDs; ten original PCM effects, finite samples, envelopes, voice cap and mute\n";
}catch(const std::exception& e){std::cerr<<"FAIL sound: "<<e.what()<<'\n';return 1;}}
