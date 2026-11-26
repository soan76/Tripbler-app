package com.tripbler.backend.translation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Arrays;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.Test;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;

class PhotoImageInspectorTest {

    private final PhotoImageInspector inspector = new PhotoImageInspector();

    private static byte[] encode(String format, int width, int height) throws IOException {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, format, out);
        return out.toByteArray();
    }

    @Test
    void inspect_readsSizeFromJpegHeader() throws IOException {
        PhotoImageInspector.Dimensions size = inspector.inspect(encode("jpg", 1536, 2048));

        assertThat(size).isEqualTo(new PhotoImageInspector.Dimensions(1536, 2048));
    }

    @Test
    void inspect_rejectsPng() throws IOException {
        byte[] png = encode("png", 100, 100);

        assertThatThrownBy(() -> inspector.inspect(png))
            .isInstanceOfSatisfying(BusinessException.class,
                e -> assertThat(e.getErrorCode()).isEqualTo(ErrorCode.INVALID_REQUEST));
    }

    @Test
    void inspect_rejectsTruncatedBytes() throws IOException {
        byte[] truncated = Arrays.copyOf(encode("jpg", 200, 200), 8);

        assertThatThrownBy(() -> inspector.inspect(truncated))
            .isInstanceOfSatisfying(BusinessException.class,
                e -> assertThat(e.getErrorCode()).isEqualTo(ErrorCode.INVALID_REQUEST));
    }
}
