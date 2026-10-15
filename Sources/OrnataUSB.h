#ifndef ORNATA_USB_H
#define ORNATA_USB_H

#include <stdint.h>

#define ORNATA_REPORT_LEN 90

/// Sends one 90-byte Razer report to the keyboard as a HID SET_REPORT control request.
/// Returns 0 on success, an IOKit error code otherwise (e.g. keyboard unplugged).
int32_t ornata_send(const uint8_t *report);

/// 1 if an Ornata V2 is connected.
int ornata_connected(void);

#endif
