# Diseño-de-una-arquitectura-de-comunicacion-LoRaWAN-para-medidores-inteligentes-domesticos.
Trabajo de grado para la empresa Minka, en este repositorio se encontrarán los códigos o scripts utilizados a lo largo de este proyecto.
Este consta de dos grupos principales de códigos:

- Códigos de transmisión: Son dos scripts configurados en la tarjeta TTGO LoRa32, estos permiten la conexión hacia el gateway (se debe revisar las llaves configuradas tanto en la tarjeta como en el gateway), enviando tanto mensajes planos como el envío de información sobre el consumo energetico de esta misma.
- Códigos para análisis de los resultados: Estos códigos buscan facilitar el análisis de los resultados obtenidos (ubicados en la carpeta Resultados), mostrando de manera gráfica como se comporta la transmisión y valorandola cuantitativamente con los valores del SNR, RSSI y el Delivery Rate.

Por últomo se encuentra la carpeta con los reusltados de estas pruebas, las cuales son presentadas en hojas de calculo, e simportante tener en cuenta que para el correcto funcionamiento de los códigos para el análisis, estos deben estar en la misma carpeta(o se debe modificar la ruta). 
