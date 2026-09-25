// SPDX-License-Identifier: GPL-2.0-or-later
// Executed as a separately signed test app with the production entitlements.
#import <Cocoa/Cocoa.h>
#import "macos/FileAccess.h"
#import "macos/SearchService.h"
#include <cerrno>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <iostream>

static void check(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        try {
            check(argc == 2, "Pass an existing unselected fixture outside the test app/container");
            int fd = open(argv[1], O_RDONLY);
            if (fd >= 0) close(fd);
            check(fd < 0 && (errno == EPERM || errno == EACCES), "sandbox must deny unselected host-file reads");
            const std::string output = std::string(argv[1]) + ".write-attempt";
            fd = open(output.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
            if (fd >= 0) { close(fd); unlink(output.c_str()); }
            check(fd < 0 && (errno == EPERM || errno == EACCES), "sandbox must deny unselected host-file writes");
            int connection = socket(AF_INET, SOCK_STREAM, 0);
            int result = -1;
            if (connection >= 0) {
                sockaddr_in address{};
                address.sin_family = AF_INET; address.sin_port = htons(9); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                result = connect(connection, reinterpret_cast<sockaddr *>(&address), sizeof(address));
            }
            const int networkError = errno;
            if (connection >= 0) close(connection);
            check(result < 0 && (networkError == EPERM || networkError == EACCES), "sandbox must deny outbound network connections");

            NSURL *boot = [NSBundle.mainBundle URLForResource:@"boot" withExtension:@"ternobj"];
            check(boot != nil, "bundled boot image exists");
            tunguska::Runtime runtime(boot.fileSystemRepresentation);
            runtime.run(500000); runtime.capture(true);
            check(runtime.text().find("TUNGUSKA STARTED") != std::string::npos, "bundled OS boots inside App Sandbox");
            NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
            NSError *error = nil;
            check([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error], "create container test directory");
            NSURL *disk = [directory URLByAppendingPathComponent:@"saved.ternobj"];
            runtime.mount(boot.fileSystemRepresentation);
            tunguska::macos::saveDiskImage(runtime, disk);
            memory restored; restored.load(disk.fileSystemRepresentation);
            memory original; original.load(boot.fileSystemRepresentation);
            for (int i = -MEMSIZ/2; i <= MEMSIZ/2; ++i)
                check(restored.memref(i).to_int() == original.memref(i).to_int(), "saved image roundtrip inside sandbox");
            tunguska::macos::saveDiskImage(runtime, disk);
            restored.load(disk.fileSystemRepresentation);
            NSURL *link = [directory URLByAppendingPathComponent:@"link.ternobj"];
            check(symlink(disk.fileSystemRepresentation, link.fileSystemRepresentation) == 0, "create symbolic link fixture");
            bool rejected = false;
            try { tunguska::macos::saveDiskImage(runtime, link); } catch (const std::runtime_error&) { rejected = true; }
            check(rejected, "native save rejects symbolic-link destinations");
            std::atomic<bool> cancel{false};
            NSURL *unselected=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
            rejected=false;
            try { [SearchService indexFolder:unselected.URLByDeletingLastPathComponent cancel:cancel progress:{} semantic:NO]; }
            catch(const std::exception&) { rejected=true; }
            check(rejected,"search index cannot read an unselected private folder");
            NSURL *note=[directory URLByAppendingPathComponent:@"receipt.md"];
            check([@"Receipt for the blue couch in reception." writeToURL:note atomically:YES encoding:NSUTF8StringEncoding error:&error],"write search fixture in container");
            SearchService *search=[SearchService indexFolder:directory cancel:cancel progress:{} semantic:YES];
            check(search.fileCount==1&&search.semanticCount==1,"search and offline model work inside App Sandbox");
            check([[search search:@"couch" meaning:NO reference:NO][@"hits"] count]==1,"sandboxed keyword search");
            check([[search search:@"furniture purchase" meaning:YES reference:NO][@"hits"] count]==1,"sandboxed meaning search");
            [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
            std::cout << "PASS App Sandbox denies unselected file reads/writes, folder indexing and network; boot, coordinated saves and offline search work\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << error.what() << '\n';
            return 1;
        }
    }
}
