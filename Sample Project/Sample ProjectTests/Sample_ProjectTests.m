//
//  Sample_ProjectTests.m
//  Sample ProjectTests
//
//  Created by Krzysztof Zablocki on 3/26/12.
//  Copyright (c) 2012 private. All rights reserved.
//

#import "Sample_ProjectTests.h"
#import "SFObservers.h"

@implementation Sample_ProjectTests {
  NSObject *observedObject;
  NSObject *observer;
}

- (void)setUp
{
  [super setUp];

  observedObject = [[NSObject alloc] init];
  observer = [[NSObject alloc] init];
}

- (void)tearDown
{
  AH_RELEASE(observedObject);
  AH_RELEASE(observer);
  [super tearDown];
}

- (void)testKVOAutoRemoval
{
  [observedObject addObserver:observer forKeyPath:@"description" options:NSKeyValueObservingOptionNew context:nil];
  AH_RELEASE(observer), observer = nil;
  AH_RELEASE(observedObject), observedObject = nil;
}

- (void)testKVOAutoRemovalWithContext
{
  [observedObject addObserver:observer forKeyPath:@"description" options:NSKeyValueObservingOptionNew context:AH_BRIDGE(self)];
  AH_RELEASE(observer), observer = nil ;
  AH_RELEASE(observedObject), observedObject = nil;
}

- (void)testKVOAutoRemovalMultiple
{
  [observedObject addObserver:observer forKeyPath:@"description" options:NSKeyValueObservingOptionNew context:AH_BRIDGE(self)];
  [observedObject addObserver:observer forKeyPath:@"class" options:NSKeyValueObservingOptionNew context:nil];
  [observedObject addObserver:observer forKeyPath:@"whatever" options:NSKeyValueObservingOptionNew context:AH_BRIDGE(self)];
  AH_RELEASE(observer), observer = nil;
  AH_RELEASE(observedObject), observedObject = nil;
}

- (void)testKVONotBreakingArray
{
  NSArray *array = [NSArray array];
  STAssertThrows([array addObserver:self forKeyPath:@"count" options:NSKeyValueObservingOptionNew context:nil], @"Array aren't observable, should raise exception");
}

- (void)testNotificationAutoRemoval
{
  @try {
    static NSString *fakeNotification = @"FakeNotification";
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector) name:fakeNotification object:self];
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector2) name:fakeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector4) name:nil object:self];
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector3) name:nil object:nil];

    AH_RELEASE(observer), observer = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:fakeNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:fakeNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OtherNotification" object:self];
    AH_RELEASE(observedObject), observedObject = nil;
  }
  @catch (NSException *exception1) {
    STFail(@"Posting notification without removing deallocated observer lead to crash");
  }
}

- (void)testNotificationRemoval
{
  @try {
    static NSString *fakeNotification = @"FakeNotification";
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector) name:fakeNotification object:self];
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector2) name:fakeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector3) name:nil object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(unsupportedSelector4) name:nil object:self];

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [[NSNotificationCenter defaultCenter] postNotificationName:fakeNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:fakeNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OtherNotification" object:self];
    AH_RELEASE(observer), observer = nil;
    AH_RELEASE(observedObject), observedObject = nil;
  }
  @catch (NSException *exception1) {
    STFail(@"Posting notification after removing deallocated observer lead to crash");
  }
}
@end
