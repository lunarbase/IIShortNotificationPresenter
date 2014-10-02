//
//  IIShortNotificationPresenter.m
//  Copyright (c) 2014 Tom Adriaenssen. All rights reserved.
//

#import "IIShortNotificationPresenter.h"
#import "IIShortNotificationQueue.h"
#import "IIShortNotificationSerialQueue.h"
#import "IIShortNotificationDefaultView.h"
#import "IIShortNotificationViewInstance.h"
#import "IIShortNotificationLayout.h"
#import "IIShortNotificationTopLayout.h"
#import <objc/runtime.h>

@interface IIShortNotificationPresenter () <IIShortNotificationQueueHandler>

@end

@implementation IIShortNotificationPresenter {
    NSMutableArray *_freeNotificationViews;
    NSMutableArray *_usedNotificationViews;
    UIView* _overlayView;
    id<IIShortNotificationQueue> _queue;
    id<IIShortNotificationLayout> _layout;
    __weak NSLayoutConstraint* _topConstraint;
    __weak UIView* _superview;
}

- (id)initWithContainerView:(UIView *)view
{
    self = [super init];
    if (self) {
        self.autoDismissDelay = [[self class] defaultAutoDismissDelay];
        _queue = [[[[self class] notificationQueueClass] alloc] initWithHandler:self];
        _layout = [[[[self class] notificationLayoutClass] alloc] init];
        _superview = view;
        _freeNotificationViews = [NSMutableArray array];
        _usedNotificationViews = [NSMutableArray array];
    }
    return self;
}

- (UIView *)containerView {
    return _superview;
}

#pragma mark - Error

- (void)presentError:(NSString *)error
{
    [self presentError:error title:nil completion:nil];
}

- (void)presentError:(NSString *)error title:(NSString *)title
{
    [self presentError:error title:title completion:nil];
}

- (void)presentError:(NSString *)error title:(NSString *)title completion:(void (^)(void))completion
{
    [self queuePresentation:IIShortNotificationError
                    message:error
                      title:title
                  accessory:NO
                 completion:completion ? ^(IIShortNotificationDismissal dismissal){ completion(); } : nil];
}

#pragma mark - Confirmation

- (void)presentConfirmation:(NSString *)confirmation
{
    [self presentConfirmation:confirmation title:nil accessory:NO completion:nil];
}

- (void)presentConfirmation:(NSString *)confirmation title:(NSString *)title
{
    [self presentConfirmation:confirmation title:title accessory:NO completion:nil];
}

- (void)presentConfirmation:(NSString *)confirmation title:(NSString *)title accessory:(BOOL)accessory completion:(void (^)(IIShortNotificationDismissal dismissal))completion
{
    [self queuePresentation:IIShortNotificationConfirmation
                    message:confirmation
                      title:title
                  accessory:accessory
                 completion:completion];
}

#pragma mark - Notification

- (void)presentNotification:(NSString *)notification
{
    [self presentNotification:notification title:nil accessory:NO completion:nil];
}

- (void)presentNotification:(NSString *)notification title:(NSString *)title
{
    [self presentNotification:notification title:title accessory:NO completion:nil];
}

- (void)presentNotification:(NSString *)notification title:(NSString *)title accessory:(BOOL)accessory completion:(void (^)(IIShortNotificationDismissal dismissal))completion
{
    [self queuePresentation:IIShortNotificationNotification
                    message:notification
                      title:title
                  accessory:accessory
                 completion:completion];
}

#pragma mark - Hard work

- (void)queuePresentation:(IIShortNotificationType)type message:(NSString *)message title:(NSString *)title accessory:(BOOL)accessory completion:(void (^)(IIShortNotificationDismissal dismissal))completion
{
    [_queue queuePresentation:type message:message title:title accessory:accessory completion:completion];
}

- (void)handlePresentation:(IIShortNotificationType)type message:(NSString *)message title:(NSString *)title accessory:(BOOL)accessory completion:(void (^)(IIShortNotificationDismissal dismissal))completion
{
    if (!_overlayView) {
        _overlayView = [UIView new];
        _overlayView.translatesAutoresizingMaskIntoConstraints = NO;
        _overlayView.clipsToBounds = YES;

        UITapGestureRecognizer* tapper = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        [_overlayView addGestureRecognizer:tapper];

        UISwipeGestureRecognizer* swiper = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
        swiper.direction = UISwipeGestureRecognizerDirectionUp;
        [_overlayView addGestureRecognizer:swiper];
    }

    if (_overlayView.superview != _superview) {
        [_superview addSubview:_overlayView];
        [_superview addConstraints:@[
                                    // top
                                    [NSLayoutConstraint constraintWithItem:_overlayView
                                                                 attribute:NSLayoutAttributeTop
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:_superview
                                                                 attribute:NSLayoutAttributeTop
                                                                multiplier:1
                                                                  constant:0],
                                    // left
                                    [NSLayoutConstraint constraintWithItem:_overlayView
                                                                 attribute:NSLayoutAttributeLeft
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:_superview
                                                                 attribute:NSLayoutAttributeLeft
                                                                multiplier:1
                                                                  constant:0],
                                    // right
                                    [NSLayoutConstraint constraintWithItem:_overlayView
                                                                 attribute:NSLayoutAttributeRight
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:_superview
                                                                 attribute:NSLayoutAttributeRight
                                                                multiplier:1
                                                                  constant:0],
                                    // bottom
                                    [NSLayoutConstraint constraintWithItem:_overlayView
                                                                 attribute:NSLayoutAttributeBottom
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:_superview
                                                                 attribute:NSLayoutAttributeBottom
                                                                multiplier:1
                                                                  constant:0],
                                    ]];

    }

    IIShortNotificationViewInstance *instance = [self dequeueNotificationView];

    [instance.view setShortNotificationType:type title:title message:message accessoryVisible:accessory];
    instance.accessory = accessory;
    instance.completion = [completion copy];

    instance.topConstraint.constant = -instance.view.intrinsicContentSize.height;
    [_overlayView layoutIfNeeded];
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.6 options:0 animations:^{
        instance.view.alpha = 1;
        instance.topConstraint.constant = 0;
        [_overlayView layoutIfNeeded];
    } completion:^(BOOL finished) {
    }];

    if (type != IIShortNotificationError) {
        [self performSelector:@selector(autoDismiss:) withObject:instance afterDelay:self.autoDismissDelay];
    }
}

- (void)handlePresentationsFinished
{
    @synchronized(_freeNotificationViews) {
        [_overlayView removeFromSuperview];
    }
}

- (void)autoDismiss:(IIShortNotificationViewInstance*)instance
{
    [self dismiss:IIShortNotificationAutomaticDismissal instance:instance];
}

- (void)dismiss:(IIShortNotificationDismissal)dismissal {
    IIShortNotificationViewInstance *topInstance;
    @synchronized(_usedNotificationViews) {
        topInstance = [_usedNotificationViews firstObject];
        [_usedNotificationViews removeObjectAtIndex:0];
    }
}

- (void)dismiss:(IIShortNotificationDismissal)dismissal instance:(IIShortNotificationViewInstance *)instance {
    if (!instance) return;

    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.6 options:0 animations:^{
        instance.view.alpha = 0;
        instance.topConstraint.constant = -instance.view.intrinsicContentSize.height;
        [_overlayView layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (instance.completion) instance.completion(dismissal);
        @synchronized(_freeNotificationViews) {
            [_freeNotificationViews addObject:instance];
        }
        [_queue dismissedPresentation];
    }];
}

#pragma mark - notification views

- (IIShortNotificationViewInstance*)dequeueNotificationView {
    IIShortNotificationViewInstance *instance = nil;
    @synchronized(_freeNotificationViews) {
        instance = [_freeNotificationViews lastObject];
        if (instance) {
            [_freeNotificationViews removeLastObject];
        }
    }

    if (!instance) {
        instance = [IIShortNotificationViewInstance new];
        instance.view = [[[self class] notificationViewClass] new];
        instance.view.translatesAutoresizingMaskIntoConstraints = NO;
        [_overlayView addSubview:instance.view];

        NSArray* constraints = @[
                                 // top
                                 [NSLayoutConstraint constraintWithItem:instance.view
                                                              attribute:NSLayoutAttributeTop
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:_overlayView
                                                              attribute:NSLayoutAttributeTop
                                                             multiplier:1
                                                               constant:0],
                                 // left
                                 [NSLayoutConstraint constraintWithItem:instance.view
                                                              attribute:NSLayoutAttributeLeft
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:_overlayView
                                                              attribute:NSLayoutAttributeLeft
                                                             multiplier:1
                                                               constant:0],
                                 // right
                                 [NSLayoutConstraint constraintWithItem:instance.view
                                                              attribute:NSLayoutAttributeRight
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:_overlayView
                                                              attribute:NSLayoutAttributeRight
                                                             multiplier:1
                                                               constant:0],
                                 ];
        
        instance.constraints = constraints;
        [_overlayView addConstraints:constraints];
    }

    [_overlayView sendSubviewToBack:instance.view];
    instance.view.alpha = 0;
    @synchronized(_usedNotificationViews) {
        [_usedNotificationViews addObject:instance];
    }
    return instance;
}

#pragma mark - dismissing tap

- (void)tapped:(UITapGestureRecognizer*)tapper {
    IIShortNotificationViewInstance *topInstance;
    @synchronized(_usedNotificationViews) {
        topInstance = [_usedNotificationViews firstObject];
    }

    if (!topInstance) return;

    if (topInstance.accessory & CGRectContainsPoint(topInstance.view.bounds, [tapper locationInView:topInstance.view])) {
        [self dismiss:IIShortNotificationUserAccessoryDismissal instance:topInstance];
    }
    else
        [self dismiss:IIShortNotificationUserDismissal instance:topInstance];
}

- (void)swiped:(UITapGestureRecognizer*)swiper {
    [self dismiss:IIShortNotificationUserDismissal];
}

#pragma mark - View class

static Class _viewClass;

+ (void)setNotificationViewClass:(Class)viewClass {
    _viewClass = viewClass;
}

+ (Class)notificationViewClass {
    return _viewClass ?: [IIShortNotificationDefaultView class];
}

#pragma mark - Queue class

static Class _queueClass;

+ (void)setNotificationQueueClass:(Class)queueClass {
    _queueClass = queueClass;
}

+ (Class)notificationQueueClass {
    return _queueClass ?: [IIShortNotificationSerialQueue class];
}

#pragma mark - Layout class

static Class _layoutClass;

+ (void)setNotificationLayoutClass:(Class)viewClass {
    _layoutClass = viewClass;
}

+ (Class)notificationLayoutClass {
    return _layoutClass ?: [IIShortNotificationTopLayout class];
}


#pragma mark - auto dismiss

static NSTimeInterval _defaultAutoDismissDelay = 5;

+ (void)setDefaultAutoDismissDelay:(NSTimeInterval)delay
{
    _defaultAutoDismissDelay = delay;
}

+ (NSTimeInterval)defaultAutoDismissDelay
{
    return _defaultAutoDismissDelay;
}

@end

@implementation UIViewController (IIShortNotificationPresenter)

- (id<IIShortNotificationPresentation>)presenter {
    IIShortNotificationPresenter* presenter = objc_getAssociatedObject(self, @selector(presenter));
    if (!presenter) {
        presenter = [[IIShortNotificationPresenter alloc] initWithContainerView:self.view];
        objc_setAssociatedObject(self, @selector(presenter), presenter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return presenter;
}

- (void)presentError:(NSString*)error
{
    [[self presenter] presentError:error];
}

- (void)presentError:(NSString*)error title:(NSString*)title;
{
    [[self presenter] presentError:error title:title];
}

- (void)presentError:(NSString *)error title:(NSString*)title completion:(void(^)(void))completion
{
    [[self presenter] presentError:error title:title completion:completion];
}

- (void)presentConfirmation:(NSString*)confirmation
{
    [[self presenter] presentConfirmation:confirmation];
}

- (void)presentConfirmation:(NSString*)confirmation title:(NSString*)title
{
    [[self presenter] presentConfirmation:confirmation title:title];
}

- (void)presentConfirmation:(NSString *)confirmation title:(NSString*)title accessory:(BOOL)accessory completion:(void(^)(IIShortNotificationDismissal dismissal))completion
{
    [[self presenter] presentConfirmation:confirmation title:title accessory:accessory completion:completion];
}

- (void)presentNotification:(NSString*)notification;
{
    [[self presenter] presentNotification:notification];
}

- (void)presentNotification:(NSString *)notification title:(NSString*)title
{
    [[self presenter] presentNotification:notification title:title];
}

- (void)presentNotification:(NSString *)notification title:(NSString*)title accessory:(BOOL)accessory completion:(void(^)(IIShortNotificationDismissal dismissal))completion
{
    [[self presenter] presentNotification:notification title:title accessory:accessory completion:completion];
}

@end