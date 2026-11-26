package com.tripbler.backend.translation.client;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.ObjectMappers;
import com.anthropic.models.messages.StructuredMessage;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;

/**
 * 실제 Claude로 사진 번역을 측정한다(계획 Task 14). <b>유료 호출이며 사진이 Anthropic으로 전송된다.</b>
 *
 * <p>기본 빌드에서는 건너뛴다. 아래 환경 변수를 모두 넣었을 때만 실행한다.
 * <ul>
 *   <li>{@code ANTHROPIC_LIVE_TEST=true}: 실행 스위치</li>
 *   <li>{@code ANTHROPIC_API_KEY}: API 키</li>
 *   <li>{@code PHOTO_LIVE_SAMPLES}: 시료 폴더. 시료마다 {@code 이름.jpg}(앱의 PhotoNormalizer로 정리한 사진)와
 *       {@code 이름.json}(앱이 보내는 {@code request} 파트와 같은 형식)을 둔다. 저장소에 넣지 않는다.</li>
 *   <li>{@code PHOTO_LIVE_MODEL}(선택): 모델 이름. 없으면 운영 기본값과 같은 {@code claude-sonnet-5-5}.</li>
 *   <li>{@code PHOTO_LIVE_OUT}(선택): 결과 폴더. 없으면 {@code build/photo-live}(git에 들어가지 않음).</li>
 * </ul>
 *
 * <p>실행: {@code ANTHROPIC_LIVE_TEST=true ./gradlew test --tests "*ClaudePhotoTranslationLiveIT"}.
 * 시료별 결과 JSON과 요약 CSV(지연, 입력·출력 토큰)를 결과 폴더에 쓴다. 번역이 맞는지, 지어낸 글자가 없는지는
 * 사람이 결과 파일을 보고 {@code docs/translation-photo-measurements.md}에 판정을 적는다. 이 테스트는 응답 형식만
 * 확인한다.
 */
@EnabledIfEnvironmentVariable(named = "ANTHROPIC_LIVE_TEST", matches = "true")
class ClaudePhotoTranslationLiveIT {

    private static final String DEFAULT_MODEL = "claude-sonnet-5-5";

    // 운영 클라이언트의 최대 시간 제한과 같다. 측정을 위해 재시도는 하지 않는다(운영과 같음).
    private static final Duration TIMEOUT = Duration.ofSeconds(90);

    private static final JsonMapper JSON = ObjectMappers.jsonMapper();

    @Test
    void measureSamples() throws IOException {
        String apiKey = requiredEnv("ANTHROPIC_API_KEY");
        Path samples = Path.of(requiredEnv("PHOTO_LIVE_SAMPLES"));
        String model = envOrDefault("PHOTO_LIVE_MODEL", DEFAULT_MODEL);
        Path out = Path.of(envOrDefault("PHOTO_LIVE_OUT", "build/photo-live")).resolve(model);
        Files.createDirectories(out);

        AnthropicClient sdk = AnthropicOkHttpClient.builder()
            .apiKey(apiKey)
            .timeout(TIMEOUT)
            .maxRetries(0)
            .build();

        List<Path> photos = listSamples(samples);
        assertThat(photos).as("시료 폴더에 .jpg와 같은 이름의 .json이 있어야 한다: " + samples).isNotEmpty();

        List<String> rows = new ArrayList<>();
        rows.add("sample,paragraphs,elapsedMs,inputTokens,outputTokens,returned,uncertain,error");
        List<Long> latencies = new ArrayList<>();

        for (Path photo : photos) {
            String name = baseName(photo);
            PhotoTranslationRequest request = JSON.readValue(
                Files.readString(photo.resolveSibling(name + ".json"), StandardCharsets.UTF_8),
                PhotoTranslationRequest.class
            );
            byte[] jpeg = Files.readAllBytes(photo);

            long[] usage = {-1, -1};
            ClaudePhotoTranslationClient client = new ClaudePhotoTranslationClient(
                (params, options) -> {
                    StructuredMessage<ClaudePhotoTranslationClient.Output> response =
                        sdk.messages().create(params, options);
                    usage[0] = response.usage().inputTokens();
                    usage[1] = response.usage().outputTokens();
                    return response;
                },
                model
            );

            long startedAt = System.nanoTime();
            String error = "";
            PhotoTranslationClient.Result result = null;

            try {
                result = client.translate(jpeg, "image/jpeg", request.paragraphs(),
                    request.sourceLanguageCode(), request.targetLanguageCode());
            } catch (RuntimeException exception) {
                error = exception.getClass().getSimpleName();
            }

            long elapsedMs = Duration.ofNanos(System.nanoTime() - startedAt).toMillis();
            latencies.add(elapsedMs);

            int returned = 0;
            int uncertain = 0;

            if (result != null) {
                Set<String> requested = new HashSet<>();
                request.paragraphs().forEach(paragraph -> requested.add(paragraph.id()));

                for (PhotoTranslationClient.Paragraph paragraph : result.paragraphs()) {
                    assertThat(requested).as(name + ": 요청에 없는 문단 ID").contains(paragraph.id());
                    returned++;
                    if (paragraph.uncertain()) {
                        uncertain++;
                    }
                }

                writeResult(out.resolve(name + ".result.json"), request, result);
            }

            rows.add(String.join(",", name, String.valueOf(request.paragraphs().size()), String.valueOf(elapsedMs),
                String.valueOf(usage[0]), String.valueOf(usage[1]), String.valueOf(returned),
                String.valueOf(uncertain), error));
        }

        rows.add("# p50Ms=" + percentile(latencies, 50) + " p90Ms=" + percentile(latencies, 90)
            + " model=" + model + " samples=" + photos.size());
        Files.write(out.resolve("summary.csv"), rows, StandardCharsets.UTF_8);
    }

    // 사람이 원문(OCR)과 AI 결과를 나란히 보고 판정할 수 있게 문단별로 묶어 쓴다.
    private static void writeResult(
        Path file,
        PhotoTranslationRequest request,
        PhotoTranslationClient.Result result
    ) throws IOException {
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("detectedLanguageCode", result.detectedLanguageCode());
        root.put("ocr", request.paragraphs());
        root.put("ai", result.paragraphs());
        Files.writeString(file, JSON.copy().enable(SerializationFeature.INDENT_OUTPUT).writeValueAsString(root),
            StandardCharsets.UTF_8);
    }

    private static List<Path> listSamples(Path folder) throws IOException {
        try (Stream<Path> files = Files.list(folder)) {
            return files
                .filter(path -> path.getFileName().toString().toLowerCase().endsWith(".jpg"))
                .filter(path -> Files.exists(path.resolveSibling(baseName(path) + ".json")))
                .sorted(Comparator.comparing(Path::toString))
                .toList();
        }
    }

    private static String baseName(Path photo) {
        String file = photo.getFileName().toString();
        return file.substring(0, file.lastIndexOf('.'));
    }

    private static long percentile(List<Long> values, int percent) {
        List<Long> sorted = values.stream().sorted().toList();
        int index = (int) Math.ceil(percent / 100.0 * sorted.size()) - 1;
        return sorted.get(Math.max(0, index));
    }

    private static String requiredEnv(String name) {
        String value = System.getenv(name);
        assertThat(value).as("환경 변수 " + name + "이(가) 필요하다").isNotBlank();
        return value;
    }

    private static String envOrDefault(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }
}
