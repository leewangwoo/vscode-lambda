Lambda Chat Extension - Installation Guide
============================================

Requirements:
- VS Code 1.115.0 or later
- GitHub Copilot Chat must be present (builtin or marketplace)

Installation:
1. Double-click "install.bat"
   Steps performed automatically:
   a) Install original Copilot Chat VSIX (trust setup)
   b) Disable builtin AI features (clears config cache)
   c) Install Lambda custom VSIX
   d) Enable AI features (loads Lambda configuration)

2. Start VS Code

3. Run: Developer: Reload Window (Ctrl+Shift+P)

4. Open the Chat panel from the sidebar

5. Verify: Settings (Ctrl+,) > search "customoai"

Configuration:
- Customoai: Url  → http://100.252.201.200:8088/v1 (pre-filled)
- Customoai: Key  → dummy-key (pre-filled)

Troubleshooting:
- If customoai settings don't appear after install:
  1. Extensions tab (Ctrl+Shift+X)
  2. Search: @builtin copilot-chat
  3. Disable → Reload Window (Ctrl+Shift+P)
  4. Enable → Reload Window
  5. Search "customoai" in settings

- Do NOT update "GitHub Copilot Chat" from the marketplace —
  it will overwrite the Lambda extension.

Notes:
- The extension works offline with your LiteLLM server.
- Ignore any "Sign in to GitHub" prompts.

Files:
- install.bat                  → Double-click to install
- copilot-chat-original.vsix   → Original Copilot Chat (trust setup)
- copilot-chat-999.0.0.vsix    → Lambda custom extension
