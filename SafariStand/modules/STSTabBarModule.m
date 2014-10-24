//
//  STSTabBarModule.m
//  SafariStand

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC
#endif

#import <mach/mach_time.h>
#import "SafariStand.h"
#import "STSTabBarModule.h"
#import "STTabProxy.h"

@implementation STSTabBarModule {
    uint64_t _nextTime;
    uint64_t _duration;
}


-(void)layoutTabBarForExistingWindow
{
    //check exists window
    STSafariEnumerateBrowserWindow(^(NSWindow* win, NSWindowController* winCtl, BOOL* stop){
        if([win isVisible] && [winCtl respondsToSelector:@selector(isTabBarVisible)]
           && [winCtl respondsToSelector:@selector(scrollableTabBarView)]
           ){
            if (objc_msgSend(winCtl, @selector(isTabBarVisible))) {
                id tabBarView = objc_msgSend(winCtl, @selector(scrollableTabBarView));
                if([tabBarView respondsToSelector:@selector(_updateButtonsAndLayOutAnimated:)]){
                    objc_msgSend(tabBarView, @selector(_updateButtonsAndLayOutAnimated:), YES);
                }
            }
        }
    });
}

- (id)initWithStand:(id)core
{
    self = [super initWithStand:core];
    if (self) {

        //SwitchTabWithWheel
        mach_timebase_info_data_t timebaseInfo;
        mach_timebase_info(&timebaseInfo);
        _duration = ((1000000000 * timebaseInfo.denom) / 3) / timebaseInfo.numer; //1/3sec
        _nextTime=mach_absolute_time();
        
        KZRMETHOD_SWIZZLING_WITHBLOCK
        (
         "ScrollableTabBarView", "scrollWheel:",
         KZRMethodInspection, call, sel,
         ^void (id slf, NSEvent* event){
             if([[NSUserDefaults standardUserDefaults]boolForKey:kpSwitchTabWithWheelEnabled]){
                 id window=objc_msgSend(slf, @selector(window));
                 if([[[window windowController]className]isEqualToString:kSafariBrowserWindowController]){
                     if ([self canAction]) {
                         SEL action=nil;
                         //[theEvent deltaY] が+なら上、-なら下
                         CGFloat deltaY=[event deltaY];
                         if(deltaY>0){
                             action=@selector(selectPreviousTab:);
                         }else if(deltaY<0){
                             action=@selector(selectNextTab:);
                         }
                         if(action){
                             [NSApp sendAction:action to:nil from:self];
                             return;
                         }
                     }
                 }
             }
             
             call.as_void(slf, sel, event);

         });


        //タブバー幅変更
        KZRMETHOD_SWIZZLING_WITHBLOCK
        (
         "ScrollableTabBarView", "_buttonWidthForNumberOfButtons:inWidth:remainderWidth:",
         KZRMethodInspection, call, sel,
         ^double (id slf, unsigned long long buttonNum, double inWidth, double* remainderWidth){
             double result=call.as_double(slf, sel, buttonNum, inWidth, remainderWidth);
             if ([[NSUserDefaults standardUserDefaults]boolForKey:kpSuppressTabBarWidthEnabled]) {
                 double maxWidth=floor([[NSUserDefaults standardUserDefaults]doubleForKey:kpSuppressTabBarWidthValue]);
                 if (result>maxWidth) {
                     //double diff=result-maxWidth;
                     //*remainderWidth=diff+*remainderWidth;
                     return maxWidth;
                 }
             }
             return result;
         });
        
        KZRMETHOD_SWIZZLING_WITHBLOCK
        (
         "ScrollableTabBarView", "_shouldLayOutButtonsToAlignWithWindowCenter",
         KZRMethodInspection, call, sel,
         ^BOOL (id slf){
             if ([[NSUserDefaults standardUserDefaults]boolForKey:kpSuppressTabBarWidthEnabled]) {
                 return NO;
             }
             
             BOOL result=call.as_char(slf, sel);
             return result;
         });

    
        double minX=[[NSUserDefaults standardUserDefaults]doubleForKey:kpSuppressTabBarWidthValue];
        if (minX<140.0 || minX>480.0) minX=240.0;
        if ([[NSUserDefaults standardUserDefaults]boolForKey:kpSuppressTabBarWidthEnabled]) {
            [self layoutTabBarForExistingWindow];
        }
        [self observePrefValue:kpSuppressTabBarWidthEnabled];
        [self observePrefValue:kpSuppressTabBarWidthValue];
        
        
        //test
        KZRMETHOD_SWIZZLING_
        (
         "ScrollableTabButton",
         "initWithFrame:tabViewItem:",
         KZRMethodInspection, call, sel)
        ^id (id slf, NSRect frame, id obj){
            NSView* result=call.as_id(slf, sel, frame, obj);
            NSView* closeButton=objc_msgSend(result, @selector(closeButton));

            NSImage* img=[NSImage imageNamed:NSImageNameFolder];
            //[view setImage:img];
            CALayer* layer=[STTabIconLayer layer];
            NSRect layerFrame=NSMakeRect(4, 4, 16, 16);
            layer.frame=layerFrame;
            layer.contents=img;
            [result.layer addSublayer:layer];
            //[layer bind:NSHiddenBinding toObject:result withKeyPath:@"showingCloseButton" options:nil];
            [layer bind:NSHiddenBinding toObject:closeButton withKeyPath:NSHiddenBinding options:@{ NSValueTransformerNameBindingOption : NSNegateBooleanTransformerName }];
            id tabViewItem=objc_msgSend(result, @selector(tabViewItem));
            STTabProxy* tp=[STTabProxy tabProxyForTabViewItem:tabViewItem];
            if (tp) {
                [layer bind:@"contents" toObject:tp withKeyPath:@"image" options:nil];
            }
            return result;
        }_WITHBLOCK;
        
        [self observePrefValue:kpShowIconOnTabBarEnabled];

    }
    return self;
}

- (void)dealloc
{

}

- (void)prefValue:(NSString*)key changed:(id)value
{
    if([key isEqualToString:kpSuppressTabBarWidthEnabled]||[key isEqualToString:kpSuppressTabBarWidthValue]){
        [self layoutTabBarForExistingWindow];
    }else if([key isEqualToString:kpShowIconOnTabBarEnabled]){
        
    }
}

- (BOOL)canAction
{
    uint64_t now=mach_absolute_time();
    if (now>_nextTime) {
        _nextTime=now+_duration;
        return YES;
    }
    return NO;
}

@end



@implementation STTabIconLayer

- (void)dealloc
{
    [self unbind:NSHiddenBinding];
    [self unbind:@"contents"];
    LOG(@"layer d");
}

@end
