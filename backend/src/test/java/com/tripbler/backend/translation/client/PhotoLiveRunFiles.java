package com.tripbler.backend.translation.client;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.regex.Pattern;

/**
 * 사진 번역 실제 측정(ClaudePhotoTranslationLiveIT)의 결과 파일 규칙. 유료 호출 없이 일반 테스트로 확인할 수 있게
 * 순수 로직만 모았다(PhotoLiveRunFilesTest).
 *
 * <ul>
 *   <li>SDK 디버그 로그(ANTHROPIC_LOG)가 켜져 있으면 실행하지 않는다(사진 base64·글자가 테스트 출력에 남는다).</li>
 *   <li>모델·실행 이름은 영문·숫자·{@code . _ -}만 허용한다(경로 밖으로 나가지 않게).</li>
 *   <li>결과·시료 경로가 저장소 안이면 빌드 폴더(git 제외) 아래만 허용한다.</li>
 *   <li>결과는 {@code <결과 폴더>/<모델>/<실행 이름>/}에 쓰고, 이미 있으면 실패한다(덮어쓰지 않음).</li>
 * </ul>
 */
final class PhotoLiveRunFiles {

    private static final Pattern SAFE_NAME = Pattern.compile("[A-Za-z0-9][A-Za-z0-9._-]{0,99}");
    private static final DateTimeFormatter RUN_TIME = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
        .withZone(ZoneOffset.UTC);

    private PhotoLiveRunFiles() {
    }

    static void rejectSdkLogging(String anthropicLog) {
        if (anthropicLog != null && !anthropicLog.isBlank()) {
            throw new IllegalStateException(
                "ANTHROPIC_LOG가 설정돼 있으면 실행하지 않는다(SDK가 요청·응답 본문을 테스트 출력에 남긴다).");
        }
    }

    /** 경로 한 칸으로 쓸 이름. 허용하지 않는 글자나 ".."가 있으면 실패한다. */
    static String safeName(String value, String label) {
        if (value == null || !SAFE_NAME.matcher(value).matches() || value.contains("..")) {
            throw new IllegalArgumentException(label + "은(는) 영문·숫자·. _ -만 쓸 수 있다(100자 이하, '..' 불가).");
        }
        return value;
    }

    /** 실행 이름이 없으면 UTC 시각(yyyyMMdd-HHmmss)을 쓴다. */
    static String runName(String requested, Instant now) {
        if (requested == null || requested.isBlank()) {
            return RUN_TIME.format(now);
        }
        return safeName(requested, "PHOTO_LIVE_RUN");
    }

    /**
     * 저장소 안의 경로는 빌드 폴더 아래만 허용한다. 심볼릭 링크로 돌아가지 않게 있는 부분까지 실제 경로로 바꿔 비교한다.
     * repoRoot가 null이면(저장소 밖에서 실행) 확인하지 않는다.
     */
    static Path checkLocation(Path path, Path repoRoot, Path buildDir, String label) throws IOException {
        Path resolved = realPrefix(path);
        if (repoRoot == null) {
            return resolved;
        }
        Path repo = realPrefix(repoRoot);
        Path build = realPrefix(buildDir);
        if (resolved.startsWith(repo) && !resolved.startsWith(build)) {
            throw new IllegalArgumentException(label + "가 저장소 안이면 " + build + " 아래만 쓸 수 있다: " + resolved);
        }
        return resolved;
    }

    /** 절대·정규화한 경로에서 있는 부분까지는 실제 경로(링크 해석)로 바꾸고 없는 나머지를 붙인다. */
    private static Path realPrefix(Path path) throws IOException {
        Path absolute = path.toAbsolutePath().normalize();
        Path existing = absolute;
        while (existing != null && !Files.exists(existing)) {
            existing = existing.getParent();
        }
        if (existing == null) {
            return absolute;
        }
        return existing.toRealPath().resolve(existing.relativize(absolute)).normalize();
    }

    /** start에서 위로 올라가며 .git이 있는 폴더를 찾는다. 없으면 null. */
    static Path findRepoRoot(Path start) {
        for (Path current = start.toAbsolutePath().normalize(); current != null; current = current.getParent()) {
            if (Files.exists(current.resolve(".git"))) {
                return current;
            }
        }
        return null;
    }

    /** {@code <out>/<model>/<run>}을 새로 만든다. 이미 있으면 FileAlreadyExistsException(덮어쓰지 않음). */
    static Path createRunDir(Path out, String model, String run) throws IOException {
        Path modelDir = out.resolve(safeName(model, "PHOTO_LIVE_MODEL"));
        Files.createDirectories(modelDir);
        return Files.createDirectory(modelDir.resolve(safeName(run, "PHOTO_LIVE_RUN")));
    }

    /** RFC 4180 형식의 한 줄. 쉼표·따옴표·줄바꿈이 있는 값은 따옴표로 감싸고 따옴표는 두 번 쓴다. */
    static String csvRow(List<String> values) {
        StringBuilder row = new StringBuilder();
        for (int index = 0; index < values.size(); index++) {
            if (index > 0) {
                row.append(',');
            }
            String value = values.get(index) == null ? "" : values.get(index);
            if (value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")) {
                row.append('"').append(value.replace("\"", "\"\"")).append('"');
            } else {
                row.append(value);
            }
        }
        return row.toString();
    }

    /** 파일 끝에 한 줄을 덧붙인다(없으면 만든다). 시료마다 바로 써서 중간에 멈춰도 앞 기록이 남는다. */
    static void appendRow(Path file, List<String> values) throws IOException {
        Files.writeString(file, csvRow(values) + "\n", StandardCharsets.UTF_8,
            StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    }

    /** 백분위수(가까운 순위 방식). 값이 없으면 -1. */
    static long percentile(List<Long> values, int percent) {
        if (values.isEmpty()) {
            return -1;
        }
        List<Long> sorted = values.stream().sorted().toList();
        int index = (int) Math.ceil(percent / 100.0 * sorted.size()) - 1;
        return sorted.get(Math.max(0, index));
    }
}
