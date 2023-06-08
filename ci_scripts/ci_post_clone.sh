#!/bin/sh

#  ci_post_clone.sh
#  Nostur
#
#  This script takes environment variables configured in Xcode Cloud settings
#  Uses those to generate Config.xcconfig that is needed to build

echo "TENOR_API_KEY = $TENOR_API_KEY" >> ../Config.xcconfig
echo "TENOR_CLIENT_KEY = $TENOR_CLIENT_KEY" >> ../Config.xcconfig
echo "IMGUR_CLIENT_ID = $IMGUR_CLIENT_ID" >> ../Config.xcconfig
echo "NOSTRCHECK_PUBLIC_API_KEY = $NOSTRCHECK_PUBLIC_API_KEY" >> ../Config.xcconfig

