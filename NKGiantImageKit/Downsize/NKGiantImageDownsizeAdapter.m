//
//  NKGiantImageDownsizeAdapter.m
//  NKGiantImageKit
//
//  Created by Near Kong on 2019/9/30.
//  Copyright © 2019 Near Kong. All rights reserved.
//

#import "NKGiantImageDownsizeAdapter.h"

#import <QuartzCore/QuartzCore.h>

NSString * const NKGiantImageDownsizeAdapterErrorDomain = @"_NKGiantImage_Downsize_ErrorDomain";


@implementation NKGiantImageDownsizeOptions

- (instancetype)init {
    self = [super init];
    if (self) {
        _destImageSizeMB = 2;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    NKGiantImageDownsizeOptions *options = [[[self class] allocWithZone:zone] init];
    options.destImageSizeMB = _destImageSizeMB;
    options.synchronous = _synchronous;
    return options;
}

- (void)setDestImageSizeMB:(CGFloat)destImageSizeMB {
    if (destImageSizeMB > 0.199) {
        _destImageSizeMB = destImageSizeMB;
    }
}

@end


static NSInteger const _NKGiantImage_Downsize_BytesPerPixel = 4;
static NSInteger const _NKGiantImage_Downsize_PixelsPerMB = 1024 * 1024 / _NKGiantImage_Downsize_BytesPerPixel;

static NSInteger const _NKGiantImage_Downsize_TileSizeMB = 20;
static NSInteger const _NKGiantImage_Downsize_TileResolution = _NKGiantImage_Downsize_PixelsPerMB * _NKGiantImage_Downsize_TileSizeMB;
static NSInteger const _NKGiantImage_Downsize_DestSeemOverlap  = 2;

static inline void _NKGiantImage_MainDispatch_async(void (^block)(void)){
    if (block) {
        if ([NSThread isMainThread]) {
            block();
        } else {
            dispatch_async(dispatch_get_main_queue(), block);
        }
    }
}

@interface NKGiantImageDownsizeOperation : NSOperation <NSCopying>

@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, copy) NKGiantImageDownsizeOptions *options;
@property (nonatomic, copy) NKGiantImageDownsizeProgress progress;
@property (nonatomic, copy) NKGiantImageDownsizeCompleted completed;

@property (nonatomic) BOOL suspended;
@property (nonatomic) BOOL suspendedByMemoryWarning;

@property (nonatomic) CGSize sourceResolution;
@property (nonatomic) CGSize destResolution;
@property (nonatomic) CGSize sourceTile;
@property (nonatomic) CGSize destTile;
@property (nonatomic) NSInteger sourceSeemOverlap;
@property (nonatomic) CGFloat destSeemOverlap;

@property (nonatomic) NSInteger currentIteration;
@property (nonatomic) NSInteger totalIterations;

@property (nonatomic) CGContextRef destContext;

- (instancetype)initWithSourceImage:(UIImage *)sourceImage options:(NKGiantImageDownsizeOptions *)options progress:(NKGiantImageDownsizeProgress)progress completed:(NKGiantImageDownsizeCompleted)completed;


@end

@implementation NKGiantImageDownsizeOperation

- (instancetype)initWithSourceImage:(UIImage *)sourceImage options:(NKGiantImageDownsizeOptions *)options progress:(NKGiantImageDownsizeProgress)progress completed:(NKGiantImageDownsizeCompleted)completed {
    self = [super init];
    if (self) {
        _sourceImage = sourceImage;
        
        self.options = options;
        self.progress = progress;
        self.completed = completed;
        
        if (![self configure]) {
            self = nil;
        }
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    NKGiantImageDownsizeOperation *operation = [[[self class] allocWithZone:zone] init];
    
    operation.sourceImage = _sourceImage;
    operation.options = _options;
    operation.progress = _progress;
    operation.completed = _completed;
    
    operation.suspended = _suspended;
    operation.suspendedByMemoryWarning = _suspendedByMemoryWarning;
    
    operation.sourceResolution = _sourceResolution;
    operation.destResolution = _destResolution;
    operation.sourceTile = _sourceTile;
    operation.destTile = _destTile;
    operation.sourceSeemOverlap = _sourceSeemOverlap;
    operation.destSeemOverlap = _destSeemOverlap;
    
    operation.currentIteration = _currentIteration;
    operation.totalIterations = _totalIterations;
    
    operation.destContext = _destContext;
    operation.name = self.name;
    
    return operation;
}

- (BOOL)configure {
    
    if (!_completed) {
        return false;
    }
    
    if (!_sourceImage || !_sourceImage.CGImage) {
        [self exceptionStatus:NKGiantImageDownsizeWithoutSourceImage];
        return false;
    }
    
    _sourceResolution = CGSizeMake(CGImageGetWidth(_sourceImage.CGImage), CGImageGetHeight(_sourceImage.CGImage));
    double sourceTotalPixels = _sourceResolution.width * _sourceResolution.height;
    double sourceTotalMB = sourceTotalPixels / _NKGiantImage_Downsize_PixelsPerMB;
    if (sourceTotalMB < _options.destImageSizeMB) {
        [self exceptionStatus:NKGiantImageDownsizeLessthanDestMB];
        return false;
    }
    
    double destTotalPixels = _options.destImageSizeMB * _NKGiantImage_Downsize_PixelsPerMB;
    double imageScale = sqrt(destTotalPixels / sourceTotalPixels);
    
    _destResolution = CGSizeMake((NSInteger)(_sourceResolution.width * imageScale), (NSInteger)(_sourceResolution.height * imageScale));
    // fix scale
    imageScale = _destResolution.width / _sourceResolution.width;
    
    // create an offscreen bitmap context that will hold the output image
    // pixel data, as it becomes available by the downscaling routine.
    // use the RGB colorspace as this is the colorspace iOS GPU is optimized for.
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    int bytesPerRow = _NKGiantImage_Downsize_BytesPerPixel * _destResolution.width;
    // create the output bitmap context
    CGContextRef destContext = CGBitmapContextCreate(NULL, _destResolution.width, _destResolution.height, 8, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
    // release the color space object as its job is done
    CGColorSpaceRelease( colorSpace );
    
    // remember CFTypes assign/check for NULL. NSObjects assign/check for nil.
    if (destContext == NULL) {
        NSLog(@"failed to create the output bitmap context!");
        
        [self exceptionStatus:NKGiantImageDownsizeFailedToCreateContext];
        return false;
    }
    
    // flip the output graphics context so that it aligns with the
    // cocoa style orientation of the input document. this is needed
    // because we used cocoa's UIImage -imageNamed to open the input file.
    CGContextTranslateCTM(destContext, 0.0f, _destResolution.height);
    CGContextScaleCTM(destContext, 1.0f, -1.0f);
    
    _destContext = destContext;
    
    
    // now define the size of the rectangle to be used for the
    // incremental blits from the input image to the output image.
    // we use a source tile width equal to the width of the source
    // image due to the way that iOS retrieves image data from disk.
    // iOS must decode an image from disk in full width 'bands', even
    // if current graphics context is clipped to a subrect within that
    // band. Therefore we fully utilize all of the pixel data that results
    // from a decoding opertion by achnoring our tile size to the full
    // width of the input image.
    double sourceTileHeight = MIN((NSInteger)(_NKGiantImage_Downsize_TileResolution / _sourceResolution.width), CGRectGetHeight(UIScreen.mainScreen.nativeBounds));
    double destTileHeight = sourceTileHeight * imageScale;
    
    _sourceTile = CGSizeMake(_sourceResolution.width, sourceTileHeight);
    _destTile = CGSizeMake(_destResolution.width, destTileHeight);
    
    // add seem overlaps to the tiles, but save the original tile height for y coordinate calculations.
    // the source seem overlap is proportionate to the destination seem overlap.
    // this is the amount of pixels to overlap each tile as we assemble the ouput image.
    _sourceSeemOverlap = _NKGiantImage_Downsize_DestSeemOverlap / imageScale;
    _destSeemOverlap = _sourceSeemOverlap * imageScale;
    
    _currentIteration = 0;
    _totalIterations = _sourceResolution.height / sourceTileHeight;
    if ((NSInteger)_sourceResolution.height % (NSInteger)sourceTileHeight > _sourceSeemOverlap && (NSInteger)_destResolution.height % (NSInteger)destTileHeight > _sourceSeemOverlap) {
        ++_totalIterations;
    }
    
    self.name = [NSString stringWithFormat:@"_NKGiantImage_DownsizeOperation_<%p>", self];
    
    return true;
}

#pragma mark operation
- (void)main {
    while (_currentIteration < _totalIterations) {
        
        if (self.isCancelled) {
            [self exceptionStatus:NKGiantImageDownsizeCanceled];
            return;
        }

        if (_suspended) {
//            [self exceptionStatus:NKGiantImageDownsizeSuspended];
//            return;
        }

        if (_suspendedByMemoryWarning) {
            unsigned int sleepTime = (arc4random() % 10 + 1) * 3;
            sleep(sleepTime);
            _suspendedByMemoryWarning = false;
            continue;
        }
        
        CGRect sourceTileRect = CGRectMake(0, _sourceTile.height * _currentIteration, _sourceTile.width, _sourceTile.height + _sourceSeemOverlap);
        CGRect destTileRect = CGRectMake(0,
                                         _destResolution.height - _destTile.height *  (_currentIteration + 1) - _destSeemOverlap,
                                         _destTile.width,
                                         _destTile.height + _destSeemOverlap);
        
        // if this is the last tile, it's size may be smaller than the source tile height.
        // adjust the dest tile size to account for that difference.
        if(_currentIteration == _totalIterations - 1) {
            sourceTileRect.size.height = _sourceResolution.height - sourceTileRect.origin.y;
            
            destTileRect.origin.y = 0;
            destTileRect.size.height = _destResolution.height - _destTile.height * _currentIteration;
        }
        
        @autoreleasepool {
            // create a reference to the source image with its context clipped to the argument rect.
            CGImageRef sourceTileImageRef = CGImageCreateWithImageInRect(_sourceImage.CGImage, sourceTileRect);
            // read and write a tile sized portion of pixels from the input image to the output image.
            CGContextDrawImage(_destContext, destTileRect, sourceTileImageRef);
            /* release the source tile portion pixel data. note,
             releasing the sourceTileImageRef doesn't actually release the tile portion pixel
             data that we just drew, but the call afterward does. */
            CGImageRelease(sourceTileImageRef);
        }
        
        ++_currentIteration;
        [self didProgress];
    }
    
    [self didFinishedDownsize];
}

- (void)didProgress {
    if (_currentIteration < _totalIterations && _progress && !self.cancelled && !_suspended && !_suspendedByMemoryWarning) {
        UIImage *image = [self createImage];
        CGFloat progress = (CGFloat)_currentIteration / (CGFloat)_totalIterations;
        
        __weak typeof(self) weakSelf = self;
        _NKGiantImage_MainDispatch_async(^{
            weakSelf.progress(progress, image);
        });
    }
}

- (void)didFinishedDownsize {
    
    if (self.isCancelled) {
        [self exceptionStatus:NKGiantImageDownsizeCanceled];
        return;
    }
    
    if (_completed) {
        UIImage *image = [self createImage];
        if (!image) {
            [self exceptionStatus:NKGiantImageDownsizeFailedToCreateImage];
            return;
        }
        
        NSDictionary *info = @{};
        _NKGiantImage_MainDispatch_async(^{
            self.completed(image, info, nil);
        });
    }
    
    if (_destContext != NULL) {
        CGContextRelease(_destContext);
    }
}

- (UIImage *)createImage {
    CGImageRef destImageRef = CGBitmapContextCreateImage(_destContext);
    UIImage *image = [UIImage imageWithCGImage:destImageRef scale:1 orientation:UIImageOrientationDownMirrored];
    CGImageRelease(destImageRef);
    return image;
}

- (void)exceptionStatus:(NKGiantImageDownsizeStatus)status {
    NSString *failureReason = @"";
    UIImage *destImage = nil;
    switch (status) {
        case NKGiantImageDownsizeCanceled:
            failureReason = @"downsize operation has been canceled";
            break;
        case NKGiantImageDownsizeLessthanDestMB:
            failureReason = @"source image is less than dest";
            destImage = _sourceImage;
            break;
        case NKGiantImageDownsizeFailedToCreateContext:
            failureReason = @"fail to create context";
            break;
        case NKGiantImageDownsizeFailedToCreateImage:
            failureReason = @"fail to create image";
            break;
        case NKGiantImageDownsizeWithoutSourceImage:
            failureReason = @"source image is null or the cgimage of source image is nil";
            break;
    }
    
    if (_completed) {
        NSError *error = [NSError errorWithDomain:NKGiantImageDownsizeAdapterErrorDomain code:status userInfo:@{NSLocalizedFailureReasonErrorKey: failureReason}];
        _NKGiantImage_MainDispatch_async(^{
            self.completed(nil, error.userInfo, error);
        });
    }
    
    if (_destContext != NULL) {
        CGContextRelease(_destContext);
    }
}


@end


@interface NKGiantImageDownsizeAdapter ()

@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, strong) NSMutableDictionary<NKGiantImageDownsizeKey, NKGiantImageDownsizeOperation *> *suspendedDic;

@end

@implementation NKGiantImageDownsizeAdapter

+ (instancetype)defauleAdapter {
    static dispatch_once_t once;
    static NKGiantImageDownsizeAdapter *defauleAdapter;
    dispatch_once(&once, ^{
        defauleAdapter = [[self alloc] init];
    });
    return defauleAdapter;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.name = [NSString stringWithFormat:@"com.nate.giantImageDownsizing.downsizeQueue.%p", self];
        _queue.maxConcurrentOperationCount = 3;
        
        _suspendedDic = NSMutableDictionary.new;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

#pragma mark interface
- (nullable NKGiantImageDownsizeKey)downsizeImage:(UIImage *)sourceImage options:(nullable NKGiantImageDownsizeOptions *)options progress:(nullable NKGiantImageDownsizeProgress)progress completed:(NKGiantImageDownsizeCompleted)completed {
    
    NKGiantImageDownsizeOperation *operation = [[NKGiantImageDownsizeOperation alloc] initWithSourceImage:sourceImage options:options ?: NKGiantImageDownsizeOptions.new progress:progress completed:completed];
    if (operation) {
        if (options.synchronous) {
            [operation start];
        } else {
            [_queue addOperation:operation];
        }
    }
    return operation.name;
}

- (void)cancelAllDownsizeOperations {
    [_queue cancelAllOperations];
}

- (BOOL)cancelOperationWithKey:(NKGiantImageDownsizeKey)key {
    if (!key.length) {
        return false;
    }
    
    for (NSOperation *operation in _queue.operations) {
        if ([operation.name isEqualToString:key]) {
            [operation cancel];
            return true;
        }
    }
    
    return false;
}

#pragma mark notification
- (void)didReceiveMemoryWarning {
    for (NKGiantImageDownsizeOperation *operation in _queue.operations) {
        if (operation.isExecuting) {
            operation.suspendedByMemoryWarning = true;
        }
    }
}

@end
