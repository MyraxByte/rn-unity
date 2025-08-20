#import "RNUnityView.h"
#ifdef DEBUG
#include <mach-o/ldsyms.h>
#endif

NSString *bundlePathStr = @"/Frameworks/UnityFramework.framework";
int gArgc = 1;

static NSDictionary *appLaunchOpts;
static RNUnityView *sharedInstance = nil;

static UnityFramework* UnityFrameworkLoad(void) {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    bundlePath = [bundlePath stringByAppendingString:bundlePathStr];

    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (![bundle isLoaded]) {
        [bundle load];
    }

    UnityFramework *ufw = [bundle.principalClass getInstance];
    if (![ufw appController]) {
#ifdef DEBUG
        [ufw setExecuteHeader:&_mh_dylib_header];
#else
        [ufw setExecuteHeader:&_mh_execute_header];
#endif
    }
    [ufw setDataBundleId:[bundle.bundleIdentifier cStringUsingEncoding:NSUTF8StringEncoding]];
    return ufw;
}

@implementation RNUnityView

- (BOOL)unityIsInitialized {
    return [self ufw] && [[self ufw] appController];
}

- (void)initUnityModule {
    @try {
        if ([self unityIsInitialized]) {
            return;
        }

        [self setUfw:UnityFrameworkLoad()];
        [[self ufw] registerFrameworkListener:self];

        unsigned count = (unsigned)[[[NSProcessInfo processInfo] arguments] count];
        char **argv = (char **)malloc((count + 1) * sizeof(char *));
        for (unsigned i = 0; i < count; i++) {
            argv[i] = strdup([[[[NSProcessInfo processInfo] arguments] objectAtIndex:i] UTF8String]);
        }
        argv[count] = NULL;

        [[self ufw] runEmbeddedWithArgc:gArgc argv:argv appLaunchOpts:appLaunchOpts];
        [[self ufw] appController].quitHandler = ^(){};

        [self.ufw.appController.rootView removeFromSuperview];

        if (@available(iOS 13.0, *)) {
            [[[[self ufw] appController] window] setWindowScene:nil];
        } else {
            [[[[self ufw] appController] window] setScreen:nil];
        }

        [[[[self ufw] appController] window] addSubview:self.ufw.appController.rootView];
        [[[[self ufw] appController] window] makeKeyAndVisible];
        [[[[[[self ufw] appController] window] rootViewController] view] setNeedsLayout];

        [NSClassFromString(@"FrameworkLibAPI") registerAPIforNativeCalls:self];
    }
    @catch (__unused NSException *e) {
        // Silent catch by request
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if ([self unityIsInitialized]) {
        self.ufw.appController.rootView.frame = self.bounds;
        [self addSubview:self.ufw.appController.rootView];
    }
}

- (void)pauseUnity:(BOOL * _Nonnull)pause {
    if ([self unityIsInitialized]) {
        [[self ufw] pause:pause];
    }
}

- (void)unloadUnity {
    UIWindow *main = [[[UIApplication sharedApplication] delegate] window];
    if (main != nil) {
        [main makeKeyAndVisible];

        if ([self unityIsInitialized]) {
            [[self ufw] unloadApplication];
        }
    }
}

- (void)sendMessageToMobileApp:(NSString *)message {
    if (self.onUnityMessage) {
        NSDictionary *data = @{ @"message": message ?: @"" };
        self.onUnityMessage(data);
    }
}

- (void)unityDidUnload:(NSNotification *)notification {
    if ([self unityIsInitialized]) {
        [[self ufw] unregisterFrameworkListener:self];
        [self setUfw:nil];

        if (self.onPlayerUnload) {
            self.onPlayerUnload(nil);
        }
    }
}

- (void)unityDidQuit:(NSNotification *)notification {
    if ([self unityIsInitialized]) {
        [[self ufw] unregisterFrameworkListener:self];
        [self setUfw:nil];

        if (self.onPlayerQuit) {
            self.onPlayerQuit(nil);
        }
    }
}

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"onUnityMessage", @"onPlayerUnload", @"onPlayerQuit"];
}

- (void)postMessage:(NSString *)gameObject methodName:(NSString *)methodName message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self ufw] sendMessageToGOWithName:[gameObject UTF8String]
                                functionName:[methodName UTF8String]
                                     message:[message UTF8String]];
    });
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        if (!sharedInstance) {
            sharedInstance = self;
        }
        [self initUnityModule];
    }

    return self;
}

@end
