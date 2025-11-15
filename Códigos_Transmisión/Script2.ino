#include <lmic.h>
#include <hal/hal.h>
#include <SPI.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ===================== Batería / ADC =====================
#define PIN_BAT_ADC       34          // GPIO34 (input-only, ADC1)
#define R1_BAT            120000.0    // ohmios (VBAT -> nodo)
#define R2_BAT            300000.0    // ohmios (nodo -> GND)
#define DIVIDER_RATIO     ((R1_BAT + R2_BAT) / R2_BAT)   // ≈ 1.4
#define V_OFFSET          0.00f       // corrección fina en voltios si la necesitas
#define ADC_SAMPLES       8           // promedio simple para filtrar

// ===================== OLED (solo estado) =====================
#define SCREEN_WIDTH      128
#define SCREEN_HEIGHT     64
#define OLED_RESET        -1
#define SCREEN_ADDRESS    0x3C
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// ===================== Parámetros energéticos =====================
const float I_TX   = 120.0;   // Corriente de transmisión (mA)
const float I_IDLE = 15.0;    // Corriente en reposo (mA)
const float ToA_SF7  = 31.0e-3;
const float ToA_SF8  = 62.0e-3;
const float ToA_SF9  = 123.9e-3;
const float ToA_SF10 = 206.8e-3;

// ===================== LMIC / LoRaWAN =====================
const lmic_pinmap lmic_pins = {
  .nss   = 18,
  .rxtx  = LMIC_UNUSED_PIN,
  .rst   = 23,
  .dio   = {26, 33, 32},
};

// Usa tus valores:
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
const unsigned TX_INTERVAL = 1;     // segundos (amigable con la red)

// ===================== Utilidades =====================
void showStatus(const char* line1, const char* line2 = "") {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0, 0);
  display.println(line1);
  if (line2 && line2[0]) display.println(line2);
  display.display();
}

// Lee VBAT en voltios, usando el divisor R1/R2 y promedio simple
float readVBAT() {
  // Ancho y atenuación del ADC (ESP32)
  analogSetWidth(12);
  analogSetPinAttenuation(PIN_BAT_ADC, ADC_11db); // ~3.6V en pin
  (void)analogRead(PIN_BAT_ADC); // dummy throwaway para estabilizar

  uint32_t mv_sum = 0;
  for (int i = 0; i < ADC_SAMPLES; i++) {
    mv_sum += analogReadMilliVolts(PIN_BAT_ADC); // mV en el pin ADC
    delay(2);
  }
  float vadc = (mv_sum / (float)ADC_SAMPLES) / 1000.0f; // V en pin
  float vbat = vadc * DIVIDER_RATIO + V_OFFSET;         // V batería real
  return vbat;
}
String analyzePower(float vbat) {
  uint8_t dr = LMIC.datarate;  // DR actual (determina el SF)
  float toa = 0;
  const char* sf_label = "";

  switch (dr) {
    case DR_SF7:  toa = ToA_SF7;  sf_label = "SF7";  break;
    case DR_SF8:  toa = ToA_SF8;  sf_label = "SF8";  break;
    case DR_SF9:  toa = ToA_SF9;  sf_label = "SF9";  break;
    case DR_SF10: toa = ToA_SF10; sf_label = "SF10"; break;
    default:      toa = ToA_SF9;  sf_label = "SF?";  break;
  }

  // Cálculos
  float Tperiod = TX_INTERVAL; // segundos
  float Iavg = (I_TX * toa + I_IDLE * (Tperiod - toa)) / Tperiod; // mA promedio
  float P_TX = vbat * (I_TX / 1000.0); // Potencia instantánea (W)
  float P_TX_mW = P_TX * 1000.0;       // Convertir a mW

  // Mostrar resultados por Serial
  Serial.println("----- Análisis energético -----");
  Serial.print("Spreading Factor: "); Serial.println(sf_label);
  Serial.print("Tiempo en aire: "); Serial.print(toa * 1000, 1); Serial.println(" ms");
  Serial.print("VBAT: "); Serial.print(vbat, 2); Serial.println(" V");
  Serial.print("I_avg: "); Serial.print(Iavg, 2); Serial.println(" mA");
  Serial.print("P_TX: "); Serial.print(P_TX_mW, 2); Serial.println(" mW");
  Serial.println("--------------------------------");

  // Construir cadena CSV para enviar por LoRa
  String data = String(sf_label) + "," + String(vbat, 4) + "," +
                String(Iavg, 4) + "," + String(P_TX_mW, 4);
  return data;
}

// ===================== Envío LoRaWAN =====================

void do_send(osjob_t* j) {
  if (LMIC.opmode & OP_TXRXPEND) {
    Serial.println("TX pendiente...");
    showStatus("TX pendiente...");
  } else {
    // Leer voltaje de batería
    float vbat = readVBAT();

    // Generar texto CSV con análisis energético
    String payloadStr = analyzePower(vbat);

    // Convertir a arreglo de bytes ASCII
    uint8_t payload[64];
    payloadStr.toCharArray((char*)payload, sizeof(payload));

    // Enviar por LoRaWAN (puerto 1)
    LMIC_setTxData2(1, payload, strlen((char*)payload), 0);

    Serial.print("TX -> "); Serial.println(payloadStr);
    showStatus("Enviando...", payloadStr.c_str());
  }

  // Programar siguiente envío
  os_setTimedCallback(j, os_getTime() + sec2osticks(TX_INTERVAL), do_send);
}

void onEvent(ev_t ev) {
  Serial.print("Evento LMIC: "); Serial.println(ev);
  switch (ev) {
    case EV_JOINING:
      Serial.println("Uniendose a la red...");
      showStatus("Uniendose...");
      break;

    case EV_JOINED:
      Serial.println("¡Conectado!");
      showStatus("¡Conectado!");
      // Recomendado: desactivar LinkCheck durante pruebas
      LMIC_setLinkCheckMode(0);
      LMIC_setAdrMode(0);
      LMIC_setDrTxpow(DR_SF7, LMIC.txpow);

      // Primer envío inmediatamente
      os_setTimedCallback(&sendjob, os_getTime() + sec2osticks(1), do_send);
      break;

    case EV_TXCOMPLETE:
      Serial.println("TX completada");
      showStatus("TX completada");
      break;

    case EV_JOIN_FAILED:
      Serial.println("Fallo de union");
      showStatus("Fallo union");
      break;

    default:
      break;
  }
}
void setup() {
  Serial.begin(115200);
  display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS);
  showStatus("Inicializando...");

  SPI.begin(5, 19, 27, 18);
  os_init_ex(&lmic_pins);
  LMIC_reset();

  // --> Selecciona la FSB que usa TU gateway.
  LMIC_selectSubBand(1);       // Prueba FSB1; si tu gateway usa FSB2, pon 2.

  // (Opcional) Fuerza máscara exacta de la FSB
  for (uint8_t i = 0; i < 72; i++) LMIC_disableChannel(i);
  for (uint8_t i = 0; i <= 7; i++) LMIC_enableChannel(i);  // si FSB1 (0..7)
  // si FSB2: for (uint8_t i = 8; i <= 15; i++) LMIC_enableChannel(i);

  LMIC_setAdrMode(0);
  LMIC_setDrTxpow(DR_SF7, 14); // AU915 DR3: SF7/125k
  LMIC_setClockError(MAX_CLOCK_ERROR * 10 / 100);

  LMIC_startJoining();
}


void loop() {
  os_runloop_once();
}
