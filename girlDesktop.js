const path = require("path");
const { spawn, execFileSync } = require("child_process");

let running = false;

/** Convert the script path into something Windows PowerShell can open. */
function windowsScriptPath(script) {
  if (process.platform === "win32") return script;
  return execFileSync("wslpath", ["-w", script]).toString().trim();
}

/**
 * Starts the transparent desktop girl (Windows only, also works from WSL).
 * Resolves "drank" | "later" | undefined. Rejects if it can't be started,
 * so the caller can fall back to another reminder style.
 */
function showDesktopGirl(message, imageFolder) {
  if (running) return Promise.resolve(undefined);

  return new Promise((resolve, reject) => {
    let script;
    try {
      script = windowsScriptPath(path.join(__dirname, "girl.ps1"));
    } catch (e) {
      return reject(e);
    }

    let assets = "";
    try {
      assets = imageFolder || windowsScriptPath(path.join(__dirname, "assets"));
    } catch (e) {
      assets = "";
    }
    const env = { ...process.env, WATER_MSG: message, WATER_ASSETS: assets };
    if (process.platform !== "win32") {
      // pass the variable through WSL interop
      env.WSLENV = env.WSLENV ? `${env.WSLENV}:WATER_MSG:WATER_ASSETS` : "WATER_MSG:WATER_ASSETS";
    }

    let child;
    try {
      child = spawn(
        "powershell.exe",
        ["-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", script],
        { env, windowsHide: true, cwd: process.platform === "win32" ? undefined : "/mnt/c" }
      );
    } catch (e) {
      return reject(e);
    }

    running = true;
    let out = "";
    let err = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", (e) => {
      running = false;
      reject(e);
    });
    child.on("close", () => {
      running = false;
      const answer = out.trim().split(/\s+/).pop();
      if (answer === "drank" || answer === "later") resolve(answer);
      else if (answer === "dismissed") resolve(undefined);
      else reject(new Error(err || "Desktop girl exited unexpectedly"));
    });
  });
}

module.exports = { showDesktopGirl };
