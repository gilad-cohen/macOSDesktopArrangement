#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef int CGSConnectionID;
typedef uint64_t CGSSpaceID;

typedef CGSConnectionID (*CGSMainConnectionIDFn)(void);
typedef CFArrayRef (*CGSCopyManagedDisplaySpacesFn)(CGSConnectionID cid);
typedef CGError (*CGSManagedDisplaySetCurrentSpaceFn)(CGSConnectionID cid, CFStringRef display, CGSSpaceID space);
typedef CGError (*CGSSetWorkspaceFn)(CGSConnectionID cid, int workspace);
typedef CGSSpaceID (*CGSGetActiveSpaceFn)(CGSConnectionID cid);
typedef CFArrayRef (*CGSCopySpacesFn)(CGSConnectionID cid, int mask);
typedef CFArrayRef (*CGSCopySpacesForWindowsFn)(CGSConnectionID cid, int mask, CFArrayRef windowIDs);

static NSString *stringValue(id value) {
    if (!value || value == (id)kCFNull) return @"";
    return [value description];
}

static NSArray<NSDictionary *> *spacesForDisplay(NSDictionary *display) {
    NSArray *spaces = display[@"Spaces"];
    return [spaces isKindOfClass:NSArray.class] ? spaces : @[];
}

static NSString *spaceLabel(NSDictionary *space) {
    NSString *name = stringValue(space[@"name"]);
    NSString *uuid = stringValue(space[@"uuid"]);
    NSString *type = stringValue(space[@"type"]);
    NSString *id64 = stringValue(space[@"id64"] ?: space[@"ManagedSpaceID"]);
    NSArray *windows = [space[@"windows"] isKindOfClass:NSArray.class] ? space[@"windows"] : @[];
    if (name.length == 0) name = @"(unnamed)";
    return [NSString stringWithFormat:@"id=%@ type=%@ windows=%lu name=%@ uuid=%@",
            id64, type, (unsigned long)windows.count, name, uuid];
}

static CGSSpaceID spaceID(NSDictionary *space) {
    id value = space[@"id64"] ?: space[@"ManagedSpaceID"];
    if ([value respondsToSelector:@selector(unsignedLongLongValue)]) {
        return (CGSSpaceID)[value unsignedLongLongValue];
    }
    return 0;
}

static NSDictionary<NSNumber *, NSMutableArray<NSString *> *> *windowLabelsBySpace(CGSConnectionID cid, CGSCopySpacesForWindowsFn copySpacesForWindows) {
    NSMutableDictionary<NSNumber *, NSMutableArray<NSString *> *> *result = [NSMutableDictionary dictionary];
    if (!copySpacesForWindows) return result;

    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    for (NSDictionary *window in windows) {
        NSNumber *windowID = window[(NSString *)kCGWindowNumber];
        NSString *owner = window[(NSString *)kCGWindowOwnerName] ?: @"?";
        NSString *name = window[(NSString *)kCGWindowName] ?: @"";
        NSNumber *layer = window[(NSString *)kCGWindowLayer] ?: @0;
        if (!windowID || layer.integerValue != 0) continue;

        NSArray *windowIDs = @[ windowID ];
        NSArray *spaceIDs = CFBridgingRelease(copySpacesForWindows(cid, 7, (__bridge CFArrayRef)windowIDs));
        for (NSNumber *sid in spaceIDs) {
            if (![sid isKindOfClass:NSNumber.class]) continue;
            NSMutableArray *labels = result[sid];
            if (!labels) {
                labels = [NSMutableArray array];
                result[sid] = labels;
            }
            NSString *label = name.length ? [NSString stringWithFormat:@"%@: %@", owner, name] : owner;
            if (![labels containsObject:label]) [labels addObject:label];
        }
    }
    return result;
}

static void printManagedSpaces(NSArray *managedDisplays, NSDictionary<NSNumber *, NSMutableArray<NSString *> *> *labelsBySpace) {
    printf("\nManaged display Spaces:\n");
    [managedDisplays enumerateObjectsUsingBlock:^(NSDictionary *display, NSUInteger displayIndex, BOOL *stop) {
        NSString *identifier = stringValue(display[@"Display Identifier"] ?: display[@"Identifier"]);
        NSString *current = stringValue(display[@"Current Space"]);
        printf("[%lu] display=%s current=%s\n",
               (unsigned long)displayIndex,
               identifier.UTF8String,
               current.UTF8String);

        [spacesForDisplay(display) enumerateObjectsUsingBlock:^(NSDictionary *space, NSUInteger spaceIndex, BOOL *stopSpace) {
            printf("  %02lu  %s\n", (unsigned long)spaceIndex, spaceLabel(space).UTF8String);
            NSArray *labels = labelsBySpace[@(spaceID(space))] ?: @[];
            for (NSString *label in labels) {
                printf("      - %s\n", label.UTF8String);
            }
        }];
    }];
}

static NSArray<NSDictionary *> *fullscreenSpaces(NSDictionary *display) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *space in spacesForDisplay(display)) {
        NSInteger type = [space[@"type"] respondsToSelector:@selector(integerValue)] ? [space[@"type"] integerValue] : -1;
        NSArray *windows = [space[@"windows"] isKindOfClass:NSArray.class] ? space[@"windows"] : @[];
        // On recent macOS, type 4 is commonly full-screen/tiled. Keep a windows>0 fallback
        // visible in the printout rather than assuming too much about private data.
        if (type == 4 || (type != 0 && windows.count > 0)) {
            [result addObject:space];
        }
    }
    return result;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!skyLight) {
            fprintf(stderr, "Could not load SkyLight: %s\n", dlerror());
            return 2;
        }

        CGSMainConnectionIDFn CGSMainConnectionIDPtr = dlsym(skyLight, "CGSMainConnectionID");
        if (!CGSMainConnectionIDPtr) CGSMainConnectionIDPtr = dlsym(skyLight, "_CGSDefaultConnection");

        CGSCopyManagedDisplaySpacesFn CGSCopyManagedDisplaySpacesPtr = dlsym(skyLight, "CGSCopyManagedDisplaySpaces");
        CGSManagedDisplaySetCurrentSpaceFn CGSManagedDisplaySetCurrentSpacePtr = dlsym(skyLight, "CGSManagedDisplaySetCurrentSpace");
        CGSSetWorkspaceFn CGSSetWorkspacePtr = dlsym(skyLight, "CGSSetWorkspace");
        CGSGetActiveSpaceFn CGSGetActiveSpacePtr = dlsym(skyLight, "CGSGetActiveSpace");
        CGSCopySpacesFn CGSCopySpacesPtr = dlsym(skyLight, "CGSCopySpaces");
        CGSCopySpacesForWindowsFn CGSCopySpacesForWindowsPtr = dlsym(skyLight, "CGSCopySpacesForWindows");

        printf("Symbols:\n");
        printf("  connection: %s\n", CGSMainConnectionIDPtr ? "yes" : "no");
        printf("  CGSCopyManagedDisplaySpaces: %s\n", CGSCopyManagedDisplaySpacesPtr ? "yes" : "no");
        printf("  CGSManagedDisplaySetCurrentSpace: %s\n", CGSManagedDisplaySetCurrentSpacePtr ? "yes" : "no");
        printf("  CGSSetWorkspace: %s\n", CGSSetWorkspacePtr ? "yes" : "no");
        printf("  CGSGetActiveSpace: %s\n", CGSGetActiveSpacePtr ? "yes" : "no");
        printf("  CGSCopySpaces: %s\n", CGSCopySpacesPtr ? "yes" : "no");
        printf("  CGSCopySpacesForWindows: %s\n", CGSCopySpacesForWindowsPtr ? "yes" : "no");

        if (!CGSMainConnectionIDPtr || !CGSCopyManagedDisplaySpacesPtr) {
            fprintf(stderr, "Required private symbols are unavailable on this macOS build.\n");
            return 3;
        }

        CGSConnectionID cid = CGSMainConnectionIDPtr();
        if (CGSGetActiveSpacePtr) {
            printf("Active space id: %llu\n", CGSGetActiveSpacePtr(cid));
        }

        CFArrayRef managed = CGSCopyManagedDisplaySpacesPtr(cid);
        if (!managed) {
            fprintf(stderr, "CGSCopyManagedDisplaySpaces returned nil.\n");
            return 4;
        }

        NSArray *managedDisplays = CFBridgingRelease(managed);
        NSDictionary *labelsBySpace = windowLabelsBySpace(cid, CGSCopySpacesForWindowsPtr);
        printManagedSpaces(managedDisplays, labelsBySpace);

        if (argc >= 2 && strcmp(argv[1], "--switch") == 0) {
            NSDictionary *targetDisplay = managedDisplays.firstObject;
            NSString *displayID = stringValue(targetDisplay[@"Display Identifier"] ?: targetDisplay[@"Identifier"]);
            NSArray *full = fullscreenSpaces(targetDisplay);
            if (full.count < 2 || !CGSManagedDisplaySetCurrentSpacePtr) {
                printf("\nSwitch test skipped: need at least 2 detected full-screen spaces on first display and CGSManagedDisplaySetCurrentSpace.\n");
                return 0;
            }

            CGSSpaceID first = spaceID(full[0]);
            CGSSpaceID second = spaceID(full[1]);
            printf("\nSwitch test: display=%s second fullscreen id=%llu then first fullscreen id=%llu\n",
                   displayID.UTF8String, second, first);
            CGError e1 = CGSManagedDisplaySetCurrentSpacePtr(cid, (__bridge CFStringRef)displayID, second);
            sleep(1);
            CGError e2 = CGSManagedDisplaySetCurrentSpacePtr(cid, (__bridge CFStringRef)displayID, first);
            printf("Switch results: %d, %d\n", e1, e2);
        }
    }
    return 0;
}
