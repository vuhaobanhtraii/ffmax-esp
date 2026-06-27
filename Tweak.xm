#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#include <vector>
#include <cmath> // For std::sqrt

// Unity Engine Structures
struct Vector3 {
    float x, y, z;
};

struct Vector2 {
    float x, y;
};

// Pointer Declarations
typedef void* Camera;
typedef void* Transform;
typedef void* UMAData;
typedef void* Il2CppObject;
typedef void* Il2CppType;

// Function Pointer Signatures based on dumped RVAs
Camera (*Camera_get_main)();
Vector3 (*Camera_WorldToScreenPoint)(Camera cam, Vector3 position);
Transform (*Component_get_transform)(void* component);
Vector3 (*Transform_get_position)(Transform transform);
void* (*Object_FindObjectsOfType)(void* type);

// IL2CPP Runtime API Exports (dynamically resolved)
extern "C" {
    Il2CppObject* il2cpp_domain_get();
    void* il2cpp_domain_assembly_open(Il2CppObject* domain, const char* name);
    void* il2cpp_assembly_get_image(void* assembly);
    void* il2cpp_class_from_name(void* image, const char* namesp, const char* name);
    Il2CppType* il2cpp_class_get_type(void* klass);
    void* il2cpp_type_get_object(Il2CppType* type);
}

uintptr_t slideAddress = 0;
void* umaDataClassTypeObject = nullptr;

// Initialize Addresses & Offsets
void InitOffsets() {
    // Resolve UnityFramework base address dynamically
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            slideAddress = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    // Fallback if not loaded separately
    if (slideAddress == 0) {
        slideAddress = (uintptr_t)_dyld_get_image_header(0);
    }
    
    // Assign function pointers based on RVAs
    Camera_get_main = (Camera(*)())(slideAddress + 0x922F64C);
    Camera_WorldToScreenPoint = (Vector3(*)(Camera, Vector3))(slideAddress + 0x922EF58);
    Component_get_transform = (Transform(*)(void*))(slideAddress + 0x9289418);
    Transform_get_position = (Vector3(*)(Transform))(slideAddress + 0x929B728);
    Object_FindObjectsOfType = (void*(*)(void*))(slideAddress + 0x9293D94);
}

// Retrieve UMAData Type Object for FindObjectsOfType
void* GetUMADataTypeObject() {
    if (umaDataClassTypeObject) return umaDataClassTypeObject;
    
    Il2CppObject* domain = il2cpp_domain_get();
    if (!domain) return nullptr;
    void* assembly = il2cpp_domain_assembly_open(domain, "Assembly-CSharp.dll");
    if (!assembly) return nullptr;
    void* image = il2cpp_assembly_get_image(assembly);
    if (!image) return nullptr;
    void* klass = il2cpp_class_from_name(image, "UMA", "UMAData");
    if (!klass) return nullptr;
    Il2CppType* type = il2cpp_class_get_type(klass);
    if (!type) return nullptr;
    
    umaDataClassTypeObject = il2cpp_type_get_object(type);
    return umaDataClassTypeObject;
}

// Native Helper for IL2CPP Array wrapper
template <typename T>
struct Il2CppArray {
    void* klass;
    void* monitor;
    void* bounds;
    int max_length;
    T vector[65536];
};

struct PlayerInfo {
    Vector2 screenPos;
    bool isEnemy;
    float distance;
};

// Main Helper to parse Player locations and filter enemies
std::vector<PlayerInfo> GetPlayers() {
    std::vector<PlayerInfo> playerList;
    
    Camera mainCam = Camera_get_main();
    if (!mainCam) return playerList;
    
    void* typeObj = GetUMADataTypeObject();
    if (!typeObj) return playerList;
    
    // Find all UMAData components currently active in the scene
    auto array = (Il2CppArray<UMAData>*)(Object_FindObjectsOfType(typeObj));
    if (!array || (uintptr_t)array < 0x1000) return playerList;
    
    // 1. Locate local player position to calculate distances
    Vector3 localPos = {0, 0, 0};
    for (int i = 0; i < array->max_length; i++) {
        UMAData player = array->vector[i];
        if (!player || (uintptr_t)player < 0x1000) continue;
        
        bool isLocalPlayer = *(bool*)((uintptr_t)player + 0x80);
        if (isLocalPlayer) {
            Transform t = Component_get_transform(player);
            if (t) localPos = Transform_get_position(t);
            break;
        }
    }
    
    // 2. Process other players (enemies)
    for (int i = 0; i < array->max_length; i++) {
        UMAData player = array->vector[i];
        if (!player || (uintptr_t)player < 0x1000) continue;
        
        bool isLocalPlayer = *(bool*)((uintptr_t)player + 0x80);
        if (isLocalPlayer) continue; // Skip drawing overlay on self
        
        bool isTeammate = *(bool*)((uintptr_t)player + 0x81);
        Transform t = Component_get_transform(player);
        if (!t) continue;
        
        Vector3 worldPos = Transform_get_position(t);
        Vector3 screenPos3D = Camera_WorldToScreenPoint(mainCam, worldPos);
        
        // Z > 0 means the player is in front of the camera
        if (screenPos3D.z > 0) {
            PlayerInfo info;
            // Unity Screen coordinates start at bottom-left, iOS UIWindow starts at top-left
            info.screenPos.x = screenPos3D.x / [UIScreen mainScreen].scale;
            info.screenPos.y = ([UIScreen mainScreen].bounds.size.height) - (screenPos3D.y / [UIScreen mainScreen].scale);
            info.isEnemy = !isTeammate;
            
            // Calculate distance
            float dx = worldPos.x - localPos.x;
            float dy = worldPos.y - localPos.y;
            float dz = worldPos.z - localPos.z;
            info.distance = std::sqrt(dx*dx + dy*dy + dz*dz);
            
            playerList.push_back(info);
        }
    }
    
    return playerList;
}

// iOS UI Window & Custom Drawing Canvas
@interface ESPView : UIView
@end

@implementation ESPView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO; // Allow touch pass-through to game controls
        
        // Redraw at 60 FPS
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(setNeedsDisplay) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    
    std::vector<PlayerInfo> players = GetPlayers();
    
    for (const auto& player : players) {
        if (player.isEnemy) {
            // Draw Box around Enemy player
            CGContextSetStrokeColorWithColor(context, [UIColor redColor].CGColor);
            CGContextSetLineWidth(context, 1.5);
            
            // Box size scaled by distance
            float boxWidth = 2000.0f / player.distance;
            float boxHeight = 4000.0f / player.distance;
            
            CGRect boxRect = CGRectMake(player.screenPos.x - (boxWidth / 2),
                                        player.screenPos.y - boxHeight,
                                        boxWidth,
                                        boxHeight);
            
            CGContextStrokeRect(context, boxRect);
            
            // Draw Snap Line from bottom-center of the screen
            CGContextSetStrokeColorWithColor(context, [UIColor yellowColor].CGColor);
            CGContextSetLineWidth(context, 1.0);
            CGContextMoveToPoint(context, rect.size.width / 2, rect.size.height);
            CGContextAddLineToPoint(context, player.screenPos.x, player.screenPos.y);
            CGContextStrokePath(context);
            
            // Draw Distance Text
            NSString *distStr = [NSString stringWithFormat:@"%.0fm", player.distance];
            NSDictionary *attributes = @{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:10.0],
                NSForegroundColorAttributeName: [UIColor whiteColor]
            };
            [distStr drawAtPoint:CGPointMake(player.screenPos.x - 10, player.screenPos.y + 5) withAttributes:attributes];
        }
    }
}

@end

// Inject Overlay View into Active UIWindow
void InjectESP() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        InitOffsets();
        
        // Wait 5 seconds after launching to ensure the UIWindow is fully initialized
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            
            // Resolve key window safely on all iOS versions (including iOS 13+ SceneDelegate)
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow *window in scene.windows) {
                            if (window.isKeyWindow) {
                                keyWindow = window;
                                break;
                            }
                        }
                    }
                }
            }
            
            if (!keyWindow) {
                keyWindow = [UIApplication sharedApplication].keyWindow;
            }
            
            if (!keyWindow) {
                for (UIWindow *window in [UIApplication sharedApplication].windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
            
            if (keyWindow) {
                ESPView *esp = [[ESPView alloc] initWithFrame:keyWindow.bounds];
                [keyWindow addSubview:esp];
                NSLog(@"[FFMaxESP] ESP Overlay injected successfully!");
            } else {
                NSLog(@"[FFMaxESP] Error: Key window not found.");
            }
        });
    });
}

// Hook Unity initialization using standard Objective-C NSNotificationCenter (ARC-friendly)
%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                     object:nil
                                                      queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *note) {
        InjectESP();
    }];
}
