#include <LittleFS.h>
#include <FS.h>

#include <U8g2lib.h>
#include <Wire.h>

#include <FS.h>
#include <LittleFS.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

// Define custom I2C pins
#define SDA_PIN D6
#define SCL_PIN D5
#define I2C_ADDRESS 0x3C

// Define the GPIO pins used
#define serialOut D2
#define shiftClk D4
#define addrLatch D3
#define dataLatch D0 // Latches the write data register and sets shift/load for the read data register
#define writeDataOE D2 // Active LOW output enable of the data to be written to the rom
#define romWE D7
#define romOE D1

void initDisplay();
void showProgressOLED(const char*, uint32_t);
void initPins();
void shiftBit(bool);
void loadAddrReg(uint32_t);
void loadDataReg(uint8_t);
uint8_t loadReadData();
void writeByte(uint8_t, uint32_t);
uint8_t readByte(uint32_t);
void readAndSaveBytes(const char*);

// Initialize the U8g2 library
// U8G2_R0 specifies no rotation and U8X8_PIN_NONE specifies no reset pin
U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, /* clock=*/ SCL_PIN, /* data=*/ SDA_PIN);

// Create an instance of the server on port 80
ESP8266WebServer server(80);

// Specify ssid and password to connect to WiFi
//const char* ssid = "TheTent";
//const char* password = "Paul&Prue";
const char* ssid = "SkibidiPhone";
const char* password = "Marshmallow314";

//IPAddress ip(192, 168, 1, 184); // Desired IP address
//IPAddress gateway(192, 168, 1, 1); // Your router’s gateway address
//IPAddress subnet(255, 255, 255, 0); // Subnet mask

void setup() {

  Serial.begin(115200); // For debugging

  // Initialize the display and the GPIO pins
  //initDisplay();
  initPins();

  Serial.println();
  // Begin the reading process off of the memory chip
  readAndSaveBytes("/data.bin");

  // Init WiFi so data can be served
  initWiFi();
  // Update the display to show the Ip address obtained and show a message
  //showProgressOLED("Serving Data...", 0x1FFFF);

  digitalWrite(serialOut, LOW); // Turn off builtin LED once finished and data is being served
}

void loop() {
  // Handle client requests
  server.handleClient();
}

void initWiFi() {
  // Connect to WiFi
  WiFi.begin(ssid, password);
  //WiFi.config(ip, gateway, subnet);

  Serial.print("Connecting to WiFi");
  bool LED = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.print(".");
    LED *= -1;
    digitalWrite(serialOut, LED);
  }
  Serial.println();
  Serial.print("Connected to WiFi. IP address: ");
  Serial.println(WiFi.localIP());

  Serial.print("MAC address: ");
  Serial.println(WiFi.macAddress());

  // Define the routes
  server.on("/", HTTP_GET, handleRoot);
  server.on("/download", HTTP_GET, handleFileDownload);

  // Start the server
  server.begin();
  Serial.println("HTTP server started");
}

void initDisplay() {
  // Set the I2C address for the display
  u8g2.setI2CAddress(I2C_ADDRESS << 1);

  // Initialize the display
  u8g2.begin();

  // Clear the display
  u8g2.clearBuffer();

  // Set font and write text
  u8g2.setFont(u8g2_font_ncenB08_tr);
  u8g2.drawStr(0, 10, "Initializing...");

  // Send buffer to display
  u8g2.sendBuffer();
}

// Specify a message and the address of the byte being read
void showProgressOLED(const char* _message, uint32_t _addr) {
  
  // Set the I2C address for the display
  u8g2.setI2CAddress(I2C_ADDRESS << 1);

  // Initialize the display
  u8g2.begin();

  // Clear the display buffer
  u8g2.clearBuffer();

  // Set font and write the message
  u8g2.setFont(u8g2_font_ncenB08_tr);
  u8g2.drawStr(0, 10, _message);
  //u8g2.drawStr(0, 10, "Test Message");

  // Calculate the progress
  float progress = (float)_addr / 0x1FFFF;
  int progressBarWidth = progress * 128; // Full width of the display is 128

  // Draw the progress bar
  u8g2.drawFrame(0, 20, 128, 10); // Draw frame of the progress bar
  u8g2.drawBox(0, 20, progressBarWidth, 10); // Draw the progress

  // Show progress in kilobytes
  char progressText[20];
  snprintf(progressText, sizeof(progressText), "%dKB/128KB", (int)(_addr / 1024));
  u8g2.drawStr(0, 40, progressText);

  char IPText[20];
  snprintf(IPText, sizeof(IPText), "IP: %s", WiFi.localIP().toString().c_str());
  u8g2.drawStr(0, 60, IPText);

  // Send buffer to display
  u8g2.sendBuffer();
}

void initPins() {

  pinMode(shiftClk, OUTPUT);
  pinMode(addrLatch, OUTPUT);
  pinMode(dataLatch, OUTPUT);
  pinMode(serialOut, OUTPUT);
  pinMode(romOE, OUTPUT);
  pinMode(romWE, OUTPUT);
  pinMode(writeDataOE, OUTPUT);

  digitalWrite(romWE, HIGH);
  digitalWrite(romOE, HIGH);
  digitalWrite(writeDataOE, HIGH);
  digitalWrite(addrLatch, LOW);
  digitalWrite(shiftClk, LOW);
  digitalWrite(dataLatch, HIGH);
  //digitalWrite(serialOut, HIGH);
}

// Function to shift a single bit into the shift registers
void shiftBit(bool _bit) {

  // Set the serial output value to the bit
  if (_bit) digitalWrite(serialOut, HIGH);
  else digitalWrite(serialOut, LOW);

  delayMicroseconds(10);

  // Shift the bit into the shift registers
  digitalWrite(shiftClk, HIGH);
  delayMicroseconds(10);
  digitalWrite(shiftClk, LOW);

  delayMicroseconds(10);

  // Reset serialOut back to high since it is also the OE' for data
  digitalWrite(serialOut, HIGH);

  delayMicroseconds(10);
}

// Function to perform a series of shifts in order to load and latch an address into registers
void loadAddrReg(uint32_t _addr) {

  // Truncate the uint32_t to 17 bits from the LSB
  _addr &= 0x1FFFF;

  //Serial.println(_addr);

  // Iterate over each bit of the address (except MSB) and shift the bits into shift registers
  for (int i = 15; i >= 0; i--) {
    shiftBit((_addr >> i) & 1);
    if(_addr == 0x1FED5) {
      Serial.println((_addr >> i) & 1);
    }
  }

  // Latch the address registers
  digitalWrite(addrLatch, HIGH);
  delayMicroseconds(10);
  digitalWrite(addrLatch, LOW);
  delayMicroseconds(10);

  // Use the unlatched serial data output for the 17 bit
  shiftBit((_addr >> 16) & 1); // Shift the A16 bit into the shift registers
  for (int i = 14; i >= 0; i--) {
    shiftBit(0); // Shift in 15 zeros so the bit A16 is output from shift register
  }
}

// Function to perform a series of shifts in order to load and latch a byte into data register
void loadDataReg(uint8_t _byte) {

  for (int i = 7; i >= 0; i--) {
    shiftBit((_byte >> i) & 1);
  }

  // Latch the data register
  digitalWrite(dataLatch, LOW);
  delayMicroseconds(10);
  digitalWrite(dataLatch, HIGH);
  delayMicroseconds(10);
}

// Returns a byte
uint8_t loadReadData() {

  // Store the byte being read in serially
  uint8_t receivedByte = 0;

  // Make sure data input reg is disabled
  digitalWrite(writeDataOE, HIGH);
  delayMicroseconds(10);

  // Enable Output on ROM
  digitalWrite(romOE, LOW);
  delayMicroseconds(10);

  // Latch current output from ROM
  digitalWrite(dataLatch, LOW);
  delayMicroseconds(10);
  digitalWrite(dataLatch, HIGH);
  delayMicroseconds(10);

  // Disable Output on ROM
  digitalWrite(romOE, HIGH);
  delayMicroseconds(10);

  // Read in each bit of the byte being output
  for (int i = 7; i >= 0; i--) {

    // Add the bit's value based on its bit number
    receivedByte += (analogRead(A0) >= 768) << i;

    // Cycle the serial data clock
    digitalWrite(shiftClk, HIGH);
    delayMicroseconds(10);
    digitalWrite(shiftClk, LOW);
    delayMicroseconds(10);
  }

  return receivedByte;
}

// Function to write a single byte to a memory address
void writeByte(uint8_t _byte, uint32_t _addr) {

  // Verify the memory address exists
  if (_addr > 0x1FFFF) {
    Serial.println("Invalid memory address for writing: ");
    Serial.println(_addr, HEX);
    return;
  }

  // NOTE: the MSB of the address is not latched, it is stored in the shift registers so ensure that
  // NOTE: the address is also loaded AFTER the data is loaded

  // Enable data register output
  digitalWrite(writeDataOE, LOW);
  delayMicroseconds(10);
  
  // Write Enable
  digitalWrite(romWE, LOW);
  delayMicroseconds(10);
  // End Write Enable
  digitalWrite(romWE, HIGH);
  delayMicroseconds(10);

  // Disable data register output
  digitalWrite(writeDataOE, HIGH);
  delayMicroseconds(10);
}

// Returns a byte from the specified memory address
uint8_t readByte(uint32_t _addr) {

  // Load the address register with the provided bytes
  loadAddrReg(_addr);

  uint8_t byte = loadReadData();

  // Return the value read from the address
  return byte;
}

// Function to read bytes from address 0x000000 to 0x01FFFF and save to a file
void readAndSaveBytes(const char* _filename) {

  // Initialize the LittleFS file system
  if (!LittleFS.begin()) {
      Serial.println("An error has occurred while mounting LittleFS");
      return;
  }
  
  // Check if the file exists
  if (LittleFS.exists(_filename)) {
      LittleFS.remove(_filename);
      Serial.print("File deleted: ");
      Serial.println(_filename);
  } else {
      Serial.print("File does not exist: ");
      Serial.println(_filename);
  }
  
  // Open the file in write mode
  File file = LittleFS.open(_filename, "w");
  if (!file) {
      Serial.println("Error: Unable to open file for writing.");
      return;
  }

  
  // Iterate over addresses from 0x000000 to 0x01FFFF
  for (uint32_t addr = 0x000000; addr <= 0x01FFFF; addr++) {

    // Read a byte from the address
    uint8_t byte = readByte(addr);

    // Call the progress function every 0x51E steps
    if (addr % 0x407 == 0) {
      //showProgressOLED("Reading...", addr);
    }

    // Write the byte to the file
    file.write(byte);
  }

  //showProgressOLED("Connecting to WiFi...", 0x1FFFF);
  
  // Close the file
  file.close();
  Serial.print("Bytes read and saved to file: ");
  Serial.println(_filename);
}

// Handler for the root path "/"
void handleRoot() {
  server.send(200, "text/html", "<h1>Welcome to NodeMCU Web Server</h1><a href=\"/download\">Download Data File</a>");
}

// Handler for downloading the file
void handleFileDownload() {
  const char* filename = "/data.bin";
  
  if (LittleFS.exists(filename)) {
      File file = LittleFS.open(filename, "r");
      if (file) {
          server.streamFile(file, "application/octet-stream");
          file.close();
      } else {
          server.send(500, "text/plain", "Failed to open file for reading");
      }
  } else {
      server.send(404, "text/plain", "File not found");
  }
}
