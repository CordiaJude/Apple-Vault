#!/bin/bash
# Prints the exact declarations of newer iOS 26 APIs from the installed SDK, so
# the code can be checked against the real interfaces rather than memory.
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
probe() { # framework, pattern
  local dir
  dir=$(find "$SDK/System/Library/Frameworks/$1.framework" -name "*.swiftinterface" 2>/dev/null | grep -E "arm64-apple-ios-simulator|x86_64" | head -1)
  echo "── $1 :: $2"
  [ -n "$dir" ] && grep -nE "$2" "$dir" | head -${3:-12}
}



iface() { find "$SDK/System/Library/Frameworks/$1.framework" -name "*.swiftinterface" | grep -E "arm64-apple-ios-simulator" | head -1; }
echo "── AppIntents"; grep -nE "supportedModes|static var openAppWhenRun|protocol ControlConfigurationIntent|struct IntentModes" "$(iface AppIntents)" | head
echo "── SwiftUI glass"; grep -nE "func glassEffect|struct GlassEffectContainer|func glassEffectID|func glassEffectTransition|func glassEffectUnion|public struct Glass |func interactive|func tint\(" "$(iface SwiftUI)" | head -20
echo "── IntentModes"; grep -nE "struct IntentModes|static (let|var) [a-zA-Z]+: AppIntents.IntentModes|static func foreground" "$(iface AppIntents)" | head -20
echo "── DataDetection"; f=$(find "$SDK/System/Library/Frameworks/DataDetection.framework" -name "*.swiftinterface" | grep simulator | head -1); grep -nE "public (enum|struct) Match|case [a-zA-Z]+\(|public var (kind|range|value)" "$f" | head -40
echo "── glass anywhere"; grep -rnE "func glassEffect|struct GlassEffectContainer|func glassEffectID" "$SDK/System/Library/Frameworks/SwiftUICore.framework" "$SDK/System/Library/Frameworks/SwiftUI.framework" --include="*ios-simulator.swiftinterface" | head
