// SPDX-License-Identifier: GPL-2.0-or-later
// Original oscillator/noise effects; no recordings, music or third-party assets.
#include "game_audio.h"
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace tunguska {
uint32_t drainGameSounds(memory& ram) {
    int head=ram.memref(BR_AUDIO_HEAD).to_int(),tail=ram.memref(BR_AUDIO_TAIL).to_int();
    if(head<0 || head>=BR_AUDIO_SLOTS || tail<0 || tail>=BR_AUDIO_SLOTS) {
        ram.memref(BR_AUDIO_HEAD)=0;ram.memref(BR_AUDIO_TAIL)=0;return 0;
    }
    uint32_t effects=0;
    for(int n=0;n<BR_AUDIO_SLOTS-1 && head!=tail;++n) {
        const int effect=ram.memref(BR_AUDIO_QUEUE+head).to_int();
        if(effect>=1 && effect<=BR_SOUND_COUNT)effects|=1u<<effect;
        head=(head+1)%BR_AUDIO_SLOTS;
    }
    ram.memref(BR_AUDIO_HEAD)=head;
    return effects;
}
GameAudioMixer::GameAudioMixer() {
    constexpr double pi=3.14159265358979323846;
    const double durations[]={0,.14,.24,.28,.38,.17,.90,.65,.07,.045,.36};
    for(int effect=1;effect<=BR_SOUND_COUNT;++effect) {
        auto& pcm=samples_[effect];pcm.resize(size_t(durations[effect]*sampleRate));
        uint32_t noise=0x1a2b3c4du+uint32_t(effect);double phase=0;
        for(size_t i=0;i<pcm.size();++i) {
            const double t=double(i)/sampleRate,u=double(i)/(pcm.size()-1);
            noise=noise*1664525u+1013904223u;
            const double hiss=double(noise>>8)/8388607.5-1;
            double frequency=440,grit=0,gain=.22;
            switch(effect) {
                case BR_SOUND_SHOT: frequency=1100*std::pow(.07,u);grit=.25;break;
                case BR_SOUND_KILL: frequency=240*(1-u)+50;grit=.7;break;
                case BR_SOUND_CELL: frequency=u<.5?660:990;break;
                case BR_SOUND_SUPPLY: frequency=u<.33?440:u<.66?660:880;break;
                case BR_SOUND_HIT: frequency=95;grit=.75;gain=.18;break;
                case BR_SOUND_WIN: {const double notes[]={523.25,659.25,783.99,1046.5};frequency=notes[std::min(3,int(u*4))];break;}
                case BR_SOUND_DEAD: frequency=330*std::pow(.12,u);grit=.25;break;
                case BR_SOUND_EMPTY: frequency=160;grit=.4;gain=.12;break;
                case BR_SOUND_STEP: frequency=70;grit=.8;gain=.055;break;
                case BR_SOUND_START: frequency=u<.5?220:440;gain=.14;break;
            }
            phase+=2*pi*frequency/sampleRate;
            const double tone=.8*std::sin(phase)+.2*std::sin(phase*2);
            const double envelope=std::min({1.0,t/.004,(durations[effect]-t)/.018})*(1-.6*u);
            pcm[i]=float(gain*std::max(0.0,envelope)*((1-grit)*tone+grit*hiss));
        }
        pcm.front()=pcm.back()=0;
    }
}
const std::vector<float>& GameAudioMixer::sample(int effect) const {
    if(effect<1 || effect>BR_SOUND_COUNT)throw std::out_of_range("Unknown sound effect");
    return samples_[effect];
}
bool GameAudioMixer::render(float* output,size_t frames) {
    const uint32_t command=pending_.exchange(0,std::memory_order_acquire);
    if(command & resetBit) {for(auto& v:voices_)v={};nextVoice_=0;}
    for(int effect=1;effect<=BR_SOUND_COUNT;++effect)if(command & (1u<<effect)) {
        // Eight voices bound simultaneous work even under a hostile event flood.
        voices_[nextVoice_]={effect,0};nextVoice_=(nextVoice_+1)%voices_.size();
    }
    bool audible=false;
    for(size_t frame=0;frame<frames;++frame) {
        float mixed=0;
        for(auto& voice:voices_)if(voice.effect) {
            const auto& pcm=samples_[voice.effect];mixed+=pcm[voice.position++];
            if(voice.position==pcm.size())voice={};
        }
        output[frame]=std::clamp(mixed,-.85f,.85f);
        audible|=output[frame]!=0;
    }
    rendered_.fetch_add(frames,std::memory_order_relaxed);
    return audible;
}
}
