//
//  MUImageDecoder.m
//  MUKit_Example
//
//  Created by Jekity on 2018/7/30.
//  Copyright © 2018年 Jeykit. All rights reserved.
//

#import "MUImageDecoder.h"

#ifdef FLYIMAGE_WEBP
#import "webp/decode.h"
#endif

static void __ReleaseAsset(void* info, const void* data, size_t size)
{
    if (info != NULL) {
        CFRelease(info); // will cause dealloc of FlyImageDataFile
    }
}

#ifdef FLYIMAGE_WEBP
// This gets called when the UIImage gets collected and frees the underlying image.
static void free_image_data(void* info, const void* data, size_t size)
{
    if (info != NULL) {
        WebPFreeDecBuffer(&(((WebPDecoderConfig*)info)->output));
        free(info);
    }
    
    if (data != NULL) {
        free((void*)data);
    }
}
#endif

@implementation MUImageDecoder

- (UIImage*)iconImageWithBytes:(void*)bytes
                        offset:(size_t)offset
                        length:(size_t)length
                      drawSize:(CGSize)drawSize
{
    
    // Create CGImageRef whose backing store *is* the mapped image table entry. We avoid a memcpy this way.
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, bytes + offset, length, __ReleaseAsset);
    
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
    NSInteger bitsPerComponent = 8;
    NSInteger bitsPerPixel = 4 * 8;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    static NSInteger bytesPerPixel = 4;
    static float kAlignment = 64;
    CGFloat screenScale = [MUImageCacheUtils contentsScale];
    size_t bytesPerRow = ceil((drawSize.width * screenScale * bytesPerPixel) / kAlignment) * kAlignment;
    
    CGImageRef imageRef = CGImageCreate(drawSize.width * screenScale,
                                        drawSize.height * screenScale,
                                        bitsPerComponent,
                                        bitsPerPixel,
                                        bytesPerRow,
                                        colorSpace,
                                        bitmapInfo,
                                        dataProvider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    
    CGDataProviderRelease(dataProvider);
    CGColorSpaceRelease(colorSpace);
    
    if (imageRef == nil) {
        return nil;
    }
    
    UIImage *image = [[UIImage alloc]initWithCGImage:imageRef];
    CGImageRelease(imageRef);
    
    return image;
}


- (CGImageRef)imageRefWithFile:(void*)file
                   contentType:(MUImageContentType)contentType
                         bytes:(void*)bytes
                        length:(size_t)length
{
    if (contentType == MUImageContentTypeUnknown || contentType == MUImageContentTypeGif || contentType == MUImageContentTypeTiff) {
        return nil;
    }
    
    // Create CGImageRef whose backing store *is* the mapped image table entry. We avoid a memcpy this way.
    CGImageRef imageRef = nil;
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(file, bytes, length, __ReleaseAsset);
    if (contentType == MUImageContentTypeJPEG) {
        CFRetain(file);
        static CGDataProviderRef newDataProvider = nil;
        newDataProvider = dataProvider;
        if (newDataProvider) {
            imageRef = CGImageCreateWithJPEGDataProvider(newDataProvider, NULL, YES, kCGRenderingIntentDefault);
        }
        newDataProvider = nil;
        
    } else if (contentType == MUImageContentTypePNG) {
        CFRetain(file);
        static CGDataProviderRef newDataProvider = nil;
        newDataProvider = dataProvider;
        if (newDataProvider != nil) {
            imageRef = CGImageCreateWithPNGDataProvider(newDataProvider, NULL, YES, kCGRenderingIntentDefault);
        }
         newDataProvider = nil;
        
    } else if (contentType == MUImageContentTypeWebP) {
#ifdef FLYIMAGE_WEBP
        // `WebPGetInfo` weill return image width and height
        int width = 0, height = 0;
        if (!WebPGetInfo(bytes, length, &width, &height)) {
            return nil;
        }
        
        WebPDecoderConfig* config = malloc(sizeof(WebPDecoderConfig));
        if (!WebPInitDecoderConfig(config)) {
            return nil;
        }
        
        config->options.no_fancy_upsampling = 1;
        config->options.bypass_filtering = 1;
        config->options.use_threads = 1;
        config->output.colorspace = MODE_RGBA;
        
        // Decode the WebP image data into a RGBA value array
        VP8StatusCode decodeStatus = WebPDecode(bytes, length, config);
        if (decodeStatus != VP8_STATUS_OK) {
            return nil;
        }
        
        // Construct UIImage from the decoded RGBA value array
        uint8_t* data = WebPDecodeRGBA(bytes, length, &width, &height);
        dataProvider = CGDataProviderCreateWithData(config, data, config->options.scaled_width * config->options.scaled_height * 4, free_image_data);
        
        CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
        CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaLast;
        CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
        
        imageRef = CGImageCreate(width, height, 8, 32, 4 * width, colorSpaceRef, bitmapInfo, dataProvider, NULL, YES, renderingIntent);
#endif
    }
    if (dataProvider != nil) {
        CGDataProviderRelease(dataProvider);
    }
    return imageRef;
}


- (UIImage *)decompressedImageWithImage:(UIImage *)image
                                   data:(NSData *__autoreleasing  _Nullable *)data
                                options:(nullable NSDictionary<NSString*, NSObject*>*)optionsDict {
    // GIF do not decompress
    return image;
}

- (UIImage*)imageWithFile:(void*)file
              contentType:(MUImageContentType)contentType
                    bytes:(void*)bytes
                   length:(size_t)length
                 drawSize:(CGSize)drawSize
          contentsGravity:(NSString* const)contentsGravity
             cornerRadius:(CGFloat)cornerRadius
{
    if (contentType == MUImageContentTypeGif) {
      NSData *data = [NSData dataWithBytes:bytes length:length];
//        NSLog(@"data====%ld",data.length);
       return [self animatedGIFWithData:data];
    }
   
    CGImageRef imageRef = [self imageRefWithFile:file contentType:contentType bytes:bytes length:length];
    if (imageRef == nil) {
        return nil;
    }
    
    
   
    CGSize imageSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
    CGFloat contentsScale = 1;
    if (drawSize.width < imageSize.width && drawSize.height < imageSize.height) {
        contentsScale = [MUImageCacheUtils contentsScale];
    }
    CGSize contextSize = CGSizeMake(drawSize.width * contentsScale, drawSize.height * contentsScale);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);
    
    int infoMask = (bitmapInfo & kCGBitmapAlphaInfoMask);
    BOOL anyNonAlpha = (infoMask == kCGImageAlphaNone || infoMask == kCGImageAlphaNoneSkipFirst || infoMask == kCGImageAlphaNoneSkipLast);
    
    // CGBitmapContextCreate doesn't support kCGImageAlphaNone with RGB.
    // https://developer.apple.com/library/mac/#qa/qa1037/_index.html
    if (cornerRadius > 0) {
        bitmapInfo &= kCGImageAlphaPremultipliedLast;
    } else if (infoMask == kCGImageAlphaNone && CGColorSpaceGetNumberOfComponents(colorSpace) > 1) {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
        
        // Set noneSkipFirst.
        bitmapInfo |= kCGImageAlphaNoneSkipFirst;
    }
    // Some PNGs tell us they have alpha but only 3 components. Odd.
    else if (!anyNonAlpha && CGColorSpaceGetNumberOfComponents(colorSpace) == 3) {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
        bitmapInfo |= kCGImageAlphaPremultipliedFirst;
    }
    
    // It calculates the bytes-per-row based on the bitsPerComponent and width arguments.
    static NSInteger bytesPerPixel = 4;
    static float kAlignment = 64;
    size_t bytesPerRow = ceil((contextSize.width * bytesPerPixel) / kAlignment) * kAlignment;
    
    CGContextRef context = CGBitmapContextCreate(NULL, contextSize.width, contextSize.height, CGImageGetBitsPerComponent(imageRef), bytesPerRow, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    
    // If failed, return undecompressed image
    if (!context) {
        UIImage* image = [[UIImage alloc] initWithCGImage:imageRef
                                                    scale:contentsScale
                                              orientation:UIImageOrientationUp];
        CGImageRelease(imageRef);
        return image;
    }
    
    CGContextScaleCTM(context, contentsScale, contentsScale);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    
    CGRect contextBounds = CGRectMake(0, 0, drawSize.width, drawSize.height);
    
    // Clip to a rounded rect
    if (cornerRadius > 0) {
        CGPathRef path = _FICDCreateRoundedRectPath(contextBounds, cornerRadius);
        CGContextAddPath(context, path);
        CFRelease(path);
        CGContextEOClip(context);
    }
    CFRetain(imageRef);
    CFRetain(context);
    NSString *contentGra = [contentsGravity copy];
    if (context&&imageRef) {
        CGContextDrawImage(context, _MUImageCalcDrawBounds(imageSize,
                                                           drawSize,
                                                           contentGra),
                           imageRef);
    }
    
    CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
    CFRelease(imageRef);
    CFRelease(context);
    CGContextRelease(context);
    
    UIImage* decompressedImage = [UIImage imageWithCGImage:decompressedImageRef
                                                     scale:contentsScale
                                               orientation:UIImageOrientationUp];
    
    CGImageRelease(decompressedImageRef);
    CGImageRelease(imageRef);
    
    return decompressedImage;
}

#ifdef FLYIMAGE_WEBP
- (UIImage*)imageWithWebPData:(NSData*)imageData hasAlpha:(BOOL*)hasAlpha
{
    
    // `WebPGetInfo` weill return image width and height
    int width = 0, height = 0;
    if (!WebPGetInfo(imageData.bytes, imageData.length, &width, &height)) {
        return nil;
    }
    
    WebPDecoderConfig* config = malloc(sizeof(WebPDecoderConfig));
    if (!WebPInitDecoderConfig(config)) {
        return nil;
    }
    
    config->options.no_fancy_upsampling = 1;
    config->options.bypass_filtering = 1;
    config->options.use_threads = 1;
    config->output.colorspace = MODE_RGBA;
    
    // Decode the WebP image data into a RGBA value array
    VP8StatusCode decodeStatus = WebPDecode(imageData.bytes, imageData.length, config);
    if (decodeStatus != VP8_STATUS_OK) {
        return nil;
    }
    
    // set alpha value
    if (hasAlpha != nil) {
        *hasAlpha = config->input.has_alpha;
    }
    
    // Construct UIImage from the decoded RGBA value array
    uint8_t* data = WebPDecodeRGBA(imageData.bytes, imageData.length, &width, &height);
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(config, data, config->options.scaled_width * config->options.scaled_height * 4, free_image_data);
    
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaLast;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    
    CGImageRef imageRef = CGImageCreate(width, height, 8, 32, 4 * width, colorSpaceRef, bitmapInfo, dataProvider, NULL, YES, renderingIntent);
    UIImage* decodeImage = [UIImage imageWithCGImage:imageRef];
    
    UIGraphicsBeginImageContextWithOptions(decodeImage.size, !config->input.has_alpha, 1);
    [decodeImage drawInRect:CGRectMake(0, 0, decodeImage.size.width, decodeImage.size.height)];
    UIImage* decompressedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return decompressedImage;
}
#endif

#pragma mark-GIF
- (UIImage *)animatedGIFWithData:(NSData *)data {
    if (!data) {
        return nil;
    }
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    
    size_t count = CGImageSourceGetCount(source);
    
    UIImage *animatedImage;
    
    if (count <= 1) {
        animatedImage = [[UIImage alloc] initWithData:data];
    }
    else {
        NSMutableArray *images = [NSMutableArray array];
        
        NSUInteger duration = 0.0f;
        
        for (size_t i = 0; i < count; i++) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
            
            duration += [self frameDurationAtIndex:i source:source];
            
            [images addObject:[UIImage imageWithCGImage:image scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp]];
            
            CGImageRelease(image);
        }
        
        if (!duration) {
            duration = (1.0f / 10.0f) * count;
        }
        
        animatedImage = [UIImage animatedImageWithImages:images duration:duration];
    }
    
    CFRelease(source);
    
    return animatedImage;
}


- (float)frameDurationAtIndex:(NSUInteger)index source:(CGImageSourceRef)source {
    float frameDuration = 0.1f;
    CFDictionaryRef cfFrameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil);
    if (!cfFrameProperties) {
        return frameDuration;
    }
    NSDictionary *frameProperties = (__bridge NSDictionary *)cfFrameProperties;
    NSDictionary *gifProperties = frameProperties[(NSString *)kCGImagePropertyGIFDictionary];
    
    NSNumber *delayTimeUnclampedProp = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    if (delayTimeUnclampedProp != nil) {
        frameDuration = [delayTimeUnclampedProp floatValue];
    } else {
        NSNumber *delayTimeProp = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
        if (delayTimeProp != nil) {
            frameDuration = [delayTimeProp floatValue];
        }
    }
    
    // Many annoying ads specify a 0 duration to make an image flash as quickly as possible.
    // We follow Firefox's behavior and use a duration of 100 ms for any frames that specify
    // a duration of <= 10 ms. See <rdar://problem/7689300> and <http://webkit.org/b/36082>
    // for more information.
    
    if (frameDuration < 0.011f) {
        frameDuration = 0.100f;
    }
    
    CFRelease(cfFrameProperties);
    return frameDuration;
}

@end
