# GearLister

**A World of Warcraft Classic addon for sharing and comparing character gear with integrated Wowhead links.**

![Version](https://img.shields.io/badge/version-4.10.0-blue.svg)
![Game Version](https://img.shields.io/badge/wow%20classic-era-orange.svg)
![Interface](https://img.shields.io/badge/interface-11504-green.svg)

## 📖 Overview

GearLister is a comprehensive gear management addon for WoW Classic that allows you to:
- **View and share** your equipped gear in a clean, copyable format
- **Inspect other players** and save their gear loadouts
- **Compare gear sets** between different characters or time periods
- **Access Wowhead links** for every item for detailed information
- **Maintain gear history** to track equipment changes over time

## ✨ Features

### 🎯 Core Functionality
- **Instant gear display** with `/gear` command
- **Target inspection** - automatically inspects your target if in range
- **Visual and text modes** - view gear as icons or copyable text
- **Wowhead integration** - direct links to classic.wowhead.com for each item

### 📊 Advanced Features
- **Gear history tracking** - saves gear snapshots with timestamps
- **Comparison mode** - side-by-side gear comparison between characters
- **Visual comparison** - highlighted differences in icon view
- **Export functionality** - copyable text format for sharing
- **Customizable delimiters** - configure output format

### 🎨 User Interface
- **Modern AceGUI interface** with resizable windows
- **Escape key support** - close dialogs with Esc
- **Visual gear layout** - character sheet style icon display
- **Clean text output** - formatted for easy reading and sharing

## 🚀 Installation

### Automatic Installation (Recommended)
1. Download the latest release from [GitHub Releases](../../releases)
2. Extract the ZIP file to your WoW Classic addons directory:
   ```
   World of Warcraft/_classic_era_/Interface/AddOns/
   ```
3. Restart World of Warcraft Classic
4. Ensure GearLister is enabled in the AddOns menu

### Manual Installation
1. Clone or download this repository
2. Copy the `GearLister` folder to your addons directory
3. Make sure the folder structure looks like:
   ```
   AddOns/
   └── GearLister/
       ├── GearLister.toc
       ├── GearLister.lua
       ├── Libs/
       └── README.md
   ```

## 🎮 Usage

### Basic Commands
- **`/gear`** - Show your equipped gear (or inspect target if selected)
- **`/gearlist`** - Alternative command (same functionality)
- **`/gear inspect`** - Force inspect mode on your target

### Main Interface

#### Getting Started
1. Type `/gear` in chat to open the main window
2. Your current gear will be displayed and automatically saved to history
3. Select **Visual Mode** or **Text Mode** based on your preference

#### Inspecting Other Players
1. Target a player within inspect range
2. Type `/gear` - the addon will automatically inspect them
3. Their gear will be displayed and saved to your history

#### Using Gear History
- **View saved gear** - Click any entry in the history list
- **Delete entries** - Click the **×** button next to any history entry
- **Clear all history** - Use the "Clear History" button

#### Comparison Mode
1. Enable **Comparison Mode** checkbox
2. Click on two different history entries to select them
3. View side-by-side comparison in both visual and text modes
4. **Visual mode**: Matching items appear greyed out, different items highlighted
5. **Text mode**: Detailed comparison with color-coded differences

### Settings Window
Click the **Settings** button to configure:
- **Delimiter** - Text between item name and Wowhead link
- **Add newline** - Insert line break after delimiter
- **Max history entries** - Limit the number of saved gear sets

### Keyboard Shortcuts
- **Escape** - Close any GearLister window
- **Click gear icons** - View item tooltips in visual mode

## ⚙️ Configuration

### Settings Options
| Setting | Description | Default |
|---------|-------------|---------|
| Delimiter | Text between item and Wowhead link | ` - ` |
| Add newline | Line break after delimiter | `false` |
| Max history entries | Maximum saved gear sets | `50` |

### Output Format Examples

**Default format:**
```
Head: [Lionheart Helm] - https://classic.wowhead.com/item=12640
Neck: [Onyxia Tooth Pendant] - https://classic.wowhead.com/item=18205
```

**With newline enabled:**
```
Head: [Lionheart Helm] - 
https://classic.wowhead.com/item=12640
Neck: [Onyxia Tooth Pendant] - 
https://classic.wowhead.com/item=18205
```

## 🛠️ Technical Details

### Dependencies
- **Self-contained** - All required libraries included
- **No external dependencies** - Works independently
- **Ace3 framework** - Professional addon development framework

### Compatibility
- **WoW Classic Era** (Interface 11504)
- **All classes and races**
- **Compatible with other addons**

### Performance
- **Lightweight** - Minimal memory footprint
- **Efficient** - Smart caching and cleanup
- **Non-intrusive** - Doesn't interfere with gameplay

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

### Development Setup
1. Clone the repository
2. Make changes to the addon files
3. Test in WoW Classic
4. Submit a pull request

### Reporting Issues
When reporting bugs, please include:
- WoW Classic version
- Addon version
- Steps to reproduce
- Any error messages

## 📜 License

This project is open source. Feel free to modify and redistribute according to the license terms.

## 🙏 Credits

- **Author**: Bunnycrits
- **Framework**: Ace3 addon development framework
- **Community**: WoW Classic addon development community

## 📞 Support

- **Issues**: Report on [GitHub Issues](../../issues)
- **Questions**: Check existing issues or create a new one
- **Updates**: Watch this repository for new releases

---

**Made with ❤️ for the WoW Classic community**
