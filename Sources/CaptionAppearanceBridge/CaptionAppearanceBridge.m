#import "CaptionAppearanceBridge.h"

#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#import <MediaAccessibility/MACaptionAppearance.h>
#import <string.h>

static void SEAssignColor(CGColorRef color, double *red, double *green, double *blue, double *alpha) {
    if (color == NULL) {
        return;
    }

    size_t componentCount = CGColorGetNumberOfComponents(color);
    const CGFloat *components = CGColorGetComponents(color);
    if (components == NULL || componentCount == 0) {
        return;
    }

    if (componentCount >= 4) {
        *red = components[0];
        *green = components[1];
        *blue = components[2];
        *alpha = components[3];
        return;
    }

    if (componentCount == 2) {
        *red = components[0];
        *green = components[0];
        *blue = components[0];
        *alpha = components[1];
        return;
    }
}

SECaptionAppearance SELoadSystemCaptionAppearance(void) {
    SECaptionAppearance appearance = {0};

    MACaptionAppearanceBehavior behavior = kMACaptionAppearanceBehaviorUseValue;
    appearance.relativeCharacterSize = MACaptionAppearanceGetRelativeCharacterSize(
        kMACaptionAppearanceDomainUser,
        &behavior
    );
    appearance.textEdgeStyle = MACaptionAppearanceGetTextEdgeStyle(
        kMACaptionAppearanceDomainUser,
        &behavior
    );
    appearance.windowCornerRadius = MACaptionAppearanceGetWindowRoundedCornerRadius(
        kMACaptionAppearanceDomainUser,
        &behavior
    );

    CGColorRef foreground = MACaptionAppearanceCopyForegroundColor(kMACaptionAppearanceDomainUser, &behavior);
    CGColorRef background = MACaptionAppearanceCopyBackgroundColor(kMACaptionAppearanceDomainUser, &behavior);
    CGColorRef window = MACaptionAppearanceCopyWindowColor(kMACaptionAppearanceDomainUser, &behavior);

    SEAssignColor(
        foreground,
        &appearance.foregroundRed,
        &appearance.foregroundGreen,
        &appearance.foregroundBlue,
        &appearance.foregroundAlpha
    );
    SEAssignColor(
        background,
        &appearance.backgroundRed,
        &appearance.backgroundGreen,
        &appearance.backgroundBlue,
        &appearance.backgroundAlpha
    );
    SEAssignColor(
        window,
        &appearance.windowRed,
        &appearance.windowGreen,
        &appearance.windowBlue,
        &appearance.windowAlpha
    );

    appearance.foregroundAlpha = MACaptionAppearanceGetForegroundOpacity(kMACaptionAppearanceDomainUser, &behavior);
    appearance.backgroundAlpha = MACaptionAppearanceGetBackgroundOpacity(kMACaptionAppearanceDomainUser, &behavior);
    appearance.windowAlpha = MACaptionAppearanceGetWindowOpacity(kMACaptionAppearanceDomainUser, &behavior);

    if (@available(macOS 15.0, *)) {
        appearance.customized = MACaptionAppearanceIsCustomized(kMACaptionAppearanceDomainUser);
    } else {
        appearance.customized = false;
    }

    CTFontDescriptorRef descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(
        kMACaptionAppearanceDomainUser,
        &behavior,
        kMACaptionAppearanceFontStyleDefault
    );
    if (descriptor != NULL) {
        CFStringRef name = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute);
        if (name == NULL) {
            name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
        }
        if (name != NULL) {
            NSString *fontName = (__bridge_transfer NSString *)name;
            strncpy(appearance.fontName, fontName.UTF8String, sizeof(appearance.fontName) - 1);
            appearance.fontName[sizeof(appearance.fontName) - 1] = '\0';
        }
        CFRelease(descriptor);
    }

    if (foreground != NULL) {
        CFRelease(foreground);
    }
    if (background != NULL) {
        CFRelease(background);
    }
    if (window != NULL) {
        CFRelease(window);
    }

    appearance.success = true;
    return appearance;
}
