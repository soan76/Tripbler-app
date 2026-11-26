package com.tripbler.backend.translation.client;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

import org.junit.jupiter.api.Tag;
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
 * <p>{@code live} 태그라 일반 {@code ./gradlew test}에서는 빠지고 {@code ./gradlew liveTest}로만 돈다. 그때도 아래 환경
 * 변수를 모두 넣었을 때만 실행한다.
 * <ul>
 *   <li>{@code ANTHROPIC_LIVE_TEST=true}: 실행 스위치</li>
 *   <li>{@code ANTHROPIC_API_KEY}: API 키. {@code ANTHROPIC_LOG}가 설정돼 있으면 실행하지 않는다.</li>
 *   <li>{@code PHOTO_LIVE_SAMPLES}: 시료 폴더. 시료마다 {@code 이름.jpg}(앱의 PhotoNormalizer로 정리한 사진)와
 *       {@code 이름.json}(앱이 보내는 {@code request} 파트와 같은 형식)을 둔다. 저장소 밖에 둔다(저장소 안이면
 *       빌드 폴더 아래만 허용).</li>
 *   <li>{@code PHOTO_LIVE_MODEL}(선택): 모델 이름. 없으면 운영 기본값과 같은 {@code claude-sonnet-5-5}.</li>
 *   <li>{@code PHOTO_LIVE_RUN}(선택): 실행 이름. 없으면 UTC 시각.</li>
 *   <li>{@code PHOTO_LIVE_OUT}(선택): 결과 폴더. 없으면 빌드 폴더의 {@code photo-live}. 저장소 안이면 빌드 폴더 아래만
 *       허용한다.</li>
 * </ul>
 *
 * <p>결과는 {@code <결과 폴더>/<모델>/<실행 이름>/}에 쓴다(이미 있으면 실패). 시료별 {@code 이름.result.json},
 * 시료마다 바로 덧붙이는 {@code samples.csv}(지연, 토큰, 돌려받은 문단 수, uncertain 수, 요청에 없는 문단 ID, 오류
 * 종류), 마지막에 항상 쓰는 {@code summary.csv}(p50·p90 등)다. 품질은 사람이 결과 파일을 보고
 * {@code docs/translation-photo-measurements.md}에 판정한다. 이 테스트는 모든 기록을 남긴 뒤 오류·요청에 없는
 * 문단 ID가 있었으면 실패한다.
 */
@Tag("live")
@EnabledIfEnvironmentVariable(named = "ANTHROPIC_LIVE_TEST", matches = "true")
class ClaudePhotoTranslationLiveIT {

    private static final String DEFAULT_MODEL = "claude-sonnet-5-5";

    // 운영 클라이언트의 최대 시간 제한과 같다. 측정을 위해 재시도는 하지 않는다(운영과 같음).
    private static final Duration TIMEOUT = Duration.ofSeconds(90);

    private static final JsonMapper JSON = ObjectMappers.jsonMapper();

    private static final List<String> SAMPLE_HEADER = List.of("sample", "paragraphs", "elapsedMs", "inputTokens",
        "outputTokens", "returned", "uncertain", "unknownIds", "error");

    @Test
    void measureSamples() throws IOException {
        // 키를 읽거나 클라이언트를 만들기 전에 거부한다.
        PhotoLiveRunFiles.rejectSdkLogging(System.getenv("ANTHROPIC_LOG"));

        String apiKey = requiredEnv("ANTHROPIC_API_KEY");
        Path buildDir = Path.of(System.getProperty("photoLive.buildDir", "build"));
        Path repoRoot = PhotoLiveRunFiles.findRepoRoot(Path.of(""));
        Path samples = PhotoLiveRunFiles.checkLocation(Path.of(requiredEnv("PHOTO_LIVE_SAMPLES")), repoRoot,
            buildDir, "PHOTO_LIVE_SAMPLES");
        Path outRoot = PhotoLiveRunFiles.checkLocation(
            Path.of(envOrDefault("PHOTO_LIVE_OUT", buildDir.resolve("photo-live").toString())), repoRoot, buildDir,
            "PHOTO_LIVE_OUT");
        String model = PhotoLiveRunFiles.safeName(envOrDefault("PHOTO_LIVE_MODEL", DEFAULT_MODEL),
            "PHOTO_LIVE_MODEL");
        String run = PhotoLiveRunFiles.runName(System.getenv("PHOTO_LIVE_RUN"), Instant.now());

        List<Path> photos = listSamples(samples);
        assertThat(photos).as("시료 폴더에 .jpg와 같은 이름의 .json이 있어야 한다: " + samples).isNotEmpty();

        Path out = PhotoLiveRunFiles.createRunDir(outRoot, model, run);
        Path sampleCsv = out.resolve("samples.csv");
        PhotoLiveRunFiles.appendRow(sampleCsv, SAMPLE_HEADER);

        AnthropicClient sdk = AnthropicOkHttpClient.builder()
            .apiKey(apiKey)
            .timeout(TIMEOUT)
            .maxRetries(0)
            .build();

        List<Long> latencies = new ArrayList<>();
        int failed = 0;
        int withUnknownIds = 0;

        try {
            for (Path photo : photos) {
                SampleResult result = measure(sdk, model, photo, out);
                PhotoLiveRunFiles.appendRow(sampleCsv, result.row());
                if (result.elapsedMs() >= 0) {
                    latencies.add(result.elapsedMs());
                }
                if (!result.error().isEmpty()) {
                    failed++;
                }
                if (!result.unknownIds().isEmpty()) {
                    withUnknownIds++;
                }
            }
        } finally {
            // 중간에 예외가 나도 요약은 남긴다.
            Files.write(out.resolve("summary.csv"), List.of(
                PhotoLiveRunFiles.csvRow(List.of("key", "value")),
                PhotoLiveRunFiles.csvRow(List.of("model", model)),
                PhotoLiveRunFiles.csvRow(List.of("run", run)),
                PhotoLiveRunFiles.csvRow(List.of("samples", String.valueOf(photos.size()))),
                PhotoLiveRunFiles.csvRow(List.of("measured", String.valueOf(latencies.size()))),
                PhotoLiveRunFiles.csvRow(List.of("failed", String.valueOf(failed))),
                PhotoLiveRunFiles.csvRow(List.of("withUnknownIds", String.valueOf(withUnknownIds))),
                PhotoLiveRunFiles.csvRow(List.of("p50Ms", String.valueOf(PhotoLiveRunFiles.percentile(latencies, 50)))),
                PhotoLiveRunFiles.csvRow(List.of("p90Ms", String.valueOf(PhotoLiveRunFiles.percentile(latencies, 90))))
            ), StandardCharsets.UTF_8);
        }

        assertThat(withUnknownIds).as("요청에 없는 문단 ID를 돌려준 시료 수(samples.csv의 unknownIds)").isZero();
    }

    /** 시료 하나를 측정한다. 시료 읽기·호출 실패는 예외로 끝내지 않고 error 열에 남긴다. */
    private static SampleResult measure(AnthropicClient sdk, String model, Path photo, Path out) {
        String name = baseName(photo);
        PhotoTranslationRequest request;
        byte[] jpeg;

        try {
            request = JSON.readValue(Files.readString(photo.resolveSibling(name + ".json"), StandardCharsets.UTF_8),
                PhotoTranslationRequest.class);
            jpeg = Files.readAllBytes(photo);
        } catch (IOException | RuntimeException exception) {
            return new SampleResult(name, -1, -1, -1, -1, 0, 0, Set.of(),
                "sample:" + exception.getClass().getSimpleName());
        }

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
        int returned = 0;
        int uncertain = 0;
        Set<String> unknownIds = new LinkedHashSet<>();

        if (result != null) {
            Set<String> requested = new LinkedHashSet<>();
            request.paragraphs().forEach(paragraph -> requested.add(paragraph.id()));

            for (PhotoTranslationClient.Paragraph paragraph : result.paragraphs()) {
                returned++;
                if (!requested.contains(paragraph.id())) {
                    unknownIds.add(String.valueOf(paragraph.id()));
                }
                if (paragraph.uncertain()) {
                    uncertain++;
                }
            }

            try {
                writeResult(out.resolve(name + ".result.json"), request, result);
            } catch (IOException | RuntimeException exception) {
                error = "write:" + exception.getClass().getSimpleName();
            }
        }

        return new SampleResult(name, request.paragraphs().size(), elapsedMs, usage[0], usage[1], returned,
            uncertain, unknownIds, error);
    }

    private record SampleResult(String name, int paragraphs, long elapsedMs, long inputTokens, long outputTokens,
        int returned, int uncertain, Set<String> unknownIds, String error) {

        List<String> row() {
            return List.of(name, String.valueOf(paragraphs), String.valueOf(elapsedMs), String.valueOf(inputTokens),
                String.valueOf(outputTokens), String.valueOf(returned), String.valueOf(uncertain),
                String.join(";", unknownIds), error);
        }
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
