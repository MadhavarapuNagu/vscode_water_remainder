const vscode = require("vscode");
const { showDesktopGirl } = require("./girlDesktop");

const IDLE_TEXT = "$(droplet) Water Reminder";
const STOPPED_TEXT = "$(circle-slash) Water Reminder Stopped";
const waterFrames = ["💧", "🥤", "💦", "🚰"];

let reminderTimer;
let snoozeTimer;
let animationTimer;
let statusBarItem;
let extContext;
let animationIndex = 0;
let nextReminderAt = 0;
let running = false;

function cfg() {
  return vscode.workspace.getConfiguration("waterReminder");
}

// ---------- daily glass tracking ----------

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function getGlasses() {
  const saved = extContext.globalState.get("waterReminder.daily");
  return saved && saved.date === todayKey() ? saved.count : 0;
}

async function setGlasses(count) {
  await extContext.globalState.update("waterReminder.daily", {
    date: todayKey(),
    count: Math.max(0, count),
  });
  refreshStatusBar();
}

// ---------- status bar ----------

function minutesLeft() {
  return Math.max(0, Math.ceil((nextReminderAt - Date.now()) / 60000));
}

function refreshStatusBar() {
  if (!statusBarItem) return;
  const goal = cfg().get("dailyGoal", 8);
  const glasses = getGlasses();
  const progress = `${glasses}/${goal} 🥛`;

  if (!running) {
    statusBarItem.text = `${STOPPED_TEXT} (${progress})`;
    statusBarItem.tooltip = "Click to start water reminders";
    statusBarItem.command = "waterReminder.start";
    return;
  }

  const frame = cfg().get("animation", true)
    ? waterFrames[animationIndex]
    : "$(droplet)";
  statusBarItem.text = `${frame} ${progress}`;
  statusBarItem.tooltip = `Next reminder in ~${minutesLeft()} min. Click to log a glass.`;
  statusBarItem.command = "waterReminder.drink";
}

// ---------- reminder logic ----------

function clearTimers() {
  if (reminderTimer) clearInterval(reminderTimer);
  if (snoozeTimer) clearTimeout(snoozeTimer);
  if (animationTimer) clearInterval(animationTimer);
  reminderTimer = snoozeTimer = animationTimer = undefined;
}

function startReminder() {
  clearTimers();
  running = true;

  const intervalMs = cfg().get("interval", 30) * 60 * 1000;
  nextReminderAt = Date.now() + intervalMs;

  reminderTimer = setInterval(() => {
    nextReminderAt = Date.now() + intervalMs;
    showReminder();
  }, intervalMs);

  // Animation frame / countdown refresh
  const animate = cfg().get("animation", true);
  animationTimer = setInterval(
    () => {
      if (animate) animationIndex = (animationIndex + 1) % waterFrames.length;
      refreshStatusBar();
    },
    animate ? 1000 : 30000
  );

  refreshStatusBar();
}

function stopReminder() {
  clearTimers();
  running = false;
  refreshStatusBar();
}

async function showReminder() {
  const message = cfg().get("message", "Time to drink water! Stay hydrated 💧");
  let selection;

  const style = cfg().get("style", "desktop");
  const notify = () =>
    vscode.window.showInformationMessage(
      `💧 ${message}`,
      "Drank Water!",
      "Remind Me Later"
    );

  if (style === "notification") {
    selection = await notify();
  } else {
    try {
      const result = await showDesktopGirl(message, cfg().get("imageFolder", ""));
      selection =
        result === "drank" ? "Drank Water!" :
        result === "later" ? "Remind Me Later" : undefined;
    } catch (e) {
      console.error("Desktop girl failed, using notification:", e);
      selection = await notify();
    }
  }

  if (selection === "Drank Water!") {
    await logGlass();
  } else if (selection === "Remind Me Later") {
    snooze();
  }
}

async function logGlass() {
  const glasses = getGlasses() + 1;
  await setGlasses(glasses);
  const goal = cfg().get("dailyGoal", 8);
  if (glasses === goal) {
    vscode.window.showInformationMessage(
      `🎉 Daily goal reached: ${glasses}/${goal} glasses! Great job!`
    );
  } else {
    vscode.window.showInformationMessage(
      `Nice! ${glasses}/${goal} glasses today. 💦`
    );
  }
}

function snooze() {
  const minutes = cfg().get("snoozeMinutes", 5);
  if (snoozeTimer) clearTimeout(snoozeTimer);
  snoozeTimer = setTimeout(() => {
    snoozeTimer = undefined;
    showReminder();
  }, minutes * 60 * 1000);
  vscode.window.showInformationMessage(
    `Okay, I'll remind you again in ${minutes} min.`
  );
}

// ---------- extension lifecycle ----------

function activate(context) {
  extContext = context;

  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    100
  );
  statusBarItem.text = IDLE_TEXT;
  statusBarItem.show();

  context.subscriptions.push(
    statusBarItem,

    vscode.commands.registerCommand("waterReminder.start", () => {
      startReminder();
      vscode.window.showInformationMessage("💧 Water reminders started!");
    }),

    vscode.commands.registerCommand("waterReminder.stop", () => {
      stopReminder();
      vscode.window.showInformationMessage("Water reminders stopped.");
    }),

    vscode.commands.registerCommand("waterReminder.drink", logGlass),

    vscode.commands.registerCommand("waterReminder.snooze", snooze),

    vscode.commands.registerCommand("waterReminder.showNow", showReminder),

    vscode.commands.registerCommand("waterReminder.resetToday", async () => {
      await setGlasses(0);
      vscode.window.showInformationMessage("Today's water count was reset.");
    }),

    vscode.workspace.onDidChangeConfiguration((event) => {
      if (!event.affectsConfiguration("waterReminder")) return;
      if (cfg().get("enabled", true)) {
        startReminder();
      } else {
        stopReminder();
      }
    }),

    { dispose: clearTimers }
  );

  if (cfg().get("enabled", true)) {
    startReminder();
  } else {
    refreshStatusBar();
  }
}

function deactivate() {
  clearTimers();
}

module.exports = { activate, deactivate };
