package com.tripbler.backend.translation.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** 실제 측정 테스트의 결과 파일 규칙. 유료 호출 없이 일반 test에서 돈다. */
class PhotoLiveRunFilesTest {

    @TempDir
    Path temp;

    @Test
    void sdkLogging_setMeansReject() {
        assertThatThrownBy(() -> PhotoLiveRunFiles.rejectSdkLogging("debug")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> PhotoLiveRunFiles.rejectSdkLogging("info")).isInstanceOf(IllegalStateException.class);
        assertThatCode(() -> PhotoLiveRunFiles.rejectSdkLogging(null)).doesNotThrowAnyException();
        assertThatCode(() -> PhotoLiveRunFiles.rejectSdkLogging(" ")).doesNotThrowAnyException();
    }

    @Test
    void safeName_allowsModelNames_rejectsPathTricks() {
        assertThat(PhotoLiveRunFiles.safeName("claude-sonnet-5-5", "m")).isEqualTo("claude-sonnet-5-5");
        assertThat(PhotoLiveRunFiles.safeName("run_1.2048px", "m")).isEqualTo("run_1.2048px");

        for (String bad : List.of("", "../x", "..", "a/b", "a\\b", "C:x", ".hidden", "a..b", "a b", "x".repeat(101))) {
            assertThatThrownBy(() -> PhotoLiveRunFiles.safeName(bad, "m")).as(bad)
                .isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(() -> PhotoLiveRunFiles.safeName(null, "m")).isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void runName_defaultsToUtcTime() {
        assertThat(PhotoLiveRunFiles.runName(null, Instant.parse("2026-11-26T03:04:05Z"))).isEqualTo("20261126-030405");
        assertThat(PhotoLiveRunFiles.runName("2048px", Instant.EPOCH)).isEqualTo("2048px");
        assertThatThrownBy(() -> PhotoLiveRunFiles.runName("../up", Instant.EPOCH))
            .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void location_insideRepo_onlyUnderBuild() throws Exception {
        Path repo = Files.createDirectories(temp.resolve("repo"));
        Path build = Files.createDirectories(repo.resolve("backend/build"));
        Path outside = Files.createDirectories(temp.resolve("outside"));

        assertThat(PhotoLiveRunFiles.checkLocation(build.resolve("photo-live"), repo, build, "out"))
            .isEqualTo(build.toRealPath().resolve("photo-live"));
        assertThatCode(() -> PhotoLiveRunFiles.checkLocation(outside, repo, build, "out")).doesNotThrowAnyException();

        for (Path bad : List.of(repo.resolve("docs"), repo, repo.resolve("backend/build/../src"), repo.resolve("build"))) {
            assertThatThrownBy(() -> PhotoLiveRunFiles.checkLocation(bad, repo, build, "out")).as(bad.toString())
                .isInstanceOf(IllegalArgumentException.class);
        }

        // 저장소를 찾지 못하면(저장소 밖 실행) 확인하지 않는다.
        assertThatCode(() -> PhotoLiveRunFiles.checkLocation(repo.resolve("docs"), null, build, "out"))
            .doesNotThrowAnyException();
    }

    @Test
    void findRepoRoot_walksUpToGit() throws Exception {
        Path repo = Files.createDirectories(temp.resolve("repo"));
        Files.createDirectories(repo.resolve(".git"));
        Path nested = Files.createDirectories(repo.resolve("backend/src"));

        assertThat(PhotoLiveRunFiles.findRepoRoot(nested)).isEqualTo(repo.toAbsolutePath().normalize());
    }

    @Test
    void createRunDir_neverOverwrites() throws Exception {
        Path run = PhotoLiveRunFiles.createRunDir(temp, "claude-sonnet-5-5", "first");

        assertThat(run).isEqualTo(temp.resolve("claude-sonnet-5-5").resolve("first"));
        assertThat(Files.isDirectory(run)).isTrue();
        assertThatThrownBy(() -> PhotoLiveRunFiles.createRunDir(temp, "claude-sonnet-5-5", "first"))
            .isInstanceOf(FileAlreadyExistsException.class);
        assertThatThrownBy(() -> PhotoLiveRunFiles.createRunDir(temp, "../escape", "x"))
            .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void csvRow_quotesCommasQuotesAndNewlines() {
        assertThat(PhotoLiveRunFiles.csvRow(List.of("menu,1", "say \"hi\"", "a\nb", "plain", "")))
            .isEqualTo("\"menu,1\",\"say \"\"hi\"\"\",\"a\nb\",plain,");
        assertThat(PhotoLiveRunFiles.csvRow(java.util.Arrays.asList("x", null))).isEqualTo("x,");
    }

    @Test
    void appendRow_keepsEarlierRows() throws Exception {
        Path file = temp.resolve("samples.csv");

        PhotoLiveRunFiles.appendRow(file, List.of("sample", "error"));
        PhotoLiveRunFiles.appendRow(file, List.of("a,b", "TranslationProviderException"));

        assertThat(Files.readString(file, StandardCharsets.UTF_8))
            .isEqualTo("sample,error\n\"a,b\",TranslationProviderException\n");
    }

    @Test
    void percentile_nearestRank_emptyIsMinusOne() {
        assertThat(PhotoLiveRunFiles.percentile(List.of(), 50)).isEqualTo(-1);
        assertThat(PhotoLiveRunFiles.percentile(List.of(30L, 10L, 20L, 40L), 50)).isEqualTo(20);
        assertThat(PhotoLiveRunFiles.percentile(List.of(30L, 10L, 20L, 40L), 90)).isEqualTo(40);
    }
}
