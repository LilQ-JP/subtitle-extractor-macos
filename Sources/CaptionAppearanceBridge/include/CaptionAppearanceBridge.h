#ifndef CaptionAppearanceBridge_h
#define CaptionAppearanceBridge_h

#include <stdbool.h>

typedef struct {
    bool success;
    bool customized;
    double relativeCharacterSize;
    double foregroundRed;
    double foregroundGreen;
    double foregroundBlue;
    double foregroundAlpha;
    double backgroundRed;
    double backgroundGreen;
    double backgroundBlue;
    double backgroundAlpha;
    double windowRed;
    double windowGreen;
    double windowBlue;
    double windowAlpha;
    double windowCornerRadius;
    long textEdgeStyle;
    char fontName[256];
} SECaptionAppearance;

SECaptionAppearance SELoadSystemCaptionAppearance(void);

#endif
