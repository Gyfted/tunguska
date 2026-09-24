// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork file access, 2026-09-24.
#pragma once
#import <Foundation/Foundation.h>
#include "runtime.h"

namespace tunguska::macos {
// Keep the original URL: reconstructing it from a path discards its scope.
// A false result is normal for bundle/container URLs or implicit panel grants.
class ScopedURL {
public:
    explicit ScopedURL(NSURL *url) : url_(url), scoped_([url startAccessingSecurityScopedResource]) {}
    ~ScopedURL() { if (scoped_) [url_ stopAccessingSecurityScopedResource]; }
    ScopedURL(const ScopedURL&) = delete;
    ScopedURL& operator=(const ScopedURL&) = delete;
private:
    NSURL *__strong url_;
    bool scoped_;
};
// Coordinates an atomic save without granting access to the enclosing folder.
void saveDiskImage(Runtime& runtime, NSURL *destination);
}
