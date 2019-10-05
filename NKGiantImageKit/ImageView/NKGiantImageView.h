//
//  NKGiantImageView.h
//  NKGiantImageKit
//
//  Created by Near Kong on 2019/10/4.
//  Copyright © 2019 Near Kong. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NKGiantImageContentMode) {
    NKGiantImageContentModeLow,
    NKGiantImageContentModeDefault,
    NKGiantImageContentModeHigh,
};

@interface NKGiantImageView : UIView

- (instancetype)initWithImage:(nullable UIImage *)image;

@property (nonatomic) NKGiantImageContentMode giantContentMode;

@property (nonatomic, nullable) UIImage *image;

@end

NS_ASSUME_NONNULL_END
