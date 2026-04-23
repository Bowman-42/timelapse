#ifndef CONFIG_H
#define CONFIG_H

// WiFi
#define WIFI_SSID     "your-ssid"
#define WIFI_PASSWORD "your-password"

// Pi server — set to your Raspberry Pi's reserved IP
#define SERVER_IP   "192.168.1.xxx"
#define SERVER_PORT 5000

// Capture
#define CAPTURE_INTERVAL_MS 60000UL   // 1 minute

// Camera
#define CAM_XCLK_FREQ   10000000
#define CAM_JPEG_QUALITY 10           // 0=best, 63=worst
#define CAM_FRAMESIZE   FRAMESIZE_XGA

#endif // CONFIG_H
