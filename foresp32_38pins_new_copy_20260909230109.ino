/*
 * ==========================================================
 * VAULT OS - ESP32 COIN NODE (SH1106 + RAW PULSE EDITION) 
 * ==========================================================
 * VERSION: 9.8 (TRUE PULSE COUNTING + RECOVERY SYNC)
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <Preferences.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h> 

// ==========================================
//  SH1106 OLED DISPLAY SETUP
// ==========================================
#define i2c_Address 0x3c 
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1    

// 🔥 Custom I2C Pins! 🔥
#define I2C_SDA 33
#define I2C_SCL 32

Adafruit_SH1106G display = Adafruit_SH1106G(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

int currentSessionCoins = 0;

//  ANIMATION STATE MACHINE 
enum DispState { BOOTING, CONNECTED, SLEEP, READY, COIN, CANCELED, SUCCESS, OFFLINE_MODE };
DispState currentDispState = BOOTING;
unsigned long lastAnimTime = 0;
unsigned long stateEnterTime = 0;
int animFrame = 0;

// ==========================================
//  GLOBALS & STORAGE
// ==========================================
WebServer server(80);
Preferences prefs;

String currentSSID = "";
String currentWIFIPass = "";
String vaultToken = "";
String adminPass = "";
String serverIP = ""; 

bool isAPMode = false; 
bool isServerOnline = true; 
unsigned long lastPingTime = 0;

// Function Prototypes
void transmitToVault(int amount);
void registerWithUbuntu();
void changeDispState(DispState newState);
void renderDisplay();
void updateLEDs();

// ==========================================
//  TEXT ALIGNMENT HELPERS
// ==========================================
void centerText(String text, int y, int size) {
  display.setTextSize(size);
  int16_t x1, y1;
  uint16_t w, h;
  display.getTextBounds(text, 0, 0, &x1, &y1, &w, &h);
  int x = (SCREEN_WIDTH - w) / 2;
  display.setCursor(x, y);
  display.print(text);
}

void leftText(String text, int y, int size) {
  display.setTextSize(size);
  display.setCursor(0, y);
  display.print(text);
}

void rightText(String text, int y, int size) {
  display.setTextSize(size);
  int16_t x1, y1;
  uint16_t w, h;
  display.getTextBounds(text, 0, 0, &x1, &y1, &w, &h);
  int x = SCREEN_WIDTH - w;
  display.setCursor(x, y);
  display.print(text);
}

// ==========================================
//  HARDWARE PINOUTS & TIMERS
// ==========================================
const int coinPin = 13;      
const int relayPin = 12;     
const int statusLedPin = 18; // 🔥 SINGLE STATUS LED 🔥

volatile int pulseCount = 0;
volatile unsigned long lastPulseTime = 0;
int coinsToProcess = 0;

// 🔥 Optimized for fast drop speeds!
const unsigned long debounceDelay = 30;  
const unsigned long batchDelay = 400;    

bool insertMode = false;
unsigned long lastBlinkTime = 0;
bool ledState = false; 

unsigned long sessionExpireTime = 0; 
const unsigned long maxSessionLength = 30000; 

void IRAM_ATTR coinInterrupt() {
  unsigned long currentTime = millis();
  if (currentTime - lastPulseTime > debounceDelay) {
    pulseCount++;
    lastPulseTime = currentTime;
  }
}

// ==========================================
//  HTML/JS/CSS PAYLOADS 
// ==========================================
const char* loginHTML = R"rawliteral(
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { background: #03060c; color: #00f3ff; font-family: 'Courier New', monospace; text-align: center; margin-top: 10vh; }
  .box { border: 2px solid #00f3ff; padding: 30px; display: inline-block; background: rgba(0,243,255,0.05); box-shadow: 0 0 20px #00f3ff; border-radius: 8px; width: 80%; max-width: 350px;}
  input[type='password'] { width: 90%; padding: 12px; margin: 20px 0; background: #000; color: #fff; border: 1px solid #00f3ff; text-align: center; font-size: 18px; letter-spacing: 2px; }
  button { background: #00f3ff; color: #000; font-weight: bold; font-size: 16px; padding: 12px 25px; border: none; cursor: pointer; box-shadow: 0 0 10px #00f3ff; width: 100%; transition: 0.2s; }
  button:active { transform: scale(0.95); }
</style></head><body>
  <div class="box">
    <h2>🛡️ VAULT OS</h2>
    <p style="color:#888;">AUTHORIZED PERSONNEL ONLY</p>
    <form action="/login" method="POST">
      <input type="password" name="pwd" placeholder="Enter Access Code" required autofocus>
      <button type="submit">ACCESS NODE</button>
    </form>
  </div>
</body></html>
)rawliteral";

const char* dashboardHTMLPart1 = R"rawliteral(
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { background: #03060c; color: #fff; font-family: 'Courier New', monospace; padding: 20px; max-width: 500px; margin: auto; }
  .card { border: 1px solid #00f3ff; padding: 20px; margin-bottom: 20px; background: rgba(0,243,255,0.05); border-radius: 5px; }
  h2 { color: #00f3ff; margin-top: 0; text-align: center; letter-spacing: 1px; }
  label { font-size: 12px; color: #888; display: block; margin-bottom: 5px; margin-top: 15px;}
  input, select { width: 100%; padding: 10px; background: #000; color: #00f3ff; border: 1px solid #555; box-sizing: border-box; font-family: monospace; font-size: 14px;}
  button { width: 100%; background: #00f3ff; color: #000; font-weight: bold; padding: 12px; border: none; margin-top: 20px; cursor: pointer; }
  .btn-scan { background: #10b981; margin-top: 5px; padding: 8px; font-size: 12px; }
  .btn-logout { background: #ff2a2a; color: #fff; box-shadow: 0 0 10px #ff2a2a; margin-top: 10px; }
</style>
<script>
  function scanWifi() {
    document.getElementById('scanBtn').innerText = "Scanning...";
    fetch('/scan').then(r=>r.text()).then(html=>{
      if(html.trim() != "") document.getElementById('ssidSelect').outerHTML = "<select id='ssidSelect' name='ssid'>" + html + "</select>";
      document.getElementById('scanBtn').innerText = "Scan Networks";
    });
  }
</script>
</head><body>
  <h2>⚙️ SYSTEM CONFIG</h2>
  <form action="/save" method="POST">
    <div class="card"><h3 style="color:#10b981; margin:0;">1. NETWORK UPLINK</h3>
    <label>Select Network</label><input type="text" id="ssidSelect" name="ssid" value=")rawliteral";

// ==========================================
//  🔥 CUSTOM LED CONTROLLER 🔥
// ==========================================
void updateLEDs() {
  unsigned long currentTime = millis();
  
  if (currentDispState == BOOTING || currentDispState == OFFLINE_MODE) {
    // 🔴 Offline / Booting = Slow Blink
    if (currentTime - lastBlinkTime > 500) {
      ledState = !ledState;
      digitalWrite(statusLedPin, ledState ? HIGH : LOW);
      lastBlinkTime = currentTime;
    }
  } 
  else if (currentDispState == READY) {
    // 🟢 Waiting for Coins = Fast Blink
    if (currentTime - lastBlinkTime > 150) {
      ledState = !ledState;
      digitalWrite(statusLedPin, ledState ? HIGH : LOW);
      lastBlinkTime = currentTime;
    }
  } 
  else {
    // 🟢 Sleep, Connected, Coin Accepted = Solid ON
    digitalWrite(statusLedPin, HIGH);
  }
}

// ==========================================
//  ANIMATION ENGINE 
// ==========================================
void changeDispState(DispState newState) {
  currentDispState = newState;
  stateEnterTime = millis();
  animFrame = 0;
  renderDisplay();
  updateLEDs(); 
}

void renderDisplay() {
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);
  
  if (currentDispState == BOOTING) {
    centerText("VAULT OS", 0, 2); 
    if (animFrame % 2 == 0) { centerText("Connecting...", 20, 1); } 
    else { centerText("Connecting..", 20, 1); }
    centerText("(^.^)", 35, 3); 
  } 
  else if (currentDispState == CONNECTED) {
    centerText("CONNECTED!", 0, 2);
    if (animFrame < 2) { centerText("\\(O)/", 25, 3); } 
    else { centerText("()", 25, 3); }
  }
  else if (currentDispState == SLEEP) {
    centerText("STANDBY", 0, 2);
    if (animFrame % 2 == 0) { centerText("()", 25, 3); } 
    else { centerText("(_)", 25, 3); }
  } 
  else if (currentDispState == OFFLINE_MODE) {
    centerText("OFFLINE", 0, 2);
    if (animFrame % 2 == 0) { centerText("(-_-) zZ", 25, 2); } 
    else { centerText("(-_-) z", 25, 2); }
    centerText("SYSTEM DOWN", 50, 1);
  }
  else if (currentDispState == READY) {
    centerText("DROP COIN", 0, 2); 
    if (animFrame % 2 == 0) { leftText("(^O^)", 25, 2); } 
    else { leftText("(^o^)", 25, 2); }
    
    int timeLeft = 0;
    if (insertMode) { 
        timeLeft = (sessionExpireTime - millis()) / 1000; 
        if (timeLeft < 0) timeLeft = 0; 
    }
    rightText(String(timeLeft) + "s", 25, 2);
    centerText("COIN:P " + String(currentSessionCoins), 50, 2);
  }
  else if (currentDispState == COIN) {
    if (animFrame % 2 == 0) { centerText("ACCEPTED!", 0, 2); } 
    else { centerText("COIN", 0, 2); }
    leftText("(P_P)", 25, 2);
    int timeLeft = 0;
    if (insertMode) { 
        timeLeft = (sessionExpireTime - millis()) / 1000; 
        if (timeLeft < 0) timeLeft = 0; 
    }
    rightText(String(timeLeft) + "s", 25, 2);
    centerText("COIN:P " + String(currentSessionCoins), 50, 2);
  }
  else if (currentDispState == CANCELED) {
    centerText("CANCELED!", 0, 2);
    if (animFrame % 2 == 0) { centerText("()", 25, 3); } 
    else { centerText("(;_;)", 25, 3); }
  }
  else if (currentDispState == SUCCESS) {
    centerText("THANK YOU!", 0, 2);
    if (animFrame % 2 == 0) { centerText("\\(^o^)/", 25, 3); } 
    else { centerText(" \\(^O^)/ ", 25, 3); }
  }

  display.display();
}

// ==========================================
//  WEB UI HANDLERS
// ==========================================
bool isAuthenticated() {
  if (server.hasHeader("Cookie")) {
    if (server.header("Cookie").indexOf("auth=granted") != -1) return true;
  }
  return false;
}

void handleRoot() {
  if (isAuthenticated()) {
    String page = String(dashboardHTMLPart1) + currentSSID + R"rawliteral(">
      <button type="button" id="scanBtn" class="btn-scan" onclick="scanWifi()">Scan Networks</button>
      <label>WiFi Password</label><input type="text" name="wifi_pass" value=")rawliteral" + currentWIFIPass + R"rawliteral(">
      </div>
      
      <div class="card"><h3 style="color:#b026ff; margin:0;">2. SERVER SETTINGS</h3>
      <label>Ubuntu Server IP (e.g. 192.168.1.11)</label><input type="text" name="server_ip" value=")rawliteral" + serverIP + R"rawliteral(">
      <label>Vault API Master Key</label><input type="text" name="token" value=")rawliteral" + vaultToken + R"rawliteral(">
      <label>Dashboard Login Password</label><input type="text" name="admin_pwd" value=")rawliteral" + adminPass + R"rawliteral(">
      </div>
      
      <button type="submit">SAVE & REBOOT</button></form>
      <button type="button" class="btn-logout" onclick="window.location.href='/logout'">LOGOUT</button>
      <br><br></body></html>)rawliteral";
    server.send(200, "text/html", page);
  } else {
    server.send(200, "text/html", loginHTML);
  }
}

void handleLogin() {
  if (server.hasArg("pwd") && server.arg("pwd") == adminPass) {
    server.sendHeader("Set-Cookie", "auth=granted; Path=/; Max-Age=86400");
    server.sendHeader("Location", "/"); 
    server.send(303);
  } else {
    server.send(401, "text/html", "<h2>❌ ACCESS DENIED</h2><script>setTimeout(()=>window.location.href='/', 2000);</script>");
  }
}

void handleLogout() { 
    server.sendHeader("Set-Cookie", "auth=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT"); 
    server.sendHeader("Location", "/"); 
    server.send(303); 
}

void handleScan() {
  if (!isAuthenticated()) return server.send(401, "text/plain", "");
  int n = WiFi.scanNetworks(); 
  String o = "";
  for (int i=0; i<n; ++i) {
      o += "<option value='" + WiFi.SSID(i) + "'>" + WiFi.SSID(i) + " (" + String(WiFi.RSSI(i)) + "dBm)</option>";
  }
  server.send(200, "text/plain", o);
}

void handleSave() {
  if (!isAuthenticated()) return server.send(401, "text/plain", "");
  
  prefs.putString("ssid", server.arg("ssid")); 
  prefs.putString("wifi_pass", server.arg("wifi_pass"));
  prefs.putString("token", server.arg("token")); 
  prefs.putString("admin_pass", server.arg("admin_pwd"));
  prefs.putString("server_ip", server.arg("server_ip")); 
  
  server.send(200, "text/html", "<h2 style='color:#10b981; text-align:center; padding:50px;'>💾 SAVED! REBOOTING...</h2>");
  delay(2000); 
  ESP.restart();
}

void handleOpenGate() {
  if (server.arg("token") != vaultToken || !isServerOnline) {
      return server.send(401, "application/json", "{\"status\":\"error\"}");
  }
  
  insertMode = true;
  digitalWrite(relayPin, HIGH); 
  sessionExpireTime = millis() + maxSessionLength; 
  
  if (server.hasArg("coins")) {
    currentSessionCoins = server.arg("coins").toInt();
  } else {
    currentSessionCoins = 0;
  }
  changeDispState(READY); 
  server.send(200, "application/json", "{\"status\":\"success\"}");
}

void handleCloseGate() {
  if (server.arg("token") != vaultToken) {
      return server.send(401, "application/json", "{\"status\":\"error\"}");
  }
  
  insertMode = false;
  digitalWrite(relayPin, LOW); 
  
  if (currentSessionCoins > 0) { changeDispState(SUCCESS); } 
  else { changeDispState(CANCELED); }
  
  server.send(200, "application/json", "{\"status\":\"success\"}");
}

void handlePing() { 
    server.send(200, "application/json", "{\"status\":\"ONLINE\"}"); 
}

// ==========================================
//  TRANSMIT DATA & REGISTRATION
// ==========================================
void transmitToVault(int amount) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin("http://" + serverIP + "/portal/slot_api.php");
    http.addHeader("Content-Type", "application/x-www-form-urlencoded");
    http.POST("action=insert_coin_api&coins=" + String(amount) + "&token=" + vaultToken);
    http.end();
  }
}

void registerWithUbuntu() {
  if(WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin("http://" + serverIP + "/register_esp.php?token=" + vaultToken);
    http.GET(); 
    http.end();
  }
}

// ==========================================
//  SETUP
// ==========================================
void setup() {
  Serial.begin(115200);
  
  pinMode(statusLedPin, OUTPUT);
  digitalWrite(statusLedPin, LOW);
  
  delay(250); 
  Wire.begin(I2C_SDA, I2C_SCL); 
  display.begin(i2c_Address, true);
  
  display.clearDisplay(); 
  display.display();
  
  changeDispState(BOOTING);
  
  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, LOW); 
  
  pinMode(coinPin, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(coinPin), coinInterrupt, FALLING);

  prefs.begin("vault", false);
  currentSSID = prefs.getString("ssid", "HAHAHA"); 
  currentWIFIPass = prefs.getString("wifi_pass", "10212002"); 
  vaultToken = prefs.getString("token", "111625080052"); 
  adminPass = prefs.getString("admin_pass", "Rj@10212002"); 
  serverIP = prefs.getString("server_ip", "192.168.1.11"); 

  WiFi.begin(currentSSID.c_str(), currentWIFIPass.c_str());
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500); 
    updateLEDs(); 
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    changeDispState(CONNECTED);
    registerWithUbuntu();
  } else {
    isAPMode = true;
    WiFi.mode(WIFI_AP);
    WiFi.softAP("VAULT_OS_SETUP", "Rj@10212002"); 
    changeDispState(SLEEP);
  }

  const char* headerkeys[] = {"Cookie"};
  server.collectHeaders(headerkeys, 1);
  
  server.on("/", HTTP_GET, handleRoot); 
  server.on("/login", HTTP_POST, handleLogin);
  server.on("/logout", HTTP_GET, handleLogout); 
  server.on("/scan", HTTP_GET, handleScan);
  server.on("/save", HTTP_POST, handleSave);
  server.on("/open", handleOpenGate); 
  server.on("/close", handleCloseGate);
  server.on("/ping", handlePing);
  
  server.begin();
}

// ==========================================
//  MAIN LOOP
// ==========================================
void loop() {
  server.handleClient(); 
  unsigned long currentTime = millis();
  
  updateLEDs(); 

  // 🔥 20-SECOND SERVER WATCHDOG 🔥
  if (currentTime - lastPingTime > 20000) {
    lastPingTime = currentTime;
    
    if (WiFi.status() == WL_CONNECTED && !isAPMode) {
      HTTPClient http;
      http.begin("http://" + serverIP + "/api_ping.php"); 
      http.setTimeout(1500); // 1.5s timeout so it doesn't freeze the coin slot!
      int httpCode = http.GET();
      http.end();
      
      if (httpCode > 0) { // Server is alive!
        if (!isServerOnline) {
          isServerOnline = true;
          // 🔥 RECOVERY SYNC: Flash CONNECTED when back online! 🔥
          changeDispState(CONNECTED); 
        }
      } else { // Server is dead/unreachable
        if (isServerOnline) {
          isServerOnline = false;
          insertMode = false;
          digitalWrite(relayPin, LOW); 
          changeDispState(OFFLINE_MODE); 
        }
      }
    } else { // WiFi disconnected
      if (isServerOnline && !isAPMode) {
        isServerOnline = false;
        insertMode = false;
        digitalWrite(relayPin, LOW); 
        changeDispState(OFFLINE_MODE);
      }
    }
  }

  // 📺 ANIMATION TICKER
  if (currentTime - lastAnimTime > 800) {
    animFrame++;
    lastAnimTime = currentTime;
    
    // Automatically fade back to SLEEP or READY from temporary screens
    if (currentDispState == CONNECTED && (currentTime - stateEnterTime > 3000)) { changeDispState(SLEEP); }
    if (currentDispState == COIN && (currentTime - stateEnterTime > 2000)) { changeDispState(READY); }
    if (currentDispState == CANCELED && (currentTime - stateEnterTime > 3000)) { changeDispState(SLEEP); }
    if (currentDispState == SUCCESS && (currentTime - stateEnterTime > 3000)) { changeDispState(SLEEP); }
    
    renderDisplay();
  }

  // ⏱️ TIMEOUT LOGIC 
  if (insertMode == true && currentTime > sessionExpireTime) {
    insertMode = false;
    digitalWrite(relayPin, LOW);
    
    if (currentSessionCoins > 0) { changeDispState(SUCCESS); } 
    else { changeDispState(CANCELED); }
  }

  // 🔥 TRUE RAW PULSE COIN PROCESSING 🔥
  if (pulseCount > 0 && (currentTime - lastPulseTime > batchDelay)) {
    detachInterrupt(digitalPinToInterrupt(coinPin));
    int rawPulses = pulseCount;
    pulseCount = 0; 
    attachInterrupt(digitalPinToInterrupt(coinPin), coinInterrupt, FALLING);

    // 1 PULSE = 1 PESO DIRECTLY! NO MORE MISSED COINS!
    if (rawPulses > 0) {
        currentSessionCoins += rawPulses;
        changeDispState(COIN); 
        sessionExpireTime = currentTime + maxSessionLength; 
        
        if (!isAPMode) { transmitToVault(rawPulses); }
    }
  }
}