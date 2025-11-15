#include <lmic.h>
#include <hal/hal.h>
#include <SPI.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH    128
#define SCREEN_HEIGHT    64
#define OLED_RESET      -1
#define SCREEN_ADDRESS 0x3C

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

const lmic_pinmap lmic_pins = {
  .nss   = 18,
  .rxtx  = LMIC_UNUSED_PIN,
  .rst   = 23,
  .dio   = {26, 33, 32},
};

static const u1_t PROGMEM APPEUI[8]  = {0x82,0xBC,0x00,0x00,0x00,0x00,0x80,0x00};
static const u1_t PROGMEM DEVEUI[8]  = {0xFF,0xFE,0x24,0x0F,0x16,0x1C,0x06,0x10};
static const u1_t PROGMEM APPKEY[16] = {
  0x2B,0x7E,0x15,0x16,0x28,0xAE,0xD2,0xA6,
  0xAB,0xF7,0x15,0x88,0x09,0xCF,0x4F,0x3C
};

void os_getArtEui(u1_t* buf) { memcpy_P(buf, APPEUI, sizeof(APPEUI)); }
void os_getDevEui(u1_t* buf) { memcpy_P(buf, DEVEUI, sizeof(DEVEUI)); }
void os_getDevKey(u1_t* buf) { memcpy_P(buf, APPKEY, sizeof(APPKEY)); }

static osjob_t sendjob;
const unsigned TX_INTERVAL = 1;  // intervalo en segundos

void showMessage(const char* message) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0, 10);
  display.println(message);
  display.display();
}

void do_send(osjob_t* j) {
  //LMIC_setLinkCheckMode(0);
  //LMIC_setDrTxpow(DR_SF10, LMIC.txpow);
  if (LMIC.opmode & OP_TXRXPEND) {
    Serial.println("TX pendiente...");
    showMessage("TX pendiente...");
  } else {
    const char msg[] = "Ho";
    LMIC_setTxData2(1, (uint8_t*)msg, sizeof(msg)-1, 0);
    Serial.println("Paquete enviado");
    showMessage("Enviando datos...");
  }
  // Reprogramar el siguiente envío
  os_setTimedCallback(j, os_getTime() + sec2osticks(TX_INTERVAL), do_send);
  
}

void onEvent(ev_t ev) {
  Serial.print("Evento LMIC: ");
  Serial.println(ev);
  switch(ev) {
    case EV_JOINING:
      Serial.println("Uniendose a la red...");
      showMessage("Uniendose...");
      break;
    case EV_JOINED:
      Serial.println("¡Conectado!");
      showMessage("¡Conectado!");
      //LMIC_setLinkCheckMode(0);
      //LMIC_setDrTxpow(DR_SF10, LMIC.txpow);

      // Programa el primer envío tras TX_INTERVAL segundos
      os_setTimedCallback(&sendjob,
                          os_getTime() + sec2osticks(TX_INTERVAL),
                          do_send);
      break;
    case EV_TXCOMPLETE:
      Serial.println("TX completada");
      showMessage("TX completada");
      break;
    case EV_JOIN_FAILED:
      Serial.println("Fallo union");
      showMessage("Fallo union");
      break;
    default:
      break;
  }
}

void setup() {
  Serial.begin(115200);

  if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println("Fallo OLED");
    while (1);
  }
  showMessage("Inicializando...");

  SPI.begin(5, 19, 27, 18);  // SCK, MISO, MOSI, SS
  os_init_ex(&lmic_pins);
  LMIC_reset();
  
  // Habilita la banda 1, sub-banda 1
  LMIC_enableSubBand(1);

  LMIC_setClockError(MAX_CLOCK_ERROR * 10 / 100);
  LMIC_startJoining();  // Solo un JOIN
}

void loop() {
  os_runloop_once();
}
