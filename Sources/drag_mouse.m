#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

static void post(CGEventType type, CGPoint point, CGMouseButton button) {
    CGEventRef event = CGEventCreateMouseEvent(NULL, type, point, button);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 5 && argc != 6) {
            fprintf(stderr, "usage: drag-mouse fromX fromY toX toY [durationMs]\n");
            return 64;
        }

        CGPoint from = CGPointMake(atof(argv[1]), atof(argv[2]));
        CGPoint to = CGPointMake(atof(argv[3]), atof(argv[4]));
        double durationMs = argc == 6 ? atof(argv[5]) : 120.0;
        if (durationMs < 20.0) durationMs = 20.0;

        post(kCGEventMouseMoved, from, kCGMouseButtonLeft);
        usleep(25000);
        post(kCGEventLeftMouseDown, from, kCGMouseButtonLeft);
        usleep(50000);

        int steps = (int)ceil(durationMs / 8.0);
        if (steps < 4) steps = 4;
        useconds_t stepDelay = (useconds_t)((durationMs * 1000.0) / steps);
        for (int i = 1; i <= steps; i++) {
            CGFloat t = (CGFloat)i / (CGFloat)steps;
            CGPoint p = CGPointMake(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
            post(kCGEventLeftMouseDragged, p, kCGMouseButtonLeft);
            usleep(stepDelay);
        }

        usleep(50000);
        post(kCGEventLeftMouseUp, to, kCGMouseButtonLeft);
        return 0;
    }
}
