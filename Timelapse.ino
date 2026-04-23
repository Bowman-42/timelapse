#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include "SD_MMC.h"
#include <time.h>
#include "config.h"

// Camera pins — ESP32-S3 Eye
#define PWDN_GPIO_NUM  -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM  15
#define SIOD_GPIO_NUM   4
#define SIOC_GPIO_NUM   5
#define Y2_GPIO_NUM    11
#define Y3_GPIO_NUM     9
#define Y4_GPIO_NUM     8
#define Y5_GPIO_NUM    10
#define Y6_GPIO_NUM    12
#define Y7_GPIO_NUM    18
#define Y8_GPIO_NUM    17
#define Y9_GPIO_NUM    16
#define VSYNC_GPIO_NUM  6
#define HREF_GPIO_NUM   7
#define PCLK_GPIO_NUM  13

// SD card pins — ESP32-S3 Eye, 1-bit mode
#define SD_MMC_CMD 38
#define SD_MMC_CLK 39
#define SD_MMC_D0  40

unsigned long lastCaptureMs = 0;

// Forward declarations
void connectWiFi();
void syncNTP();
bool initCamera();
bool initSD();
void captureAndProcess();
bool uploadFile(const char* filepath, const char* folder, const char* filename);
void retryPending();
void getTimeStrings(char* folder, size_t folderLen, char* filename, size_t filenameLen);

// =============================================================================
// Setup
// =============================================================================

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\nTimelapse starting...");

  if (!initCamera()) {
    Serial.println("Camera init failed — halting");
    while (true) delay(1000);
  }

  if (!initSD()) {
    Serial.println("SD init failed — halting");
    while (true) delay(1000);
  }

  connectWiFi();
  syncNTP();

  Serial.println("Setup complete — first capture in a moment");
}

// =============================================================================
// Loop
// =============================================================================

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost, reconnecting...");
    connectWiFi();
  }

  unsigned long now = millis();
  if (now - lastCaptureMs >= CAPTURE_INTERVAL_MS) {
    lastCaptureMs = now;
    captureAndProcess();
    retryPending();
  }

  delay(100);
}

// =============================================================================
// WiFi
// =============================================================================

void connectWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.printf("Connecting to %s", WIFI_SSID);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\nWiFi connected: %s\n", WiFi.localIP().toString().c_str());
}

// =============================================================================
// NTP — UTC, no DST
// =============================================================================

void syncNTP() {
  configTime(0, 0, "pool.ntp.org");
  Serial.print("Waiting for NTP sync");
  struct tm timeinfo;
  while (!getLocalTime(&timeinfo)) {
    Serial.print(".");
    delay(1000);
  }
  char buf[30];
  strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S UTC", &timeinfo);
  Serial.printf("\nNTP synced: %s\n", buf);
}

// =============================================================================
// Camera
// =============================================================================

bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0       = Y2_GPIO_NUM;
  config.pin_d1       = Y3_GPIO_NUM;
  config.pin_d2       = Y4_GPIO_NUM;
  config.pin_d3       = Y5_GPIO_NUM;
  config.pin_d4       = Y6_GPIO_NUM;
  config.pin_d5       = Y7_GPIO_NUM;
  config.pin_d6       = Y8_GPIO_NUM;
  config.pin_d7       = Y9_GPIO_NUM;
  config.pin_xclk     = XCLK_GPIO_NUM;
  config.pin_pclk     = PCLK_GPIO_NUM;
  config.pin_vsync    = VSYNC_GPIO_NUM;
  config.pin_href     = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn     = PWDN_GPIO_NUM;
  config.pin_reset    = RESET_GPIO_NUM;
  config.xclk_freq_hz = CAM_XCLK_FREQ;
  config.frame_size   = CAM_FRAMESIZE;
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode    = CAMERA_GRAB_LATEST;
  config.fb_location  = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = CAM_JPEG_QUALITY;
  config.fb_count     = 2;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", err);
    return false;
  }

  sensor_t *s = esp_camera_sensor_get();
  s->set_vflip(s, 1);

  Serial.println("Camera initialised (VGA, JPEG)");
  return true;
}

// =============================================================================
// SD card — 1-bit SD_MMC
// =============================================================================

bool initSD() {
  SD_MMC.setPins(SD_MMC_CLK, SD_MMC_CMD, SD_MMC_D0);
  if (!SD_MMC.begin("/sdcard", true)) {  // true = 1-bit mode
    Serial.println("SD_MMC mount failed");
    return false;
  }
  uint64_t mb = SD_MMC.totalBytes() / (1024 * 1024);
  Serial.printf("SD ready: %llu MB total\n", mb);
  return true;
}

// =============================================================================
// Time helpers
// =============================================================================

// folder   → "2026-04-23"        (needs 11 bytes)
// filename → "2026-04-23_18-23.jpg" (needs 21 bytes)
void getTimeStrings(char* folder, size_t folderLen, char* filename, size_t filenameLen) {
  struct tm timeinfo;
  getLocalTime(&timeinfo);
  strftime(folder,   folderLen,   "%Y-%m-%d",          &timeinfo);
  strftime(filename, filenameLen, "%Y-%m-%d_%H-%M.jpg", &timeinfo);
}

// =============================================================================
// Capture and save
// =============================================================================

void captureAndProcess() {
  char folder[11];
  char filename[21];
  getTimeStrings(folder, sizeof(folder), filename, sizeof(filename));

  Serial.printf("Capturing %s\n", filename);

  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Capture failed — skipping");
    return;
  }

  // Create date directory if needed
  char dirPath[13];
  snprintf(dirPath, sizeof(dirPath), "/%s", folder);
  if (!SD_MMC.exists(dirPath)) {
    SD_MMC.mkdir(dirPath);
  }

  // Save to SD
  char filepath[40];
  snprintf(filepath, sizeof(filepath), "/%s/%s", folder, filename);

  File f = SD_MMC.open(filepath, FILE_WRITE);
  if (f) {
    f.write(fb->buf, fb->len);
    f.close();
    Serial.printf("Saved: %s (%d bytes)\n", filepath, fb->len);
  } else {
    Serial.printf("SD write failed: %s\n", filepath);
    esp_camera_fb_return(fb);
    return;
  }

  esp_camera_fb_return(fb);

  // Attempt immediate upload — delete from SD on success
  if (WiFi.status() == WL_CONNECTED) {
    if (uploadFile(filepath, folder, filename)) {
      SD_MMC.remove(filepath);
    }
  } else {
    Serial.println("WiFi down — image queued on SD");
  }
}

// =============================================================================
// HTTP upload
// Headers: X-Folder, X-Filename — Pi reconstructs the path from these
// =============================================================================

bool uploadFile(const char* filepath, const char* folder, const char* filename) {
  File f = SD_MMC.open(filepath);
  if (!f) {
    Serial.printf("Cannot open for upload: %s\n", filepath);
    return false;
  }
  size_t fileSize = f.size();

  char url[50];
  snprintf(url, sizeof(url), "http://%s:%d/upload", SERVER_IP, SERVER_PORT);

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "image/jpeg");
  http.addHeader("X-Folder",   folder);
  http.addHeader("X-Filename", filename);

  int code = http.sendRequest("POST", &f, fileSize);
  f.close();
  http.end();

  if (code == 200) {
    Serial.printf("Uploaded: %s\n", filename);
    return true;
  }

  Serial.printf("Upload failed: %s — HTTP %d\n", filename, code);
  return false;
}

// =============================================================================
// Retry pending files on SD
// Scans all date folders and uploads any .jpg not yet transferred.
// Stops immediately if upload fails (WiFi likely down) or if the next
// capture is due so we never miss a frame during a long retry run.
// =============================================================================

void retryPending() {
  if (WiFi.status() != WL_CONNECTED) return;

  File root = SD_MMC.open("/");
  if (!root) return;

  while (true) {
    // Abort if capture is due
    if (millis() - lastCaptureMs >= CAPTURE_INTERVAL_MS) {
      root.close();
      return;
    }

    File dateDir = root.openNextFile();
    if (!dateDir) break;  // no more entries

    if (!dateDir.isDirectory()) {
      dateDir.close();
      continue;
    }

    String dirPath    = String(dateDir.path());
    String folderName = String(dateDir.name());
    dateDir.close();

    File dir = SD_MMC.open(dirPath);
    if (!dir) continue;

    while (true) {
      // Abort if capture is due
      if (millis() - lastCaptureMs >= CAPTURE_INTERVAL_MS) {
        dir.close();
        root.close();
        return;
      }

      File img = dir.openNextFile();
      if (!img) break;  // no more files in this folder

      String imgPath = String(img.path());
      String imgName = String(img.name());
      img.close();

      if (!imgName.endsWith(".jpg")) continue;

      Serial.printf("Retrying: %s\n", imgName.c_str());

      if (!uploadFile(imgPath.c_str(), folderName.c_str(), imgName.c_str())) {
        // Upload failed — stop retrying until next cycle
        dir.close();
        root.close();
        return;
      }

      SD_MMC.remove(imgPath);
    }

    dir.close();
  }

  root.close();
}
