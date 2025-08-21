<img width="251" height="74" alt="image" src="https://github.com/user-attachments/assets/6291b77b-0a49-4a73-8d5b-8466e0723c5d" />





✨ Features

Multi-Weapon Support: Track main-hand, off-hand, and ranged weapons simultaneously
Real-Time Updates: Precise timing based on combat log events and weapon speeds
Dual-Wield Detection: Intelligent alternating swing detection for dual-wielding classes
Auto-Shot Integration: Automatic ranged weapon tracking for hunters and other ranged classes
Fully Customizable: Extensive configuration options via slash commands
Combat Awareness: Shows/hides based on combat state and user preferences
Movable Interface: Drag and drop positioning with lock/unlock functionality
Backwards Compatible: Works seamlessly with 3.3.5a client limitations

📦 Installation

Download the addon files
Extract to your World of Warcraft/Interface/AddOns/ directory
The folder structure should be: AddOns/TacoRotSwingTimer/
Restart World of Warcraft or reload your UI (/reload)
Type /st or /swingtimer to see available commands

🎮 Usage
Basic Commands
/st                    - Show help and available commands
/st lock               - Lock the timer bars in place
/st unlock             - Unlock to allow repositioning
/st reset              - Reset position to center of screen
Appearance Customization
/st scale <0.5-3.0>    - Set UI scale (default: 1.0)
/st alpha <0.2-1.0>    - Set transparency (default: 1.0)
/st width <120-600>    - Set bar width in pixels (default: 260)
/st height <8-40>      - Set bar height in pixels (default: 14)
Visibility Options
/st show               - Show timers even when out of combat
/st hide               - Hide timers when out of combat
/st togglemelee        - Toggle main-hand timer visibility
/st toggleoffhand      - Toggle off-hand timer visibility
/st toggleranged       - Toggle ranged timer visibility
⚙️ Configuration
All settings are automatically saved to your character and persist between sessions. The addon stores configuration in the SwingTimerDB saved variable.
Default Settings

Position: Center of screen, below character
Scale: 100% (1.0)
Alpha: 100% (1.0)
Dimensions: 260x14 pixels per bar
Visibility: Show all weapon types, hide when out of combat

🔧 Technical Details
File Structure
TacoRotSwingTimer/
├── TacoRotSwingTimer.toc    # Addon metadata
├── SwingTimer.xml           # Script loading order
├── Compat-335.lua           # Compatibility layer for 3.3.5a
├── core.lua                 # Main logic and event handling
└── ui.lua                   # User interface and visual updates
Key Features
Compatibility Layer
The addon includes a compatibility layer (Compat-335.lua) that handles API differences between retail and 3.3.5a:

SetColorTexture replacement using SetTexture + SetVertexColor
Backdrop application with proper insets and styling

Smart Swing Detection

Uses COMBAT_LOG_EVENT_UNFILTERED for precise swing timing
Handles dual-wield alternating swings intelligently
Automatically detects weapon speed changes from gear/buffs
Proportionally adjusts remaining swing time on speed changes

Performance Optimized

Efficient OnUpdate handling with minimal CPU usage
Conditional visibility updates
Smart event registration and handling

🎯 Supported Classes & Weapons
Melee Weapons

Warriors: All weapon combinations
Rogues: Dual-wield and single weapon support
Death Knights: Two-hand and dual-wield configurations
Paladins, Shamans: Enhancement and retribution builds

Ranged Weapons

Hunters: Auto Shot tracking with proper timing
Warriors, Rogues: Thrown weapons and crossbows
Any class: Wands, bows, guns, crossbows

🐛 Known Limitations

Swing timer reset on target switching may have slight delays
Very fast attack speeds (<0.5s) may have minor visual artifacts
Some weapon speed buffs may not be immediately detected

🔄 Changelog
Version 1.0.0

Initial release
Full swing timer functionality for all weapon types
Comprehensive slash command interface
Drag-and-drop positioning
Combat state awareness
Saved configuration system

🤝 Contributing
Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.
Development Setup

Clone the repository
Symlink to your AddOns directory for testing
Use /reload for rapid iteration
Test with various class/weapon combinations

Code Style

Use 4-space indentation
Follow existing naming conventions
Add comments for complex logic
Test on multiple classes/specs

📄 License
This project is licensed under the MIT License - see the LICENSE file for details.
🙏 Acknowledgments

Inspired by classic swing timer addons
Built for the 3.3.5a WoW community
Thanks to all testers and contributors

📞 Support
For issues, suggestions, or questions:

Create an issue on the project repository
Contact the author: Steven
Community forums and Discord servers
