#ifndef CONFIG_H
#define CONFIG_H

// WiFi
#define WIFI_SSID     "your-ssid"
#define WIFI_PASSWORD "your-password"

// Pi server — set to your Raspberry Pi's reserved IP
#define SERVER_IP   "192.168.1.xxx"
#define SERVER_PORT 5000

// Capture
// Below 60000 (1 minute), filenames get second-resolution timestamps
// (HH-MM-SS.jpg) instead of the default HH-MM.jpg — see getTimeStrings()
// in Timelapse.ino. This keeps existing 1-min-or-slower cameras' output
// unchanged even if they're reflashed with this same sketch.
#define CAPTURE_INTERVAL_MS 60000UL   // 1 minute

// Camera
#define CAM_XCLK_FREQ   10000000
#define CAM_JPEG_QUALITY 10           // 0=best, 63=worst
#define CAM_FRAMESIZE   FRAMESIZE_XGA

#endif // CONFIG_H
