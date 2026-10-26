#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p .build/automation-checks
clang -fobjc-arc -fmodules -fmodules-cache-path="$PWD/.build/clang-cache" \
  -I Sources/AutomationBridge/include \
  Sources/AutomationBridge/AutomationBridge.m Tests/AutomationBridgeChecks/main.m \
  -framework Foundation -framework ScriptingBridge -o .build/automation-checks/checks
.build/automation-checks/checks
