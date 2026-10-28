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
probe SwiftUI "func glassEffect\(|struct GlassEffectContainer|func glassEffectID|struct ToolbarSpacer|func tabBarMinimizeBehavior|func scrollEdgeEffectStyle|static var glassProminent|static var glass:"
probe Vision "struct RecognizeDocumentsRequest|struct DocumentObservation|public var transcript|var text: |detectedData" 30
probe FoundationModels "func respond<|struct LanguageModelSession|case available|var availability" 20
