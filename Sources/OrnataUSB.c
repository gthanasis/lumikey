// Talks to the Ornata V2 over USB control requests on the default pipe.
//
// macOS won't let a regular app open a keyboard's HID interfaces, but a control request
// sent to the device itself goes through without opening (or seizing) anything. Same
// approach as libusb and Razer macOS (librazermacos).

#include "OrnataUSB.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>

#define RAZER_VENDOR_ID 0x1532
#define ORNATA_V2_PRODUCT_ID 0x025D
#define ORNATA_INTERFACE 2

static IOUSBDeviceInterface **device = NULL;

static io_service_t find_service(void) {
    CFMutableDictionaryRef match = IOServiceMatching(kIOUSBHostDeviceClassName);
    if (!match) return IO_OBJECT_NULL;
    int vendor = RAZER_VENDOR_ID, product = ORNATA_V2_PRODUCT_ID;
    CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &vendor);
    CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &product);
    CFDictionarySetValue(match, CFSTR(kUSBVendorID), v);
    CFDictionarySetValue(match, CFSTR(kUSBProductID), p);
    CFRelease(v);
    CFRelease(p);
    return IOServiceGetMatchingService(kIOMainPortDefault, match);  // consumes match
}

static IOUSBDeviceInterface **open_device(void) {
    io_service_t service = find_service();
    if (!service) return NULL;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
                                                         kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS || !plugin) return NULL;

    IOUSBDeviceInterface **dev = NULL;
    (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&dev);
    (*plugin)->Release(plugin);
    return dev;
}

static void close_device(void) {
    if (device) {
        (*device)->Release(device);
        device = NULL;
    }
}

static IOReturn send_once(const uint8_t *report) {
    if (!device) device = open_device();
    if (!device) return kIOReturnNoDevice;

    uint8_t buffer[ORNATA_REPORT_LEN];
    for (int i = 0; i < ORNATA_REPORT_LEN; i++) buffer[i] = report[i];

    IOUSBDevRequest request = {
        .bmRequestType = USBmakebmRequestType(kUSBOut, kUSBClass, kUSBInterface),
        .bRequest = 0x09,  // HID SET_REPORT
        .wValue = 0x300,   // feature report, ID 0
        .wIndex = ORNATA_INTERFACE,
        .wLength = ORNATA_REPORT_LEN,
        .pData = buffer,
    };
    return (*device)->DeviceRequest(device, &request);
}

int32_t ornata_send(const uint8_t *report) {
    IOReturn kr = send_once(report);
    if (kr != kIOReturnSuccess) {
        // The keyboard may have been unplugged and replugged: drop the stale handle, retry once.
        close_device();
        kr = send_once(report);
    }
    return kr;
}

int ornata_connected(void) {
    io_service_t service = find_service();
    if (!service) return 0;
    IOObjectRelease(service);
    return 1;
}
