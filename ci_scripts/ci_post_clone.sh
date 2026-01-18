#!/bin/zsh

#  ci_post_clone.sh
#  Nostur
#
#  This script takes environment variables configured in Xcode Cloud settings
#  Uses those to generate Config.xcconfig that is needed to build with Xcode Cloud

echo "TENOR_API_KEY = $TENOR_API_KEY" >> ../Config.xcconfig
echo "TENOR_CLIENT_KEY = $TENOR_CLIENT_KEY" >> ../Config.xcconfig
echo "KLIPY_API_KEY = $KLIPY_API_KEY" >> ../Config.xcconfig
echo "IMGUR_CLIENT_ID = $IMGUR_CLIENT_ID" >> ../Config.xcconfig
echo "NOSTRCHECK_PUBLIC_API_KEY = $NOSTRCHECK_PUBLIC_API_KEY" >> ../Config.xcconfig
echo "NOSTUR_IS_DESKTOP = $NOSTUR_IS_DESKTOP" >> ../Config.xcconfig
echo "CI_BUILD_NUMBER = $CI_BUILD_NUMBER" >> ../Config.xcconfig
echo "NIP89_APP_REFERENCE = $NIP89_APP_REFERENCE" >> ../Config.xcconfig
echo "NIP89_APP_NAME = $NIP89_APP_NAME" >> ../Config.xcconfig
