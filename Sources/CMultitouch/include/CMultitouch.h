#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
  int frame; double timestamp; int identifier; int state; int fingerId; int handId;
  MTVector normalized; float size; int zero1; float angle; float majorAxis; float minorAxis;
  MTVector absolute; int zero2[2]; float density;
} MTTouch;
typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef, const MTTouch *, int, double, int);
CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef);
