#ifndef RAZER_USB_H
#define RAZER_USB_H

#include <stdint.h>

#define RAZER_REPORT_LEN 90

/// Product IDs of the connected Razer USB devices (vendor 0x1532), at most `max` of them.
/// Returns how many there are, which may be more than `max`.
int razer_list(uint16_t *product_ids, int max);

/// The device's USB product name, e.g. "Razer Ornata V2". 1 if found, 0 otherwise.
int razer_product_name(uint16_t product_id, char *name, int length);

/// Sends one 90-byte Razer report as a HID SET_REPORT control request to `interface`.
/// Returns 0 on success, an IOKit error code otherwise (e.g. keyboard unplugged).
int32_t razer_send(uint16_t product_id, uint16_t interface, const uint8_t *report);

/// Sends a report, then reads the keyboard's 90-byte answer (HID GET_REPORT) into `response`.
int32_t razer_query(uint16_t product_id, uint16_t interface, const uint8_t *report, uint8_t *response);

#endif
