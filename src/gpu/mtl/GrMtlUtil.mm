/*
 * Copyright 2017 Google Inc.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include "GrMtlUtil.h"

#include "GrTypesPriv.h"
#include "GrSurface.h"
#include "mtl/GrMtlGpu.h"
#include "mtl/GrMtlTexture.h"
#include "mtl/GrMtlRenderTarget.h"
#include "SkSLCompiler.h"

#import <Metal/Metal.h>

#define PRINT_MSL 0 // print out the MSL code generated

bool GrPixelConfigToMTLFormat(GrPixelConfig config, MTLPixelFormat* format) {
    MTLPixelFormat dontCare;
    if (!format) {
        format = &dontCare;
    }

    switch (config) {
        case kUnknown_GrPixelConfig:
            return false;
        case kRGBA_8888_GrPixelConfig:
            *format = MTLPixelFormatRGBA8Unorm;
            return true;
        case kRGB_888_GrPixelConfig:
            // TODO: MTLPixelFormatRGB8Unorm
            return false;
        case kBGRA_8888_GrPixelConfig:
            *format = MTLPixelFormatBGRA8Unorm;
            return true;
        case kSRGBA_8888_GrPixelConfig:
            *format = MTLPixelFormatRGBA8Unorm_sRGB;
            return true;
        case kSBGRA_8888_GrPixelConfig:
            *format = MTLPixelFormatBGRA8Unorm_sRGB;
            return true;
        case kRGBA_1010102_GrPixelConfig:
            *format = MTLPixelFormatRGB10A2Unorm;
            return true;
        case kRGB_565_GrPixelConfig:
#ifdef SK_BUILD_FOR_IOS
            *format = MTLPixelFormatB5G6R5Unorm;
            return true;
#else
            return false;
#endif
        case kRGBA_4444_GrPixelConfig:
#ifdef SK_BUILD_FOR_IOS
            *format = MTLPixelFormatABGR4Unorm;
            return true;
#else
            return false;
#endif
        case kAlpha_8_GrPixelConfig: // fall through
        case kAlpha_8_as_Red_GrPixelConfig:
            *format = MTLPixelFormatR8Unorm;
            return true;
        case kAlpha_8_as_Alpha_GrPixelConfig:
            return false;
        case kGray_8_GrPixelConfig: // fall through
        case kGray_8_as_Red_GrPixelConfig:
            *format = MTLPixelFormatR8Unorm;
            return true;
        case kGray_8_as_Lum_GrPixelConfig:
            return false;
        case kRGBA_float_GrPixelConfig:
            *format = MTLPixelFormatRGBA32Float;
            return true;
        case kRG_float_GrPixelConfig:
            *format = MTLPixelFormatRG32Float;
            return true;
        case kRGBA_half_GrPixelConfig:
            *format = MTLPixelFormatRGBA16Float;
            return true;
        case kAlpha_half_GrPixelConfig: // fall through
        case kAlpha_half_as_Red_GrPixelConfig:
            *format = MTLPixelFormatR16Float;
            return true;
    }
    SK_ABORT("Unexpected config");
    return false;
}

GrPixelConfig GrMTLFormatToPixelConfig(MTLPixelFormat format) {
    switch (format) {
        case MTLPixelFormatRGBA8Unorm:
            return kRGBA_8888_GrPixelConfig;
        case MTLPixelFormatBGRA8Unorm:
            return kBGRA_8888_GrPixelConfig;
        case MTLPixelFormatRGBA8Unorm_sRGB:
            return kSRGBA_8888_GrPixelConfig;
        case MTLPixelFormatBGRA8Unorm_sRGB:
            return kSBGRA_8888_GrPixelConfig;
        case MTLPixelFormatRGB10A2Unorm:
            return kRGBA_1010102_GrPixelConfig;
#ifdef SK_BUILD_FOR_IOS
        case MTLPixelFormatB5G6R5Unorm:
            return kRGB_565_GrPixelConfig;
        case MTLPixelFormatABGR4Unorm:
            return kRGBA_4444_GrPixelConfig;
#endif
        case MTLPixelFormatR8Unorm:
            // We currently set this to be Alpha_8 and have no way to go to Gray_8
            return kAlpha_8_GrPixelConfig;
        case MTLPixelFormatRGBA32Float:
            return kRGBA_float_GrPixelConfig;
        case MTLPixelFormatRG32Float:
            return kRG_float_GrPixelConfig;
        case MTLPixelFormatRGBA16Float:
            return kRGBA_half_GrPixelConfig;
        case MTLPixelFormatR16Float:
            return kAlpha_half_GrPixelConfig;
        default:
            return kUnknown_GrPixelConfig;
    }
}

id<MTLTexture> GrGetMTLTexture(const void* mtlTexture, GrWrapOwnership wrapOwnership) {
    if (GrWrapOwnership::kAdopt_GrWrapOwnership == wrapOwnership) {
        return (__bridge_transfer id<MTLTexture>)mtlTexture;
    } else {
        return (__bridge id<MTLTexture>)mtlTexture;
    }
}

const void* GrGetPtrFromId(id idObject) {
    return (__bridge const void*)idObject;
}

const void* GrReleaseId(id idObject) {
    return (__bridge_retained const void*)idObject;
}

MTLTextureDescriptor* GrGetMTLTextureDescriptor(id<MTLTexture> mtlTexture) {
    MTLTextureDescriptor* texDesc = [[MTLTextureDescriptor alloc] init];
    texDesc.textureType = mtlTexture.textureType;
    texDesc.pixelFormat = mtlTexture.pixelFormat;
    texDesc.width = mtlTexture.width;
    texDesc.height = mtlTexture.height;
    texDesc.depth = mtlTexture.depth;
    texDesc.mipmapLevelCount = mtlTexture.mipmapLevelCount;
    texDesc.arrayLength = mtlTexture.arrayLength;
    texDesc.sampleCount = mtlTexture.sampleCount;
    texDesc.usage = mtlTexture.usage;
    return texDesc;
}

#if PRINT_MSL
void print_msl(const char* source) {
    SkTArray<SkString> lines;
    SkStrSplit(source, "\n", kStrict_SkStrSplitMode, &lines);
    for (int i = 0; i < lines.count(); i++) {
        SkString& line = lines[i];
        line.prependf("%4i\t", i + 1);
        SkDebugf("%s\n", line.c_str());
    }
}
#endif

id<MTLLibrary> GrCompileMtlShaderLibrary(const GrMtlGpu* gpu,
                                         const char* shaderString,
                                         SkSL::Program::Kind kind,
                                         const SkSL::Program::Settings& settings,
                                         SkSL::Program::Inputs* outInputs) {
    std::unique_ptr<SkSL::Program> program =
            gpu->shaderCompiler()->convertProgram(kind,
                                                  SkSL::String(shaderString),
                                                  settings);

    if (!program) {
        SkDebugf("SkSL error:\n%s\n", gpu->shaderCompiler()->errorText().c_str());
        SkASSERT(false);
    }

    *outInputs = program->fInputs;
    SkSL::String code;
    if (!gpu->shaderCompiler()->toMetal(*program, &code)) {
        SkDebugf("%s\n", gpu->shaderCompiler()->errorText().c_str());
        SkASSERT(false);
        return nil;
    }
    NSString* mtlCode = [[NSString alloc] initWithCString: code.c_str()
                                                 encoding: NSASCIIStringEncoding];
#if PRINT_MSL
    print_msl([mtlCode cStringUsingEncoding: NSASCIIStringEncoding]);
#endif

    MTLCompileOptions* defaultOptions = [[MTLCompileOptions alloc] init];
    NSError* error = nil;
    id<MTLLibrary> compiledLibrary = [gpu->device() newLibraryWithSource: mtlCode
                                                                 options: defaultOptions
                                                                   error: &error];
    if (error) {
        SkDebugf("Error compiling MSL shader: %s\n",
                 [[error localizedDescription] cStringUsingEncoding: NSASCIIStringEncoding]);
        return nil;
    }
    return compiledLibrary;
}

id<MTLTexture> GrGetMTLTextureFromSurface(GrSurface* surface, bool doResolve) {
    id<MTLTexture> mtlTexture = nil;

    GrMtlRenderTarget* renderTarget = static_cast<GrMtlRenderTarget*>(surface->asRenderTarget());
    GrMtlTexture* texture;
    if (renderTarget) {
        if (doResolve) {
            // TODO: do resolve and set mtlTexture to resolved texture. As of now, we shouldn't
            // have any multisampled render targets.
            SkASSERT(false);
        } else {
            mtlTexture = renderTarget->mtlRenderTexture();
        }
    } else {
        texture = static_cast<GrMtlTexture*>(surface->asTexture());
        if (texture) {
            mtlTexture = texture->mtlTexture();
        }
    }
    return mtlTexture;
}
