// Talks to Razer keyboards over USB control requests on the default pipe.
//
// macOS won't let a regular app open a keyboard's HID interfaces, but a control request
// sent to the device itself goes through without opening (or seizing) anything. Same
// approach as libusb and Razer macOS (librazermacos).

#include "RazerUSB.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <unistd.h>

#define RAZER_VENDOR_ID 0x1532

// One open device at a time: the keyboard the app is driving.
static IOUSBDeviceInterface **device = NULL;
static uint16_t device_product_id = 0;

static io_service_t find_service(uint16_t product_id) {
    CFMutableDictionaryRef match = IOServiceMatching(kIOUSBHostDeviceClassName);
    if (!match) return IO_OBJECT_NULL;
    int vendor = RAZER_VENDOR_ID, product = product_id;
    CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &vendor);
    CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &product);
    CFDictionarySetValue(match, CFSTR(kUSBVendorID), v);
    CFDictionarySetValue(match, CFSTR(kUSBProductID), p);
    CFRelease(v);
    CFRelease(p);
    return IOServiceGetMatchingService(kIOMainPortDefault, match);  // consumes match
}

static int number_property(io_service_t service, CFStringRef key) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, NULL, 0);
    int n = -1;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberIntType, &n);
    if (value) CFRelease(value);
    return n;
}

int razer_list(uint16_t *product_ids, int max) {
    // USB matching needs vendor and product together, so walk every USB device instead.
    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOUSBHostDeviceClassName),
                                     &iterator) != KERN_SUCCESS) return 0;
    int count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        if (number_property(service, CFSTR(kUSBVendorID)) == RAZER_VENDOR_ID) {
            int pid = number_property(service, CFSTR(kUSBProductID));
            if (pid >= 0) {
                if (count < max) product_ids[count] = (uint16_t)pid;
                count++;
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return count;
}

int razer_product_name(uint16_t product_id, char *name, int length) {
    io_service_t service = find_service(product_id);
    if (!service) return 0;
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR(kUSBProductString), NULL, 0);
    IOObjectRelease(service);
    int ok = value && CFGetTypeID(value) == CFStringGetTypeID() &&
             CFStringGetCString(value, name, length, kCFStringEncodingUTF8);
    if (value) CFRelease(value);
    return ok;
}

static void close_device(void) {
    if (device) {
        (*device)->Release(device);
        device = NULL;
    }
}

static IOUSBDeviceInterface **open_device(uint16_t product_id) {
    if (device && device_product_id == product_id) return device;
    close_device();

    io_service_t service = find_service(product_id);
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
    device = dev;
    device_product_id = product_id;
    return dev;
}

static IOReturn request_once(uint16_t product_id, uint16_t interface, int direction, uint8_t *buffer) {
    IOUSBDeviceInterface **dev = open_device(product_id);
    if (!dev) return kIOReturnNoDevice;
    IOUSBDevRequest request = {
        .bmRequestType = USBmakebmRequestType(direction, kUSBClass, kUSBInterface),
        .bRequest = direction == kUSBOut ? 0x09 : 0x01,  // HID SET_REPORT / GET_REPORT
        .wValue = 0x300,                                 // feature report, ID 0
        .wIndex = interface,
        .wLength = RAZER_REPORT_LEN,
        .pData = buffer,
    };
    return (*dev)->DeviceRequest(dev, &request);
}

static IOReturn request(uint16_t product_id, uint16_t interface, int direction, uint8_t *buffer) {
    IOReturn kr = request_once(product_id, interface, direction, buffer);
    if (kr != kIOReturnSuccess) {
        // The keyboard may have been unplugged and replugged: drop the stale handle, retry once.
        close_device();
        kr = request_once(product_id, interface, direction, buffer);
    }
    return kr;
}

int32_t razer_send(uint16_t product_id, uint16_t interface, const uint8_t *report) {
    uint8_t buffer[RAZER_REPORT_LEN];
    for (int i = 0; i < RAZER_REPORT_LEN; i++) buffer[i] = report[i];
    return request(product_id, interface, kUSBOut, buffer);
}

int32_t razer_query(uint16_t product_id, uint16_t interface, const uint8_t *report, uint8_t *response) {
    IOReturn kr = razer_send(product_id, interface, report);
    if (kr != kIOReturnSuccess) return kr;
    usleep(5000);  // give the keyboard time to prepare its answer
    return request(product_id, interface, kUSBIn, response);
}
