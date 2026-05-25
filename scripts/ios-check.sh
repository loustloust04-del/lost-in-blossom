#!/bin/bash
# iOS completeness checker — outputs a score 0-6
cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace"
score=0

# 1. Three-screen navigation structure (TabView or enum-based screen switching)
if grep -q 'TabView\|enum.*Screen\|case.*sidebar.*case.*chat\|\.tag(' MemoryPalace/Views/ContentView.swift 2>/dev/null; then
  ((score++))
fi

# 2. Proper NavigationLink(value:) in sidebar rows (not EmptyView hack)
if grep -q 'NavigationLink(value:' MemoryPalace/Views/SidebarView.swift 2>/dev/null; then
  ((score++))
fi

# 3. No misplaced navigationDestination inside sidebar column on iOS
# (the broken pattern: #else block with .navigationDestination inside sidebar)
if ! grep -A3 '#else' MemoryPalace/Views/ContentView.swift 2>/dev/null | grep -q 'navigationDestination'; then
  ((score++))
fi

# 4. Build succeeds
if xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -q "BUILD SUCCEEDED"; then
  ((score++))
fi

# 5. Sufficient iOS-specific layout code (3+ #if os(iOS) blocks across Views/)
ios_blocks=$(grep -rc '#if os(iOS)' MemoryPalace/Views/ 2>/dev/null | awk -F: '{s+=$2} END {print s}')
if [ "$ios_blocks" -ge 3 ]; then
  ((score++))
fi

# 6. Keyboard/safe area handling in chat input
if grep -q 'scrollDismissesKeyboard\|safeAreaInset\|keyboardAvoidance\|\.keyboard' MemoryPalace/Views/CardFlowView.swift 2>/dev/null; then
  ((score++))
fi

echo $score
