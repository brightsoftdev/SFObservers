//
//  Created by merowing2 on 3/25/12.
//
//
//
#import <objc/runtime.h>
#import <objc/message.h>
#import "NSObject+SFObservers.h"

static NSString const *NSObjectKVOSFObserversArrayKey = @"NSObjectKVOSFObserversArrayKey";
static NSString const *NSObjectKVOSFObserversAllowMethodForwardingKey = @"NSObjectKVOSFObserversAllowMethodForwardingKey";

static NSString *NSObjectKVOSFObserversAddSelector = @"sf_original_addObserver:forKeyPath:options:context:";
static NSString *NSObjectKVOSFObserversRemoveSelector = @"sf_original_removeObserver:forKeyPath:";
static NSString *NSObjectKVOSFObserversRemoveSpecificSelector = @"sf_original_removeObserver:forKeyPath:context:";

@interface __SFObserversKVOObserverInfo : NSObject
@property(nonatomic, copy) NSString *keyPath;
@property(nonatomic, AH_WEAK) id context;
@property(nonatomic, assign) void *blockKey;
@end

@implementation __SFObserversKVOObserverInfo
@synthesize keyPath;
@synthesize context;
@synthesize blockKey;

- (void)dealloc
{
  AH_RELEASE(keyPath);
  AH_SUPER_DEALLOC;
}

@end


@implementation NSObject (SFObservers)

+ (void)sf_swapSelector:(SEL)aOriginalSelector withSelector:(SEL)aSwappedSelector
{
  Method originalMethod = class_getInstanceMethod(self, aOriginalSelector);
  Method swappedMethod = class_getInstanceMethod(self, aSwappedSelector);

  SEL newSelector = NSSelectorFromString([NSString stringWithFormat:@"sf_original_%@", NSStringFromSelector(aOriginalSelector)]);
  class_addMethod([self class], newSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
  class_replaceMethod([self class], aOriginalSelector, method_getImplementation(swappedMethod), method_getTypeEncoding(swappedMethod));
}

+ (void)load
{
  //! swap methods
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    @autoreleasepool {
      [self sf_swapSelector:@selector(addObserver:forKeyPath:options:context:) withSelector:@selector(sf_addObserver:forKeyPath:options:context:)];
      [self sf_swapSelector:@selector(removeObserver:forKeyPath:) withSelector:@selector(sf_removeObserver:forKeyPath:)];
      [self sf_swapSelector:@selector(removeObserver:forKeyPath:context:) withSelector:@selector(sf_removeObserver:forKeyPath:context:)];
    }
  });
}

- (BOOL)allowMethodForwarding
{
  NSNumber *state = objc_getAssociatedObject(self, AH_BRIDGE(NSObjectKVOSFObserversAllowMethodForwardingKey));
  return [state boolValue];
}

- (void)setAllowMethodForwarding:(BOOL)allowForwarding
{
  objc_setAssociatedObject(self, AH_BRIDGE(NSObjectKVOSFObserversAllowMethodForwardingKey), [NSNumber numberWithBool:allowForwarding], OBJC_ASSOCIATION_RETAIN);
}

- (void)sf_addObserver:(id)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(id)aContext
{
  //! store info into our observer structure
  NSMutableDictionary *registeredKeyPaths = (NSMutableDictionary *)objc_getAssociatedObject(observer, AH_BRIDGE(NSObjectKVOSFObserversArrayKey));
  if (!registeredKeyPaths) {
    registeredKeyPaths = [NSMutableDictionary dictionary];
    objc_setAssociatedObject(observer, AH_BRIDGE(NSObjectKVOSFObserversArrayKey), registeredKeyPaths, OBJC_ASSOCIATION_RETAIN);
  }

  NSMutableArray *observerInfos = [registeredKeyPaths objectForKey:keyPath];
  if (!observerInfos) {
    observerInfos = [NSMutableArray array];
    [registeredKeyPaths setObject:observerInfos forKey:keyPath];
  }
  __block __SFObserversKVOObserverInfo *observerInfo = nil;

  //! don't allow to add many times the same observer
  [observerInfos enumerateObjectsUsingBlock:^void(id obj, NSUInteger idx, BOOL *stop) {
    __SFObserversKVOObserverInfo *info = obj;
    if ([info.keyPath isEqualToString:keyPath] && info.context == aContext) {
      observerInfo = info;
      *stop = YES;
    }
  }];

  if (!observerInfo) {
    observerInfo = [[__SFObserversKVOObserverInfo alloc] init];
    [observerInfos addObject:observerInfo];
    AH_RELEASE(observerInfo);
  } else {
    //! don't register twice so skip this
    NSAssert(NO, @"You shouldn't register twice for same keyPath, context");
    return;
  }

  observerInfo.keyPath = keyPath;
  observerInfo.context = aContext;

  //! Add auto remove when observer is going to be deallocated
  __unsafe_unretained __block id weakSelf = self;
  __unsafe_unretained __block id weakObserver = observer;
  __unsafe_unretained __block id weakContext = aContext;

  void *key = [observer performBlockOnDealloc:^{
    if ([weakSelf sf_removeObserver:weakObserver forKeyPath:keyPath context:weakContext registeredKeyPaths:registeredKeyPaths]) {
      [self setAllowMethodForwarding:YES];
#if SF_OBSERVERS_LOG_ORIGINAL_METHODS
      NSLog(@"Calling original method %@ with parameters %@ %@ %@", NSObjectKVOSFObserversRemoveSpecificSelector, weakObserver, keyPath, weakContext);
#endif
      objc_msgSend(self, NSSelectorFromString(NSObjectKVOSFObserversRemoveSpecificSelector), weakObserver, keyPath, weakContext);
      [self setAllowMethodForwarding:NO];
    }
  }];

  observerInfo.blockKey = key;

  //! call originalMethod
#if SF_OBSERVERS_LOG_ORIGINAL_METHODS
  NSLog(@"Calling original method %@ with parameters %@ %@ %d %@", NSObjectKVOSFObserversAddSelector, observer, keyPath, options, aContext);
#endif
  objc_msgSend(self, NSSelectorFromString(NSObjectKVOSFObserversAddSelector), observer, keyPath, options, aContext);
}


- (void)sf_removeObserver:(id)observer forKeyPath:(NSString *)keyPath
{
  NSMutableDictionary *registeredKeyPaths = (NSMutableDictionary *)objc_getAssociatedObject(observer, AH_BRIDGE(NSObjectKVOSFObserversArrayKey));
  if ([self allowMethodForwarding] || [self sf_removeObserver:observer forKeyPath:keyPath context:nil registeredKeyPaths:registeredKeyPaths]) {
    if ([self allowMethodForwarding]) {
#if SF_OBSERVERS_LOG_ORIGINAL_METHODS
      NSLog(@"Calling original method %@ with parameters %@ %@", NSObjectKVOSFObserversRemoveSelector, observer, keyPath);
#endif
      objc_msgSend(self, NSSelectorFromString(NSObjectKVOSFObserversRemoveSelector), observer, keyPath);
    } else {
      [self setAllowMethodForwarding:YES];
#if SF_OBSERVERS_LOG_ORIGINAL_METHODS
      NSLog(@"Calling original method %@ with parameters %@ %@", NSObjectKVOSFObserversRemoveSelector, observer, keyPath);
#endif
      objc_msgSend(self, NSSelectorFromString(NSObjectKVOSFObserversRemoveSelector), observer, keyPath);
      [self setAllowMethodForwarding:NO];
    }
  }
}

- (void)sf_removeObserver:(id)observer forKeyPath:(NSString *)keyPath context:(id)context
{
  NSLog(@"Remove observer called with %@ %@ context %@\n", observer, keyPath, context);

  NSMutableDictionary *registeredKeyPaths = (NSMutableDictionary *)objc_getAssociatedObject(observer, AH_BRIDGE(NSObjectKVOSFObserversArrayKey));
  if ([self allowMethodForwarding] || [self sf_removeObserver:observer forKeyPath:keyPath context:context registeredKeyPaths:registeredKeyPaths]) {
    if ([self allowMethodForwarding]) {
#if SF_OBSERVERS_LOG_ORIGINAL_METHODS
      NSLog(@"Calling original method %@ with parameters %@ %@ %@", NSObjectKVOSFObserversRemoveSpecificSelector, observer, keyPath, context);
#endif
      objc_msgSend(self, NSSelectorFromString(NSObjectKVOSFObserversRemoveSpecificSelector), observer, keyPath, context);
    } else {
      [self setAllowMethodForwarding:YES];
#if SF_OBSERVERS_LOG_ORIGINAL_METHODS
      NSLog(@"Calling original method %@ with parameters %@ %@ %@", NSObjectKVOSFObserversRemoveSpecificSelector, observer, keyPath, context);
#endif
      objc_msgSend(self, NSSelectorFromString(NSObjectKVOSFObserversRemoveSpecificSelector), observer, keyPath, context);
      [self setAllowMethodForwarding:NO];
    }
  }
}

- (BOOL)sf_removeObserver:(id)observer
               forKeyPath:(NSString *)keyPath
                  context:(id)context
  registeredKeyPaths:(NSMutableDictionary *)registeredKeyPaths
{
  __block BOOL result = NO;
  if ([keyPath length] <= 0 && context == nil) {
    //! don't need to execute block on dealloc so cleanup
    [registeredKeyPaths enumerateKeysAndObjectsUsingBlock:^void(id key, id obj, BOOL *stop) {
      NSMutableArray *observerInfos = obj;
      [observerInfos enumerateObjectsUsingBlock:^void(id innerObj, NSUInteger idx, BOOL *innerStop) {
        __SFObserversKVOObserverInfo *info = innerObj;
        [observer cancelDeallocBlockWithKey:info.blockKey];
      }];
    }];
    [registeredKeyPaths removeAllObjects];
    return YES;
  } else {
    [registeredKeyPaths enumerateKeysAndObjectsUsingBlock:^void(id key, id obj, BOOL *stop) {
      NSMutableArray *observerInfos = obj;
      NSMutableArray *objectsToRemove = [NSMutableArray array];
      [observerInfos enumerateObjectsUsingBlock:^void(id innerObj, NSUInteger idx, BOOL *innerStop) {
        __SFObserversKVOObserverInfo *info = innerObj;

        if ((!keyPath || [keyPath isEqualToString:info.keyPath]) && (!context || (context == info.context))) {
          //! remove this info
          [objectsToRemove addObject:innerObj];

          //! cancel dealloc block
          [innerObj cancelDeallocBlockWithKey:info.blockKey];
        }
      }];

      //! remove all collected objects
      if ([objectsToRemove count] > 0) {
        [observerInfos removeObjectsInArray:objectsToRemove];
        result = YES;
      }
    }];
  }

  return result;
}
@end