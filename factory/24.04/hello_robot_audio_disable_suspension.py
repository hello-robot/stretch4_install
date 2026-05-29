#!/usr/bin/env python3
import os
import pathlib
import subprocess


def disable_audio_suspension():
    """
    Fixes the issue where the first audio playback after a period of inactivity is quiet, while subsequent plays are loud. 
    This is likely due to audio device power management (USB autosuspend or PulseAudio module-suspend-on-idle).
    Generates the WirePlumber suspension config to disable idle timeout 
    for the specific USB audio device and restarts WirePlumber.
    """
    print("Configuring WirePlumber to disable audio suspension...")

    # Define the config directory and file path for WirePlumber 0.4 (Lua)
    # Using main.lua.d to ensure it loads with the main configuration
    config_dir = pathlib.Path(os.path.expanduser("~/.config/wireplumber/main.lua.d"))
    config_file = config_dir / "51-disable-suspension.lua"

    # Minimal Lua configuration to disable suspension for the specific device
    lua_config = """
-- Disable suspension for the Robot's USB Speaker Phone (Anhui LISTENAI)
-- This prevents the initial quiet audio issue when playing sounds after idle.

rule = {
  matches = {
    {
      { "node.name", "matches", "alsa_output.usb-Anhui_LISTENAI_CO._LTD._USB_Speaker_Phone-*" },
    },
  },
  apply_properties = {
    ["session.suspend-timeout-seconds"] = 0,
  },
}

-- Ensure alsa_monitor is available or check where to insert
if alsa_monitor and alsa_monitor.rules then
    table.insert(alsa_monitor.rules, rule)
else
    -- Fallback/Log if alsa_monitor isn't loaded (though it should be in main.lua context)
    print("Warning: alsa_monitor not found in global scope")
end
"""

    try:
        # 1. Create directory if it doesn't exist
        #print(f"Creating directory: {config_dir}")
        config_dir.mkdir(parents=True, exist_ok=True)

        # 2. Write the configuration file
        #print(f"Writing config to: {config_file}")
        with open(config_file, "w") as f:
            f.write(lua_config)
        
        #print("Configuration file written successfully.")

        # 3. Restart WirePlumber service
        #print("Restarting wireplumber.service...")
        #subprocess.run(["systemctl", "--user", "restart", "wireplumber"], check=True)
        #print("WirePlumber restarted successfully.")
        print("Audio suspension disabled. Restart wireplumber for change to take effect.")
    except OSError as e:
        #print(f"Error creating config file: {e}", file=sys.stderr)
        return False
    except subprocess.CalledProcessError as e:
        #print(f"Error restarting WirePlumber: {e}", file=sys.stderr)
        return False

    return True

if __name__ == "__main__":
  disable_audio_suspension()
  