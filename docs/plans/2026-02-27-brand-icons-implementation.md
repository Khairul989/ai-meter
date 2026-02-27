# Brand Icons Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the `sparkles` and `airplane` SF Symbols in the Claude/Copilot tab buttons with the real brand icons sourced from local image files.

**Architecture:** Add `claude.png` and a PNG-converted `copilot.webp` as image sets in `Assets.xcassets`, introduce a `TabIcon` enum in `PopoverView.swift` to distinguish system vs asset icons, and update `tabButton` to render each type appropriately. Run `xcodegen generate` after asset changes.

**Tech Stack:** SwiftUI, XcodeGen, macOS 14+, `Assets.xcassets` image sets

---

### Task 1: Convert copilot.webp to PNG

`copilot.webp` (at repo root) must be converted to PNG — Xcode's asset catalog compiler does not support `.webp`.

**Files:**
- Source: `copilot.webp` (repo root)
- Output: `copilot.png` (repo root, temporary staging location)

**Step 1: Convert using sips (built-in macOS tool)**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
sips -s format png copilot.webp --out copilot.png
```

Expected output: `copilot.png` created at repo root.

**Step 2: Verify the output**

```bash
file copilot.png
```

Expected: `copilot.png: PNG image data, 512 x 512, ...`

---

### Task 2: Add claude image set to Assets.xcassets

**Files:**
- Create: `AIMeter/Resources/Assets.xcassets/claude.imageset/Contents.json`
- Copy: `claude.png` → `AIMeter/Resources/Assets.xcassets/claude.imageset/claude.png`

**Step 1: Create the imageset directory and copy the image**

```bash
mkdir -p AIMeter/Resources/Assets.xcassets/claude.imageset
cp claude.png AIMeter/Resources/Assets.xcassets/claude.imageset/claude.png
```

**Step 2: Create Contents.json**

Create `AIMeter/Resources/Assets.xcassets/claude.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "claude.png",
      "idiom": "universal",
      "scale": "1x"
    },
    {
      "idiom": "universal",
      "scale": "2x"
    },
    {
      "idiom": "universal",
      "scale": "3x"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

---

### Task 3: Add copilot image set to Assets.xcassets

**Files:**
- Create: `AIMeter/Resources/Assets.xcassets/copilot.imageset/Contents.json`
- Copy: `copilot.png` → `AIMeter/Resources/Assets.xcassets/copilot.imageset/copilot.png`

**Step 1: Create the imageset directory and copy the image**

```bash
mkdir -p AIMeter/Resources/Assets.xcassets/copilot.imageset
cp copilot.png AIMeter/Resources/Assets.xcassets/copilot.imageset/copilot.png
```

**Step 2: Create Contents.json**

Create `AIMeter/Resources/Assets.xcassets/copilot.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "copilot.png",
      "idiom": "universal",
      "scale": "1x"
    },
    {
      "idiom": "universal",
      "scale": "2x"
    },
    {
      "idiom": "universal",
      "scale": "3x"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

---

### Task 4: Regenerate Xcode project

After adding new assets to the catalog, XcodeGen must be re-run so the project picks them up.

**Step 1: Run xcodegen from AIMeter/**

```bash
cd AIMeter
xcodegen generate
cd ..
```

Expected: `✔ Done` with no errors.

---

### Task 5: Update TabBarView in PopoverView.swift

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift:117-151`

**Step 1: Add the TabIcon enum just above the TabBarView struct**

After line 116 (before `// MARK: - TabBarView`), add:

```swift
// MARK: - TabIcon

enum TabIcon {
    case system(String)
    case asset(String)
}
```

**Step 2: Update tabButton signature and body**

Replace the existing `tabButton` function (lines 131–150) with:

```swift
private func tabButton(_ tab: Tab, icon: TabIcon, label: String?) -> some View {
    Button {
        selectedTab = tab
    } label: {
        HStack(spacing: 4) {
            switch icon {
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: 11))
            case .asset(let name):
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
            }
            if let label = label {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundColor(selectedTab == tab ? .white : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    .buttonStyle(.plain)
}
```

**Step 3: Update the call sites in TabBarView.body**

Replace lines 124–127 with:

```swift
tabButton(.claude,   icon: .asset("claude"),   label: "Claude")
tabButton(.copilot,  icon: .asset("copilot"),  label: "Copilot")
Spacer()
tabButton(.settings, icon: .system("gear"),     label: nil)
```

---

### Task 6: Build and verify

**Step 1: Build the project**

```bash
cd AIMeter
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

**Step 2: Visual check**

Run the app and verify:
- Claude tab shows the orange robot icon (not sparkles)
- Copilot tab shows the pilot helmet icon (not airplane)
- Both icons tint white when selected, secondary gray when not
- Settings gear is unchanged

---

### Task 7: Commit

```bash
git add AIMeter/Resources/Assets.xcassets/claude.imageset/ \
        AIMeter/Resources/Assets.xcassets/copilot.imageset/ \
        AIMeter/Sources/App/PopoverView.swift \
        docs/plans/2026-02-27-brand-icons-design.md \
        docs/plans/2026-02-27-brand-icons-implementation.md
git commit -m "feat: replace SF Symbol tab icons with real Claude and Copilot brand icons"
```
