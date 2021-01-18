#import "AutomlObjectDetectionPlugin.h"
#if __has_include(<automl_object_detection/automl_object_detection-Swift.h>)
#import <automl_object_detection/automl_object_detection-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "automl_object_detection-Swift.h"
#endif

@implementation AutomlObjectDetectionPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAutomlObjectDetectionPlugin registerWithRegistrar:registrar];
}
@end
