//
//  NKGiantImageView.m
//  NKGiantImageKit
//
//  Created by Near Kong on 2019/10/4.
//  Copyright © 2019 Near Kong. All rights reserved.
//

#import "NKGiantImageView.h"

@interface NKGiantImageView ()

@property (nonatomic) CGRect imageRect;

// self.frame and self.contentMode must be used from main thread only
@property (nonatomic) CGRect drawFrame;
@property (nonatomic) UIViewContentMode drawContentMode;

@end


@implementation NKGiantImageView

+ (Class)layerClass {
    return [CATiledLayer class];
}

- (instancetype)initWithImage:(UIImage *)image {
    self = [super init];
    if (self) {
        self.image = image;
        self.giantContentMode = NKGiantImageContentModeDefault;
    }
    return self;
}

- (instancetype)init {
    return [self initWithImage:nil];
}

#pragma mark property
- (void)setGiantContentMode:(NKGiantImageContentMode)giantContentMode {
    CATiledLayer *tiledLayer = (CATiledLayer *)[self layer];
    
    // levelsOfDetail and levelsOfDetailBias determine how
    // the layer is rendered at different zoom levels.  This
    // only matters while the view is zooming, since once the
    // the view is done zooming a new TiledImageView is created
    // at the correct size and scale.
    switch (giantContentMode) {
        case NKGiantImageContentModeLow:
        case NKGiantImageContentModeDefault:
            tiledLayer.levelsOfDetail = 4;
            tiledLayer.levelsOfDetailBias = 4;
            tiledLayer.tileSize = CGSizeMake(512.0, 512.0);
            break;
        case NKGiantImageContentModeHigh:
            tiledLayer.levelsOfDetail = 16;
            tiledLayer.levelsOfDetailBias = 16;
            tiledLayer.tileSize = CGSizeMake(256, 256);
            break;
    }
}

- (void)setImage:(UIImage *)image {
    if (image) {
        _imageRect = CGRectMake(0.0, 0.0, CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
    } else {
        _imageRect = CGRectZero;
    }
    _image = image;
    [self setNeedsDisplay];
}

- (void)setFrame:(CGRect)frame {
    _drawFrame = frame;
    [super setFrame:frame];
}

- (void)setContentMode:(UIViewContentMode)contentMode {
    _drawContentMode = contentMode;
    [super setContentMode:contentMode];
    [self setNeedsDisplay];
}

#pragma mark drawRect
- (void)drawRect:(CGRect)rect {
    CGFloat widthScale = 0;
    CGFloat heightScale = 0;
    CGRect imageRect = _imageRect;
    if (_imageRect.size.width > CGFLOAT_MIN && _imageRect.size.height > CGFLOAT_MIN) {
        widthScale = _drawFrame.size.width / _imageRect.size.width;
        heightScale = _drawFrame.size.height / _imageRect.size.height;
        CGRect frame = _drawFrame;
        switch (_drawContentMode) {
            case UIViewContentModeScaleAspectFit: {
                if (widthScale < heightScale) {
                    heightScale = widthScale;
                    imageRect.origin.y = (frame.size.height / heightScale - imageRect.size.height) / 2;
                } else {
                    widthScale = heightScale;
                    imageRect.origin.x = (frame.size.width / widthScale - imageRect.size.width) / 2;
                }
            }
                break;
            case UIViewContentModeScaleAspectFill: {
                if (widthScale > heightScale) {
                    heightScale = widthScale;
                    imageRect.origin.y = (frame.size.height / heightScale - imageRect.size.height) / 2;
                } else {
                    widthScale = heightScale;
                    imageRect.origin.x = (frame.size.width / widthScale - imageRect.size.width) / 2;
                }
            }
                break;
            default:
                break;
        }
    }
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    // Scale the context so that the image is rendered
    // at the correct size for the zoom level.
    CGContextScaleCTM(context, widthScale, heightScale);
    CGContextDrawImage(context, imageRect, _image.CGImage);
    CGContextRestoreGState(context);
}

@end
