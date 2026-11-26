package com.tripbler.backend.translation.service;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Iterator;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.MemoryCacheImageInputStream;

import org.springframework.stereotype.Component;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;

/** 사진이 JPEG인지 확인하고 머리 정보만 읽어 크기를 구한다. 이미지를 통째로 디코딩하지 않으며, 바이트를 로그에 남기지 않는다. */
@Component
public class PhotoImageInspector {

    private static final String INVALID_MESSAGE = "JPEG 사진만 보낼 수 있습니다.";

    public record Dimensions(int width, int height) {
    }

    public Dimensions inspect(byte[] image) {
        if (!hasJpegSignature(image)) {
            throw invalid(null);
        }
        try (ImageInputStream input = new MemoryCacheImageInputStream(new ByteArrayInputStream(image))) {
            Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName("jpeg");
            if (!readers.hasNext()) {
                throw invalid(null);
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(input, true, true);
                int width = reader.getWidth(0);
                int height = reader.getHeight(0);
                if (width <= 0 || height <= 0) {
                    throw invalid(null);
                }
                return new Dimensions(width, height);
            } finally {
                reader.dispose();
            }
        } catch (BusinessException e) {
            throw e;
        } catch (IOException | RuntimeException e) {
            throw invalid(e);
        }
    }

    private static boolean hasJpegSignature(byte[] image) {
        return image != null
            && image.length >= 3
            && (image[0] & 0xFF) == 0xFF
            && (image[1] & 0xFF) == 0xD8
            && (image[2] & 0xFF) == 0xFF;
    }

    private static BusinessException invalid(Throwable cause) {
        return cause == null
            ? new BusinessException(ErrorCode.INVALID_REQUEST, INVALID_MESSAGE)
            : new BusinessException(ErrorCode.INVALID_REQUEST, INVALID_MESSAGE, cause);
    }
}
