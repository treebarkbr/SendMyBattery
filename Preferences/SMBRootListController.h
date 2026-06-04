#import <Preferences/PSListController.h>

@interface SMBRootListController : PSListController
- (void)refreshDiagnostics;
- (id)readDiagnosticValue:(PSSpecifier *)specifier;
@end
