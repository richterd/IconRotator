TWEAK_NAME = IconRotator
IconRotator_FILES = Tweak.x
IconRotator_FRAMEWORKS = Foundation UIKit QuartzCore CoreMotion

ADDITIONAL_CFLAGS = -std=c99

include framework/makefiles/common.mk
include framework/makefiles/tweak.mk
