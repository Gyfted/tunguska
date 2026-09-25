// SPDX-License-Identifier: GPL-2.0-or-later
// Original bounded sound peripheral and offline synthesizer, Mac fork 2026-09-25.
#pragma once
#include "breach_protocol.h"
#include "core/memory.h"
#include <array>
#include <atomic>
#include <cstdint>
#include <vector>

namespace tunguska {
static_assert(std::atomic<uint32_t>::is_always_lock_free && std::atomic<uint64_t>::is_always_lock_free,
              "Audio callback requires lock-free command and statistics atomics");
// Drains at most 26 guest events; repeated IDs in one poll coalesce.
uint32_t drainGameSounds(memory& ram);

class GameAudioMixer {
public:
    static constexpr int sampleRate = 48000;
    static constexpr uint32_t effectMask = (1u << (BR_SOUND_COUNT+1))-2;
    GameAudioMixer();
    // One producer (the UI), one consumer (the audio callback).
    void enqueue(uint32_t effects) { pending_.fetch_or(effects & effectMask, std::memory_order_relaxed); }
    void silence() { pending_.store(resetBit, std::memory_order_release); }
    bool render(float* output, size_t frames); // no allocations or locks
    const std::vector<float>& sample(int effect) const;
    uint64_t renderedFrames() const { return rendered_.load(std::memory_order_relaxed); }
private:
    static constexpr uint32_t resetBit = 1u << 31;
    struct Voice { int effect=0; size_t position=0; };
    std::array<std::vector<float>, BR_SOUND_COUNT+1> samples_;
    std::array<Voice, 8> voices_{};
    size_t nextVoice_=0;
    std::atomic<uint32_t> pending_{0};
    std::atomic<uint64_t> rendered_{0};
};
}
