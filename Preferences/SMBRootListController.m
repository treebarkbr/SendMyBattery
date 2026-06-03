#import "SMBRootListController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const SMBDiagnosticsPath = @"/var/mobile/Library/Preferences/com.treebarkbr.sendmybattery.diagnostics.plist";
static NSString *const SMBDiagnosticsGroupID = @"SMBDiagnosticsSnapshotGroup";
static NSString *const SMBDiagnosticsRefreshID = @"SMBDiagnosticsRefresh";

@implementation SMBRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		[_specifiers addObjectsFromArray:[self diagnosticsSpecifiers]];
	}

	return _specifiers;
}

- (void)refreshDiagnostics {
	NSMutableArray *baseSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	[baseSpecifiers addObjectsFromArray:[self diagnosticsSpecifiers]];
	self.specifiers = baseSpecifiers;
	[self reloadSpecifiers];
}

- (NSArray *)diagnosticsSpecifiers {
	NSMutableArray *diagnosticsSpecifiers = [NSMutableArray array];

	PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Diagnostics Snapshot"];
	group.identifier = SMBDiagnosticsGroupID;
	[group setProperty:@"Values are read from the diagnostics plist. Enable Detailed Diagnostics and trigger a battery send to populate fresh data." forKey:@"footerText"];
	[diagnosticsSpecifiers addObject:group];

	PSSpecifier *refresh = [PSSpecifier preferenceSpecifierNamed:@"Refresh Diagnostics"
														 target:self
															set:NULL
															get:NULL
														 detail:Nil
														   cell:PSButtonCell
														   edit:Nil];
	refresh.identifier = SMBDiagnosticsRefreshID;
	refresh.buttonAction = @selector(refreshDiagnostics);
	[diagnosticsSpecifiers addObject:refresh];

	NSDictionary *diagnostics = [NSDictionary dictionaryWithContentsOfFile:SMBDiagnosticsPath];
	if (![diagnostics isKindOfClass:NSDictionary.class] || diagnostics.count == 0) {
		[diagnosticsSpecifiers addObject:[self textSpecifierNamed:@"Status" value:@"No diagnostics file yet"]];
		[diagnosticsSpecifiers addObject:[self textSpecifierNamed:@"File" value:SMBDiagnosticsPath]];
		return diagnosticsSpecifiers;
	}

	NSArray *keys = @[
		@"lastEvent",
		@"lastUpdated",
		@"startedAt",
		@"enabled",
		@"hostConfigured",
		@"port",
		@"notificationsObserved",
		@"duplicateSkips",
		@"invalidConfigurationSkips",
		@"unknownBatterySkips",
		@"packetsSent",
		@"bytesSent",
		@"sendFailures",
		@"activeSendMilliseconds"
	];

	NSDictionary *labels = @{
		@"lastEvent": @"Last Event",
		@"lastUpdated": @"Last Updated",
		@"startedAt": @"Started At",
		@"enabled": @"Enabled",
		@"hostConfigured": @"Host Configured",
		@"port": @"Port",
		@"notificationsObserved": @"Notifications",
		@"duplicateSkips": @"Duplicate Skips",
		@"invalidConfigurationSkips": @"Config Skips",
		@"unknownBatterySkips": @"Unknown Battery Skips",
		@"packetsSent": @"Packets Sent",
		@"bytesSent": @"Bytes Sent",
		@"sendFailures": @"Send Failures",
		@"activeSendMilliseconds": @"Active Send Time"
	};

	for (NSString *key in keys) {
		id value = diagnostics[key];
		if (!value) {
			continue;
		}

		NSString *label = labels[key] ?: key;
		[diagnosticsSpecifiers addObject:[self textSpecifierNamed:label value:[self displayStringForValue:value key:key]]];
	}

	[diagnosticsSpecifiers addObject:[self textSpecifierNamed:@"File" value:SMBDiagnosticsPath]];
	return diagnosticsSpecifiers;
}

- (PSSpecifier *)textSpecifierNamed:(NSString *)name value:(NSString *)value {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
														   target:self
															  set:NULL
															  get:NULL
														   detail:Nil
															 cell:PSTitleValueCell
															 edit:Nil];
	[specifier setProperty:value forKey:@"value"];
	return specifier;
}

- (NSString *)displayStringForValue:(id)value key:(NSString *)key {
	if ([key isEqualToString:@"lastUpdated"] || [key isEqualToString:@"startedAt"]) {
		NSDate *date = [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
		NSDateFormatter *formatter = [NSDateFormatter new];
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterMediumStyle;
		return [formatter stringFromDate:date];
	}

	if ([key isEqualToString:@"activeSendMilliseconds"]) {
		return [NSString stringWithFormat:@"%@ ms", value];
	}

	if ([value isKindOfClass:NSNumber.class]) {
		const char *type = [value objCType];
		if (strcmp(type, @encode(BOOL)) == 0) {
			return [value boolValue] ? @"Yes" : @"No";
		}
		return [value stringValue];
	}

	if ([value isKindOfClass:NSString.class]) {
		return value;
	}

	return [value description];
}

@end
