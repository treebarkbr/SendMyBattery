#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <notify.h>
#import <sys/socket.h>
#import <mach/mach_time.h>
#import <unistd.h>

static NSString *const SMBPreferencesIdentifier = @"com.treebarkbr.sendmybattery";
static CFStringRef const SMBPreferencesChangedNotification = CFSTR("com.treebarkbr.sendmybattery/preferences.changed");
static NSString *const SMBDiagnosticsPath = @"/var/mobile/Library/Preferences/com.treebarkbr.sendmybattery.diagnostics.plist";

static void SMBPreferencesDidChange(CFNotificationCenterRef center,
									void *observer,
									CFStringRef name,
									const void *object,
									CFDictionaryRef userInfo);

@interface SendMyBatterySender : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL sendInitial;
@property (nonatomic, assign) BOOL detailedDiagnostics;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, assign) NSInteger lastSentPercent;
@property (nonatomic, assign) NSUInteger notificationCount;
@property (nonatomic, assign) NSUInteger duplicateSkipCount;
@property (nonatomic, assign) NSUInteger invalidConfigurationSkipCount;
@property (nonatomic, assign) NSUInteger unknownBatterySkipCount;
@property (nonatomic, assign) NSUInteger packetCount;
@property (nonatomic, assign) NSUInteger failureCount;
@property (nonatomic, assign) NSUInteger byteCount;
@property (nonatomic, assign) double activeSendMilliseconds;
@property (nonatomic, strong) NSDate *startedAt;
+ (instancetype)sharedInstance;
- (void)start;
@end

@implementation SendMyBatterySender

+ (instancetype)sharedInstance {
	static SendMyBatterySender *sender;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sender = [self new];
	});
	return sender;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_lastSentPercent = NSIntegerMin;
		_enabled = YES;
		_sendInitial = YES;
		_startedAt = [NSDate date];
	}
	return self;
}

- (void)start {
	[self reloadPreferences];

	UIDevice *device = UIDevice.currentDevice;
	device.batteryMonitoringEnabled = YES;

	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(batteryLevelDidChange:)
											   name:UIDeviceBatteryLevelDidChangeNotification
											 object:device];

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
									(__bridge const void *)(self),
									SMBPreferencesDidChange,
									SMBPreferencesChangedNotification,
									NULL,
									CFNotificationSuspensionBehaviorDeliverImmediately);

	if (self.sendInitial) {
		[self sendCurrentBatteryIfChanged:YES];
	}
}

- (void)reloadPreferences {
	CFPreferencesAppSynchronize((__bridge CFStringRef)SMBPreferencesIdentifier);

	self.enabled = [self boolPreferenceForKey:@"enabled" defaultValue:YES];
	self.sendInitial = [self boolPreferenceForKey:@"sendInitial" defaultValue:YES];
	self.detailedDiagnostics = [self boolPreferenceForKey:@"detailedDiagnostics" defaultValue:NO];

	NSString *host = [self stringPreferenceForKey:@"host"];
	self.host = [host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

	NSInteger port = [self integerPreferenceForKey:@"port" defaultValue:0];
	self.port = port;
}

- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
	CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)SMBPreferencesIdentifier);
	if (!value) {
		return defaultValue;
	}

	BOOL result = defaultValue;
	if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
		result = CFBooleanGetValue((CFBooleanRef)value);
	} else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
		int numberValue = 0;
		CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &numberValue);
		result = numberValue != 0;
	}

	CFRelease(value);
	return result;
}

- (NSInteger)integerPreferenceForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
	CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)SMBPreferencesIdentifier);
	if (!value) {
		return defaultValue;
	}

	NSInteger result = defaultValue;
	if (CFGetTypeID(value) == CFNumberGetTypeID()) {
		CFNumberGetValue((CFNumberRef)value, kCFNumberNSIntegerType, &result);
	} else if (CFGetTypeID(value) == CFStringGetTypeID()) {
		result = [(__bridge NSString *)value integerValue];
	}

	CFRelease(value);
	return result;
}

- (NSString *)stringPreferenceForKey:(NSString *)key {
	CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)SMBPreferencesIdentifier);
	if (!value) {
		return @"";
	}

	NSString *result = @"";
	if (CFGetTypeID(value) == CFStringGetTypeID()) {
		result = [(__bridge NSString *)value copy];
	}

	CFRelease(value);
	return result;
}

- (void)batteryLevelDidChange:(NSNotification *)notification {
	self.notificationCount += 1;
	[self sendCurrentBatteryIfChanged:NO];
}

- (void)sendCurrentBatteryIfChanged:(BOOL)force {
	if (!self.enabled || self.host.length == 0 || self.port <= 0 || self.port > 65535) {
		self.invalidConfigurationSkipCount += 1;
		[self writeDiagnosticsWithLastEvent:@"skipped-invalid-configuration"];
		return;
	}

	float batteryLevel = UIDevice.currentDevice.batteryLevel;
	if (batteryLevel < 0.0f) {
		self.unknownBatterySkipCount += 1;
		[self writeDiagnosticsWithLastEvent:@"skipped-unknown-battery"];
		return;
	}

	NSInteger percent = (NSInteger)lroundf(batteryLevel * 100.0f);
	if (!force && percent == self.lastSentPercent) {
		self.duplicateSkipCount += 1;
		[self writeDiagnosticsWithLastEvent:@"skipped-duplicate-percent"];
		return;
	}

	if ([self sendBatteryPercent:percent]) {
		self.lastSentPercent = percent;
	}
}

- (BOOL)sendBatteryPercent:(NSInteger)percent {
	NSString *payload = [self payloadForBatteryPercent:percent];
	NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
	if (!data) {
		self.failureCount += 1;
		[self writeDiagnosticsWithLastEvent:@"failed-payload-encoding"];
		return NO;
	}

	struct addrinfo hints;
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_DGRAM;
	hints.ai_protocol = IPPROTO_UDP;

	char portBuffer[8];
	snprintf(portBuffer, sizeof(portBuffer), "%ld", (long)self.port);

	struct addrinfo *addresses = NULL;
	int lookupResult = getaddrinfo(self.host.UTF8String, portBuffer, &hints, &addresses);
	if (lookupResult != 0 || !addresses) {
		self.failureCount += 1;
		[self writeDiagnosticsWithLastEvent:@"failed-host-lookup"];
		return NO;
	}

	uint64_t started = mach_absolute_time();
	BOOL sent = NO;
	for (struct addrinfo *address = addresses; address != NULL; address = address->ai_next) {
		int socketFD = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
		if (socketFD < 0) {
			continue;
		}

		ssize_t bytesSent = sendto(socketFD, data.bytes, data.length, 0, address->ai_addr, address->ai_addrlen);
		close(socketFD);

		if (bytesSent == (ssize_t)data.length) {
			sent = YES;
			break;
		}
	}

	freeaddrinfo(addresses);
	self.activeSendMilliseconds += [self millisecondsSinceMachTime:started];

	if (sent) {
		self.packetCount += 1;
		self.byteCount += data.length;
		[self writeDiagnosticsWithLastEvent:@"sent"];
	} else {
		self.failureCount += 1;
		[self writeDiagnosticsWithLastEvent:@"failed-send"];
	}

	return sent;
}

- (NSString *)payloadForBatteryPercent:(NSInteger)percent {
	if (!self.detailedDiagnostics) {
		return [NSString stringWithFormat:@"{\"battery\":%ld}", (long)percent];
	}

	UIDevice *device = UIDevice.currentDevice;
	NSString *state = [self stringForBatteryState:device.batteryState];
	NSInteger uptimeSeconds = (NSInteger)llround([NSDate.date timeIntervalSinceDate:self.startedAt]);

	return [NSString stringWithFormat:
			@"{\"battery\":%ld,\"state\":\"%@\",\"source\":\"SendMyBattery\",\"uptimeSeconds\":%ld,\"packetsSent\":%lu,\"bytesSent\":%lu,\"sendFailures\":%lu}",
			(long)percent,
			state,
			(long)uptimeSeconds,
			(unsigned long)self.packetCount,
			(unsigned long)self.byteCount,
			(unsigned long)self.failureCount];
}

- (NSString *)stringForBatteryState:(UIDeviceBatteryState)state {
	switch (state) {
		case UIDeviceBatteryStateUnplugged:
			return @"unplugged";
		case UIDeviceBatteryStateCharging:
			return @"charging";
		case UIDeviceBatteryStateFull:
			return @"full";
		case UIDeviceBatteryStateUnknown:
		default:
			return @"unknown";
	}
}

- (double)millisecondsSinceMachTime:(uint64_t)started {
	static mach_timebase_info_data_t timebase;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		mach_timebase_info(&timebase);
	});

	uint64_t elapsed = mach_absolute_time() - started;
	double nanoseconds = (double)elapsed * (double)timebase.numer / (double)timebase.denom;
	return nanoseconds / 1000000.0;
}

- (void)writeDiagnosticsWithLastEvent:(NSString *)lastEvent {
	if (!self.detailedDiagnostics) {
		return;
	}

	NSDictionary *diagnostics = @{
		@"enabled": @(self.enabled),
		@"hostConfigured": @(self.host.length > 0),
		@"port": @(self.port),
		@"lastEvent": lastEvent,
		@"lastUpdated": @([NSDate.date timeIntervalSince1970]),
		@"startedAt": @([self.startedAt timeIntervalSince1970]),
		@"notificationsObserved": @(self.notificationCount),
		@"duplicateSkips": @(self.duplicateSkipCount),
		@"invalidConfigurationSkips": @(self.invalidConfigurationSkipCount),
		@"unknownBatterySkips": @(self.unknownBatterySkipCount),
		@"packetsSent": @(self.packetCount),
		@"bytesSent": @(self.byteCount),
		@"sendFailures": @(self.failureCount),
		@"activeSendMilliseconds": @((NSInteger)llround(self.activeSendMilliseconds))
	};

	[diagnostics writeToFile:SMBDiagnosticsPath atomically:YES];
}

@end

static void SMBPreferencesDidChange(CFNotificationCenterRef center,
									void *observer,
									CFStringRef name,
									const void *object,
									CFDictionaryRef userInfo) {
	SendMyBatterySender *sender = (__bridge SendMyBatterySender *)observer;
	[sender reloadPreferences];
	if (sender.sendInitial) {
		[sender sendCurrentBatteryIfChanged:YES];
	}
}

%ctor {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[SendMyBatterySender sharedInstance] start];
	});
}
