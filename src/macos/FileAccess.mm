// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork file access, 2026-09-24.
#import "FileAccess.h"
#include <cerrno>
#include <sys/stat.h>

namespace tunguska::macos {
static void fail(NSError *error, const char *fallback) {
    throw std::runtime_error(error ? error.localizedDescription.UTF8String : fallback);
}
void saveDiskImage(Runtime& runtime, NSURL *destination) {
    if (!destination.isFileURL) throw std::runtime_error("Choose a local file for the disk image");
    ScopedURL access(destination);
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSError *coordinationError = nil;
    __block std::string failure;
    __block bool saved = false;
    [coordinator coordinateWritingItemAtURL:destination options:NSFileCoordinatorWritingForReplacing
        error:&coordinationError byAccessor:^(NSURL *url) {
        NSFileManager *manager = NSFileManager.defaultManager;
        NSURL *temporaryDirectory = nil;
        try {
            struct stat previous;
            const bool exists = lstat(url.fileSystemRepresentation, &previous) == 0;
            if (exists && !S_ISREG(previous.st_mode))
                throw std::runtime_error("Choose a regular output file, not a directory or symbolic link");
            if (!exists && errno != ENOENT) throw std::runtime_error("Cannot inspect output path");
            NSError *error = nil;
            // Foundation obtains sandbox access to a same-volume replacement
            // directory. The Save panel grants the destination, not its parent.
            temporaryDirectory = [manager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask
                appropriateForURL:url create:YES error:&error];
            if (!temporaryDirectory) fail(error, "Cannot create replacement directory");
            NSURL *staged = [temporaryDirectory URLByAppendingPathComponent:@"disk.ternobj"];
            runtime.saveDisk(staged.fileSystemRepresentation);
            if (exists) {
                if (![manager replaceItemAtURL:url withItemAtURL:staged backupItemName:nil options:0 resultingItemURL:nil error:&error])
                    fail(error, "Cannot replace disk image");
            } else if (![manager moveItemAtURL:staged toURL:url error:&error]) {
                fail(error, "Cannot create disk image");
            }
            saved = true;
        } catch (const std::exception& error) {
            failure = error.what();
        }
        if (temporaryDirectory) [manager removeItemAtURL:temporaryDirectory error:nil];
    }];
    if (!saved) {
        if (!failure.empty()) throw std::runtime_error(failure);
        fail(coordinationError, "Unable to coordinate the disk save");
    }
}
}
