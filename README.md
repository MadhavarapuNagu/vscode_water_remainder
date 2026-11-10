# Water Drinking Reminder

Periodic reminders to drink water, with a daily glass counter in the status bar.

## Features
- Reminder notification every N minutes with "Drank Water!" / "Remind Me Later"
- Working snooze timer
- Daily glass counter and goal (resets each day); click the status bar item to log a glass
- Optional animated status bar

## Commands
Start, Stop, I Drank a Glass, Snooze, Reset Today's Count (Command Palette: "Water Reminder").

## Settings
`waterReminder.interval`, `message`, `enabled`, `animation`, `dailyGoal`, `snoozeMinutes`.

## Run it
Open this folder in VS Code and press F5 to launch an Extension Development Host.

## Package, install and uninstall
Package the extension:
```bash
npx @vscode/vsce package --allow-missing-repository
```

Install the packaged extension:
```bash
code --install-extension "$PWD/water-drinking-reminder-1.0.0.vsix" --force
```

Uninstall it:
```bash
code --uninstall-extension local.water-drinking-reminder
```
