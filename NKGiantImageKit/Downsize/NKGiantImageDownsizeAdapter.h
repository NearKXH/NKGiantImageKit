//
//  NKGiantImageDownsizeAdapter.h
//  NKGiantImageKit
//
//  Created by Near Kong on 2019/9/30.
//  Copyright © 2019 Near Kong. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NKGiantImageDownsizeOptions : NSObject <NSCopying>

@property (nonatomic, assign, getter=isSynchronous) BOOL synchronous;   // default is false, run in current thread if true.

/**
 dest memory cast by the image drawing, not the data of the image
 must not less than 0.2MB (200KB), otherwise setting false.
 default is 2MB.
 */
@property (nonatomic, assign) CGFloat destImageSizeMB;

@end


extern NSErrorDomain const NKGiantImageDownsizeAdapterErrorDomain;
typedef NS_ENUM(NSUInteger, NKGiantImageDownsizeStatus) {
    NKGiantImageDownsizeCanceled = -9001,
    NKGiantImageDownsizeWithoutSourceImage,
    NKGiantImageDownsizeLessthanDestMB,
    NKGiantImageDownsizeFailedToCreateContext,
    NKGiantImageDownsizeFailedToCreateImage,
};

typedef void (^NKGiantImageDownsizeProgress)(CGFloat progress, UIImage * _Nullable progressImage);
typedef void (^NKGiantImageDownsizeCompleted)(UIImage * _Nullable image, NSDictionary *__nullable info, NSError * _Nullable error);

typedef NSString *NKGiantImageDownsizeKey;

@interface NKGiantImageDownsizeAdapter : NSObject

+ (instancetype)defauleAdapter;

- (instancetype)init;

/**
 downsize image

 @param sourceImage source image
 @param options operation options, use the default options if nil
 @param progress progress handle
 @param completed completed handle, called the on main thread, called immediately if operation init fail
 @return downsize operation key, Nil if the operation init fail
 */
- (nullable NKGiantImageDownsizeKey)downsizeImage:(UIImage *)sourceImage options:(nullable NKGiantImageDownsizeOptions *)options progress:(nullable NKGiantImageDownsizeProgress)progress completed:(NKGiantImageDownsizeCompleted)completed;


/**
 cancel downsize operation by downsize key

 @param key downsize key
 @return True, if the operation is found and is executing, otherwise false
 */
- (BOOL)cancelOperationWithKey:(NKGiantImageDownsizeKey)key;
- (void)cancelAllDownsizeOperations;

@end

NS_ASSUME_NONNULL_END
